// install.ts の非破壊マージ挙動の検証。
// hermetic な assetsRoot を一時ディレクトリに組み、dist/install.js の公開 API を叩く。
// 実行前に `npm run build`（dist 生成）が必要。
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { install, mergeSettings, parseAgentModelOverrides, setAgentModel } from "../dist/install.js";

const MANIFEST_REL = path.join(".claude", ".stdd", "manifest.json");
const CODEX_MANIFEST_REL = path.join(".stdd", "codex-manifest.json");

/** テスト用の最小 assetsRoot を作る（.claude/ + stdd.config.yml.tpl + mcp.json）。 */
async function makeAssets() {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "stdd-assets-"));
  const claude = path.join(root, ".claude");
  await fs.mkdir(path.join(claude, "skills", "auto-implement"), { recursive: true });
  await fs.mkdir(path.join(claude, "agents"), { recursive: true });
  await fs.mkdir(path.join(claude, "hooks"), { recursive: true });
  await fs.mkdir(path.join(claude, "rules"), { recursive: true });

  await fs.writeFile(
    path.join(claude, "skills", "auto-implement", "SKILL.md"),
    "---\nname: auto-implement\nsource: stdd\n---\nbody\n",
  );
  await fs.writeFile(
    path.join(claude, "agents", "implementer.md"),
    "---\nname: implementer\nsource: stdd\n---\nbody\n",
  );
  await fs.writeFile(path.join(claude, "hooks", "spec-first-check.sh"), "#!/bin/sh\n");
  await fs.writeFile(path.join(claude, "rules", "stdd-spec-first.md"), "rule\n");
  await fs.writeFile(
    path.join(claude, "settings.json"),
    JSON.stringify(
      {
        env: { MAX_THINKING_TOKENS: "10000" },
        permissions: { allow: ["Skill", "Bash(git:*)"] },
        enabledMcpjsonServers: ["playwright"],
        hooks: {
          PreToolUse: [
            { matcher: "Bash", hooks: [{ type: "command", command: ".claude/hooks/spec-first-check.sh" }] },
          ],
        },
      },
      null,
      2,
    ),
  );

  // Codex ビューのアセット（.agents/ + .codex/）
  await fs.mkdir(path.join(root, ".agents", "skills", "auto-implement"), { recursive: true });
  await fs.writeFile(
    path.join(root, ".agents", "skills", "auto-implement", "SKILL.md"),
    "---\nname: auto-implement\n---\nbody\n",
  );
  await fs.mkdir(path.join(root, ".codex", "agents"), { recursive: true });
  await fs.writeFile(
    path.join(root, ".codex", "agents", "implementer.toml"),
    'name = "implementer"\nsandbox_mode = "workspace-write"\n',
  );
  await fs.mkdir(path.join(root, ".codex", "hooks"), { recursive: true });
  await fs.writeFile(path.join(root, ".codex", "hooks", "spec-first-check.sh"), "#!/bin/sh\n");
  await fs.writeFile(path.join(root, ".codex", "hooks.json"), '{"hooks":{}}\n');
  await fs.writeFile(path.join(root, ".codex", "config.toml"), '[mcp_servers.playwright]\ncommand = "npx"\n');

  await fs.writeFile(path.join(root, "stdd.config.yml.tpl"), 'project:\n  name: "{{project.name}}"\n');
  await fs.writeFile(path.join(root, "mcp.json"), "{}\n");
  return root;
}

async function makeTarget() {
  return fs.mkdtemp(path.join(os.tmpdir(), "stdd-target-"));
}

async function read(p) {
  return fs.readFile(p, "utf8");
}

async function exists(p) {
  try {
    await fs.stat(p);
    return true;
  } catch {
    return false;
  }
}

function baseOpts(targetDir, assetsRoot, overrides = {}) {
  return { targetDir, assetsRoot, projectName: "demo", overwriteClaude: false, ...overrides };
}

test("空ディレクトリへの新規導入: STDD 一式と manifest を作る", async () => {
  const assets = await makeAssets();
  const target = await makeTarget();

  const result = await install(baseOpts(target, assets));

  assert.ok(await exists(path.join(target, ".claude", "skills", "auto-implement", "SKILL.md")));
  assert.ok(await exists(path.join(target, ".claude", "agents", "implementer.md")));
  assert.ok(await exists(path.join(target, MANIFEST_REL)));

  const manifest = JSON.parse(await read(path.join(target, MANIFEST_REL)));
  const paths = manifest.files.map((f) => f.path);
  assert.ok(paths.includes("skills/auto-implement/SKILL.md"));
  assert.ok(paths.includes("agents/implementer.md"));
  // manifest の各エントリは由来とチェックサムを持つ
  for (const f of manifest.files) {
    assert.equal(f.source, "stdd");
    assert.match(f.sha256, /^[0-9a-f]{64}$/);
  }
  // settings.json は STDD 所有ファイルとしては列挙しない（マージ管理のため）
  assert.ok(!paths.includes("settings.json"));

  assert.deepEqual(result.claude.created.sort(), [
    "agents/implementer.md",
    "hooks/spec-first-check.sh",
    "rules/stdd-spec-first.md",
    "skills/auto-implement/SKILL.md",
  ]);
  assert.equal(result.settings, "created");
});

test("既存ユーザーファイルを汚染しない（STDD パスと衝突しない自作 skill は不可侵）", async () => {
  const assets = await makeAssets();
  const target = await makeTarget();

  const userSkill = path.join(target, ".claude", "skills", "my-skill", "SKILL.md");
  await fs.mkdir(path.dirname(userSkill), { recursive: true });
  await fs.writeFile(userSkill, "USER CONTENT\n");

  await install(baseOpts(target, assets));

  assert.equal(await read(userSkill), "USER CONTENT\n");
  // STDD 側も入っている
  assert.ok(await exists(path.join(target, ".claude", "skills", "auto-implement", "SKILL.md")));
});

test("STDD パスにユーザーが置いた同名ファイルは上書きせず skip 報告する", async () => {
  const assets = await makeAssets();
  const target = await makeTarget();

  const collide = path.join(target, ".claude", "skills", "auto-implement", "SKILL.md");
  await fs.mkdir(path.dirname(collide), { recursive: true });
  await fs.writeFile(collide, "USER OWNED\n");

  const result = await install(baseOpts(target, assets));

  assert.equal(await read(collide), "USER OWNED\n");
  assert.ok(result.claude.skippedConflict.includes("skills/auto-implement/SKILL.md"));
});

test("settings.json は deep-merge（ユーザー設定保持＋STDD 設定追記）", async () => {
  const assets = await makeAssets();
  const target = await makeTarget();

  const userSettings = path.join(target, ".claude", "settings.json");
  await fs.mkdir(path.dirname(userSettings), { recursive: true });
  await fs.writeFile(
    userSettings,
    JSON.stringify(
      {
        env: { MY_VAR: "1", MAX_THINKING_TOKENS: "99999" },
        permissions: { allow: ["Bash(docker:*)"] },
        enabledMcpjsonServers: ["other"],
      },
      null,
      2,
    ),
  );

  const result = await install(baseOpts(target, assets));
  assert.equal(result.settings, "merged");

  const merged = JSON.parse(await read(userSettings));
  // ユーザー値は保持
  assert.equal(merged.env.MY_VAR, "1");
  // 競合スカラーはユーザー優先
  assert.equal(merged.env.MAX_THINKING_TOKENS, "99999");
  // permissions / mcp サーバは union
  assert.ok(merged.permissions.allow.includes("Bash(docker:*)"));
  assert.ok(merged.permissions.allow.includes("Skill"));
  assert.ok(merged.enabledMcpjsonServers.includes("other"));
  assert.ok(merged.enabledMcpjsonServers.includes("playwright"));
  // STDD の hooks が追記される
  assert.ok(merged.hooks?.PreToolUse?.length >= 1);
});

test("再導入は冪等: 未編集の STDD ファイルは更新され、衝突エラーにならない", async () => {
  const assets = await makeAssets();
  const target = await makeTarget();

  await install(baseOpts(target, assets));
  const result = await install(baseOpts(target, assets));

  // 2 回目は created ではなく updated 側（または no-op）に入り、衝突報告は出ない
  assert.equal(result.claude.skippedConflict.length, 0);
  assert.equal(result.claude.skippedModified.length, 0);
  assert.ok(await exists(path.join(target, MANIFEST_REL)));
});

test("ユーザーが tailoring した STDD ファイルは保持し skip 報告する（--force なし）", async () => {
  const assets = await makeAssets();
  const target = await makeTarget();

  await install(baseOpts(target, assets));
  const skillPath = path.join(target, ".claude", "skills", "auto-implement", "SKILL.md");
  await fs.writeFile(skillPath, "TAILORED BY USER\n");

  const result = await install(baseOpts(target, assets));

  assert.equal(await read(skillPath), "TAILORED BY USER\n");
  assert.ok(result.claude.skippedModified.includes("skills/auto-implement/SKILL.md"));
});

test("overwriteClaude=true は tailoring 済みファイルも更新する", async () => {
  const assets = await makeAssets();
  const target = await makeTarget();

  await install(baseOpts(target, assets));
  const skillPath = path.join(target, ".claude", "skills", "auto-implement", "SKILL.md");
  await fs.writeFile(skillPath, "TAILORED BY USER\n");

  const result = await install(baseOpts(target, assets, { overwriteClaude: true }));

  assert.notEqual(await read(skillPath), "TAILORED BY USER\n");
  assert.ok(result.claude.updated.includes("skills/auto-implement/SKILL.md"));
});

test("配布から外れた旧 STDD ファイル（orphan, 未編集）は削除する", async () => {
  const assets = await makeAssets();
  const target = await makeTarget();

  await install(baseOpts(target, assets));

  // 旧バージョンで入っていた体の STDD ファイルを manifest に手で追加し、実体も置く
  const manifestPath = path.join(target, MANIFEST_REL);
  const manifest = JSON.parse(await read(manifestPath));
  const orphanRel = "skills/old-skill/SKILL.md";
  const orphanAbs = path.join(target, ".claude", "skills", "old-skill", "SKILL.md");
  await fs.mkdir(path.dirname(orphanAbs), { recursive: true });
  const orphanBody = "OLD STDD\n";
  await fs.writeFile(orphanAbs, orphanBody);
  const crypto = await import("node:crypto");
  const sha = crypto.createHash("sha256").update(orphanBody).digest("hex");
  manifest.files.push({ path: orphanRel, sha256: sha, source: "stdd" });
  await fs.writeFile(manifestPath, JSON.stringify(manifest, null, 2));

  const result = await install(baseOpts(target, assets));

  assert.ok(!(await exists(orphanAbs)));
  assert.ok(result.claude.removed.includes(orphanRel));
});

test("Codex 導入: .agents/.codex/AGENTS.md/config.toml と codex-manifest を作る", async () => {
  const assets = await makeAssets();
  const target = await makeTarget();

  const result = await install(baseOpts(target, assets, { agents: ["codex"] }));

  assert.ok(await exists(path.join(target, ".agents", "skills", "auto-implement", "SKILL.md")));
  assert.ok(await exists(path.join(target, ".codex", "agents", "implementer.toml")));
  assert.ok(await exists(path.join(target, ".codex", "hooks.json")));
  assert.ok(await exists(path.join(target, ".codex", "hooks", "spec-first-check.sh")));
  assert.ok(await exists(path.join(target, ".codex", "config.toml")));
  assert.ok(await exists(path.join(target, "AGENTS.md")));
  assert.ok(await exists(path.join(target, CODEX_MANIFEST_REL)));

  // codex-manifest はルート基準の rel を記録し、config.toml は含めない（create-if-absent 管理）
  const manifest = JSON.parse(await read(path.join(target, CODEX_MANIFEST_REL)));
  const paths = manifest.files.map((f) => f.path);
  assert.ok(paths.includes(".agents/skills/auto-implement/SKILL.md"));
  assert.ok(paths.includes(".codex/agents/implementer.toml"));
  assert.ok(paths.includes(".codex/hooks.json"));
  assert.ok(!paths.includes(".codex/config.toml"));

  // AGENTS.md にマーカーブロックが注入される
  const agentsMd = await read(path.join(target, "AGENTS.md"));
  assert.match(agentsMd, /STDD:BEGIN spec-first/);
  assert.match(agentsMd, /STDD:END spec-first/);

  // Claude ビューは作らない
  assert.equal(result.claude, undefined);
  assert.ok(result.codex.created.length > 0);
  assert.equal(result.agentsMd, "created");
  assert.equal(result.codexConfig, "created");
});

test("AGENTS.md は既存を保持し spec-first ブロックのみ注入・再導入で冪等", async () => {
  const assets = await makeAssets();
  const target = await makeTarget();
  await fs.writeFile(path.join(target, "AGENTS.md"), "# My Project\n\n既存の内容。\n");

  const r1 = await install(baseOpts(target, assets, { agents: ["codex"] }));
  assert.equal(r1.agentsMd, "merged");
  const md1 = await read(path.join(target, "AGENTS.md"));
  assert.match(md1, /既存の内容/);
  assert.match(md1, /STDD:BEGIN spec-first/);

  const r2 = await install(baseOpts(target, assets, { agents: ["codex"] }));
  assert.equal(r2.agentsMd, "kept");
  assert.equal(await read(path.join(target, "AGENTS.md")), md1);
});

test("AGENTS.md の注入ブロックは導入先に存在しないパスを案内しない", async () => {
  const assets = await makeAssets();
  const target = await makeTarget();

  await install(baseOpts(target, assets, { agents: ["codex"] }));
  const agentsMd = await read(path.join(target, "AGENTS.md"));

  // packages/core は stdd 本体リポジトリの SSoT。導入先には存在しないため案内してはならない。
  assert.ok(
    !agentsMd.includes("packages/core"),
    "注入ブロックが導入先に存在しない packages/core を案内している",
  );
  // 管理主体と再導入時の扱いは明示する。
  assert.match(agentsMd, /STDD が管理します/);
  assert.match(agentsMd, /stdd init/);
});

test("既存 .codex/config.toml は破壊しない（kept）", async () => {
  const assets = await makeAssets();
  const target = await makeTarget();
  await fs.mkdir(path.join(target, ".codex"), { recursive: true });
  await fs.writeFile(path.join(target, ".codex", "config.toml"), '[mcp_servers.custom]\ncommand = "x"\n');

  const result = await install(baseOpts(target, assets, { agents: ["codex"] }));
  assert.equal(result.codexConfig, "kept");
  assert.match(await read(path.join(target, ".codex", "config.toml")), /mcp_servers\.custom/);
});

test("agents=both は Claude と Codex 両ビューを作る", async () => {
  const assets = await makeAssets();
  const target = await makeTarget();

  const result = await install(baseOpts(target, assets, { agents: ["claude", "codex"] }));

  assert.ok(result.claude);
  assert.ok(result.codex);
  assert.ok(await exists(path.join(target, MANIFEST_REL)));
  assert.ok(await exists(path.join(target, CODEX_MANIFEST_REL)));
  assert.ok(await exists(path.join(target, ".claude", "skills", "auto-implement", "SKILL.md")));
  assert.ok(await exists(path.join(target, ".agents", "skills", "auto-implement", "SKILL.md")));
});

test("Codex 再導入は冪等（衝突/保持なし）", async () => {
  const assets = await makeAssets();
  const target = await makeTarget();

  await install(baseOpts(target, assets, { agents: ["codex"] }));
  const result = await install(baseOpts(target, assets, { agents: ["codex"] }));

  assert.equal(result.codex.skippedConflict.length, 0);
  assert.equal(result.codex.skippedModified.length, 0);
});

test("mergeSettings 単体: union と user-wins", () => {
  const existing = {
    env: { A: "user" },
    permissions: { allow: ["X"] },
    enabledMcpjsonServers: ["a"],
  };
  const incoming = {
    env: { A: "stdd", B: "stdd" },
    permissions: { allow: ["X", "Y"] },
    enabledMcpjsonServers: ["a", "b"],
    hooks: { PreToolUse: [{ matcher: "Bash", hooks: [] }] },
  };
  const out = mergeSettings(existing, incoming);
  assert.equal(out.env.A, "user");
  assert.equal(out.env.B, "stdd");
  assert.deepEqual(out.permissions.allow, ["X", "Y"]);
  assert.deepEqual(out.enabledMcpjsonServers, ["a", "b"]);
  assert.equal(out.hooks.PreToolUse.length, 1);
});

// ---- 除外の記録（削除した配布物を再導入で復活させない） -------------------------

const EXCLUSIONS_REL = path.join(".stdd", "exclusions.json");

/** skill を 2 本・フックの登録を 2 つ持つ assetsRoot（削除の検出はビューに 2 つ以上あるときに働く）。 */
async function makeRichAssets() {
  const root = await makeAssets();
  for (const base of [path.join(root, ".claude", "skills"), path.join(root, ".agents", "skills")]) {
    await fs.mkdir(path.join(base, "kaizen"), { recursive: true });
    await fs.writeFile(path.join(base, "kaizen", "SKILL.md"), "---\nname: kaizen\n---\nbody\n");
  }
  await fs.writeFile(path.join(root, ".claude", "hooks", "pre-push-check.sh"), "#!/bin/sh\n");
  const settingsPath = path.join(root, ".claude", "settings.json");
  const settings = JSON.parse(await read(settingsPath));
  settings.hooks.PreToolUse.unshift({
    matcher: "Bash",
    hooks: [{ type: "command", command: ".claude/hooks/pre-push-check.sh", timeout: 600 }],
  });
  await fs.writeFile(settingsPath, JSON.stringify(settings, null, 2));
  await fs.writeFile(
    path.join(root, ".codex", "hooks.json"),
    JSON.stringify({
      hooks: {
        PreToolUse: [
          { matcher: "Edit", hooks: [{ type: "command", command: 'bash ".codex/hooks/spec-first-check.sh"' }] },
        ],
        UserPromptSubmit: [{ hooks: [{ type: "command", command: 'bash ".codex/hooks/work-mode-prompt.sh"' }] }],
      },
    }),
  );
  return root;
}

const both = { agents: ["claude", "codex"] };

function hookCommands(settings) {
  return Object.values(settings.hooks ?? {})
    .flat()
    .flatMap((g) => g.hooks.map((h) => h.command));
}

test("削除した skill は再導入で復活せず、記録され、もう一方のビューからも外れる", async () => {
  const assets = await makeRichAssets();
  const target = await makeTarget();
  await install(baseOpts(target, assets, both));

  await fs.rm(path.join(target, ".claude", "skills", "kaizen"), { recursive: true });
  const result = await install(baseOpts(target, assets, both));

  assert.ok(!(await exists(path.join(target, ".claude", "skills", "kaizen"))));
  assert.ok(!(await exists(path.join(target, ".agents", "skills", "kaizen", "SKILL.md"))));
  assert.deepEqual(result.exclusions.detected, ["skill:kaizen"]);
  const recorded = JSON.parse(await read(path.join(target, EXCLUSIONS_REL)));
  assert.deepEqual(recorded.skills, ["kaizen"]);
  // 残した skill は通常どおり
  assert.ok(await exists(path.join(target, ".claude", "skills", "auto-implement", "SKILL.md")));

  // 3 回目も復活しない（記録が効く）。検出は 1 回だけ。
  const third = await install(baseOpts(target, assets, both));
  assert.ok(!(await exists(path.join(target, ".claude", "skills", "kaizen"))));
  assert.deepEqual(third.exclusions.detected, []);
  assert.deepEqual(third.exclusions.recorded, ["skill:kaizen"]);
});

test("--force でも除外の記録は上書きしない", async () => {
  const assets = await makeRichAssets();
  const target = await makeTarget();
  await install(baseOpts(target, assets));
  await fs.rm(path.join(target, ".claude", "skills", "kaizen"), { recursive: true });
  await install(baseOpts(target, assets, { overwriteClaude: true }));
  assert.ok(!(await exists(path.join(target, ".claude", "skills", "kaizen"))));
});

test("削除した agent は再導入で復活しない", async () => {
  const assets = await makeRichAssets();
  const target = await makeTarget();
  await install(baseOpts(target, assets));
  await fs.rm(path.join(target, ".claude", "agents", "implementer.md"));
  const result = await install(baseOpts(target, assets));
  assert.ok(!(await exists(path.join(target, ".claude", "agents", "implementer.md"))));
  assert.deepEqual(result.exclusions.detected, ["agent:implementer"]);
});

test("ビューごと消したときは導入し直しとみなし、除外を記録しない", async () => {
  const assets = await makeRichAssets();
  const target = await makeTarget();
  await install(baseOpts(target, assets, { agents: ["codex"] }));
  await fs.rm(path.join(target, ".agents"), { recursive: true });
  await fs.rm(path.join(target, ".codex", "agents"), { recursive: true });
  const result = await install(baseOpts(target, assets, { agents: ["codex"] }));
  assert.deepEqual(result.exclusions.detected, []);
  assert.ok(await exists(path.join(target, ".agents", "skills", "kaizen", "SKILL.md")));
  assert.ok(!(await exists(path.join(target, EXCLUSIONS_REL))));
});

test("skill の一部のファイルだけが消えたときは作り直す（削除とみなさない）", async () => {
  const assets = await makeRichAssets();
  await fs.writeFile(path.join(assets, ".claude", "skills", "kaizen", "notes.md"), "notes\n");
  const target = await makeTarget();
  await install(baseOpts(target, assets));
  await fs.rm(path.join(target, ".claude", "skills", "kaizen", "notes.md"));
  const result = await install(baseOpts(target, assets));
  assert.ok(await exists(path.join(target, ".claude", "skills", "kaizen", "notes.md")));
  assert.deepEqual(result.exclusions.detected, []);
});

test("--exclude は未編集の実体を消し、編集済みは残して報告する。--include で戻る", async () => {
  const assets = await makeRichAssets();
  const target = await makeTarget();
  await install(baseOpts(target, assets, both));
  const tailored = path.join(target, ".agents", "skills", "kaizen", "SKILL.md");
  await fs.writeFile(tailored, "TAILORED\n");

  const r1 = await install(baseOpts(target, assets, { ...both, exclude: ["skill:kaizen"] }));
  assert.ok(!(await exists(path.join(target, ".claude", "skills", "kaizen"))));
  assert.ok(r1.claude.removed.includes("skills/kaizen/SKILL.md"));
  assert.equal(await read(tailored), "TAILORED\n");
  assert.ok(r1.codex.skippedModified.includes(".agents/skills/kaizen/SKILL.md"));
  assert.deepEqual(r1.exclusions.recorded, ["skill:kaizen"]);
  assert.deepEqual(r1.exclusions.detected, []);

  const r2 = await install(baseOpts(target, assets, { ...both, include: ["skill:kaizen"] }));
  assert.ok(await exists(path.join(target, ".claude", "skills", "kaizen", "SKILL.md")));
  assert.deepEqual(r2.exclusions.recorded, []);
  assert.deepEqual(r2.exclusions.detected, []);
  const recorded = JSON.parse(await read(path.join(target, EXCLUSIONS_REL)));
  assert.deepEqual(recorded.skills, []);
});

test("初回の導入から --exclude で入れないものを選べる", async () => {
  const assets = await makeRichAssets();
  const target = await makeTarget();
  const result = await install(
    baseOpts(target, assets, { ...both, exclude: ["skill:kaizen", "hook:pre-push-check"] }),
  );
  assert.ok(!(await exists(path.join(target, ".claude", "skills", "kaizen"))));
  assert.ok(!(await exists(path.join(target, ".agents", "skills", "kaizen"))));
  const settings = JSON.parse(await read(path.join(target, ".claude", "settings.json")));
  assert.ok(!hookCommands(settings).some((c) => c.includes("pre-push-check")));
  assert.ok(hookCommands(settings).some((c) => c.includes("spec-first-check")));
  // フックのスクリプトの実体は残す（ほかの手順から呼ばれるため）
  assert.ok(await exists(path.join(target, ".claude", "hooks", "pre-push-check.sh")));
  assert.deepEqual(result.exclusions.recorded, ["hook:pre-push-check", "skill:kaizen"]);
});

test("settings.json から外したフックの登録は再導入で戻らず、記録される", async () => {
  const assets = await makeRichAssets();
  const target = await makeTarget();
  await install(baseOpts(target, assets));
  const settingsPath = path.join(target, ".claude", "settings.json");
  const settings = JSON.parse(await read(settingsPath));
  settings.hooks.PreToolUse = settings.hooks.PreToolUse.filter(
    (g) => !g.hooks.some((h) => h.command.includes("pre-push-check")),
  );
  await fs.writeFile(settingsPath, JSON.stringify(settings, null, 2));

  const result = await install(baseOpts(target, assets));
  const after = JSON.parse(await read(settingsPath));
  assert.ok(!hookCommands(after).some((c) => c.includes("pre-push-check")));
  assert.deepEqual(result.exclusions.detected, ["hook:pre-push-check"]);

  // --include で登録が戻る
  await install(baseOpts(target, assets, { include: ["hook:pre-push-check"] }));
  const restored = JSON.parse(await read(settingsPath));
  assert.ok(hookCommands(restored).some((c) => c.includes("pre-push-check")));
});

test("利用者が書き換えたフックの登録は残し、STDD の登録を重ねて足さない", async () => {
  const assets = await makeRichAssets();
  const target = await makeTarget();
  await install(baseOpts(target, assets));
  const settingsPath = path.join(target, ".claude", "settings.json");
  const settings = JSON.parse(await read(settingsPath));
  for (const g of settings.hooks.PreToolUse) for (const h of g.hooks) h.timeout = 5;
  await fs.writeFile(settingsPath, JSON.stringify(settings, null, 2));

  const result = await install(baseOpts(target, assets));
  const after = JSON.parse(await read(settingsPath));
  assert.equal(after.hooks.PreToolUse.length, 2);
  assert.ok(after.hooks.PreToolUse.every((g) => g.hooks.every((h) => h.timeout === 5)));
  assert.deepEqual(result.exclusions.detected, []);
});

test("配布から外れたフックの登録は settings.json から外す", async () => {
  const assets = await makeRichAssets();
  const target = await makeTarget();
  await install(baseOpts(target, assets));
  const srcSettings = path.join(assets, ".claude", "settings.json");
  const s = JSON.parse(await read(srcSettings));
  s.hooks.PreToolUse = s.hooks.PreToolUse.filter((g) => !g.hooks.some((h) => h.command.includes("pre-push")));
  await fs.writeFile(srcSettings, JSON.stringify(s, null, 2));

  const result = await install(baseOpts(target, assets));
  const after = JSON.parse(await read(path.join(target, ".claude", "settings.json")));
  assert.ok(!hookCommands(after).some((c) => c.includes("pre-push-check")));
  assert.deepEqual(result.exclusions.detected, []);
});

test("除外したフックは Codex の hooks.json の登録からも外す", async () => {
  const assets = await makeRichAssets();
  const target = await makeTarget();
  await install(baseOpts(target, assets, { agents: ["codex"], exclude: ["hook:work-mode-prompt"] }));
  const hooks = JSON.parse(await read(path.join(target, ".codex", "hooks.json")));
  assert.equal(hooks.hooks.UserPromptSubmit, undefined);
  assert.equal(hooks.hooks.PreToolUse.length, 1);
  // 再導入しても編集扱いにならない（変換後の内容で記録している）
  const again = await install(baseOpts(target, assets, { agents: ["codex"] }));
  assert.equal(again.codex.skippedModified.length, 0);
  const still = JSON.parse(await read(path.join(target, ".codex", "hooks.json")));
  assert.equal(still.hooks.UserPromptSubmit, undefined);
});

test("除外の指定の書式が誤っていればエラーにする", async () => {
  const assets = await makeRichAssets();
  const target = await makeTarget();
  await assert.rejects(install(baseOpts(target, assets, { exclude: ["kaizen"] })), /skill:<名前>/);
  await assert.rejects(install(baseOpts(target, assets, { exclude: ["plugin:x"] })), /skill:<名前>/);
});

// ---- agent のモデルの上書き（Claude のみ。packages/core/docs/model-selection.md） ----

const AGENT_MD = "---\nname: implementer\ntools: Read, Edit\nmodel: inherit\n---\nbody\n";
const CODEX_TOML = 'name = "implementer"\nsandbox_mode = "workspace-write"\n';

async function makeModelAssets() {
  const assets = await makeAssets();
  await fs.writeFile(path.join(assets, ".claude", "agents", "implementer.md"), AGENT_MD);
  return assets;
}

async function writeConfig(target, body) {
  await fs.writeFile(path.join(target, ".stdd.config.yml"), `version: 1\n${body}plugins: []\n`);
}

test("設定が無ければ agent の定義は配布物のまま（既定の model: inherit）", async () => {
  const assets = await makeModelAssets();
  const target = await makeTarget();
  const result = await install(baseOpts(target, assets, { agents: ["claude", "codex"] }));
  assert.equal(await read(path.join(target, ".claude", "agents", "implementer.md")), AGENT_MD);
  assert.equal(await read(path.join(target, ".codex", "agents", "implementer.toml")), CODEX_TOML);
  assert.equal(result.models, undefined);
});

test("models.agents の上書きは Claude の agent の定義だけに効き、Codex の生成物は変わらない", async () => {
  const assets = await makeModelAssets();
  const target = await makeTarget();
  await writeConfig(target, "models:\n  agents:\n    implementer: sonnet  # 試しに下げる\n    missing-agent: haiku\n  mechanical: haiku\n");

  const result = await install(baseOpts(target, assets, { agents: ["claude", "codex"] }));

  const md = await read(path.join(target, ".claude", "agents", "implementer.md"));
  assert.equal(md, AGENT_MD.replace("model: inherit", "model: sonnet"));
  assert.equal(await read(path.join(target, ".codex", "agents", "implementer.toml")), CODEX_TOML);
  assert.deepEqual(result.models, { applied: ["implementer: sonnet"], unknown: ["missing-agent"] });

  // 再導入は冪等。設定を外すと既定へ戻る（未編集のファイルなので更新される）
  const again = await install(baseOpts(target, assets, { agents: ["claude", "codex"] }));
  assert.deepEqual(again.claude.updated, []);
  assert.deepEqual(again.claude.skippedModified, []);
  await writeConfig(target, "");
  const reset = await install(baseOpts(target, assets, { agents: ["claude", "codex"] }));
  assert.deepEqual(reset.claude.updated, ["agents/implementer.md"]);
  assert.equal(await read(path.join(target, ".claude", "agents", "implementer.md")), AGENT_MD);
});

test("利用者が編集した agent の定義には、モデルの上書きも書かない", async () => {
  const assets = await makeModelAssets();
  const target = await makeTarget();
  await install(baseOpts(target, assets));
  const edited = AGENT_MD.replace("body", "tailored body");
  await fs.writeFile(path.join(target, ".claude", "agents", "implementer.md"), edited);
  await writeConfig(target, "models:\n  agents:\n    implementer: opus\n");
  const result = await install(baseOpts(target, assets));
  assert.equal(await read(path.join(target, ".claude", "agents", "implementer.md")), edited);
  assert.deepEqual(result.claude.skippedModified, ["agents/implementer.md"]);
});

test("models.agents にモデルの ID を書くと導入を止める", async () => {
  const assets = await makeModelAssets();
  const target = await makeTarget();
  await writeConfig(target, "models:\n  agents:\n    implementer: claude-opus-x\n");
  await assert.rejects(install(baseOpts(target, assets)), /モデルの別名/);
});

test("parseAgentModelOverrides: models.agents の対応だけを読む", () => {
  const yaml = [
    "agents: [claude]", // トップレベルの別のキーは読まない
    "models:",
    "  mechanical: haiku",
    "  agents:",
    "    # コメント",
    '    code-reviewer: "opus"',
    "    qa-engineer: sonnet # 理由",
    "  other:",
    "    implementer: haiku",
    "plugins: []",
  ].join("\n");
  assert.deepEqual(parseAgentModelOverrides(yaml), { "code-reviewer": "opus", "qa-engineer": "sonnet" });
  assert.deepEqual(parseAgentModelOverrides("version: 1\n"), {});
  assert.deepEqual(parseAgentModelOverrides("# models:\n#   agents:\n#     qa-engineer: sonnet\n"), {});
});

test("setAgentModel: model の行を書き換え、無ければ frontmatter に足す", () => {
  assert.equal(setAgentModel(AGENT_MD, "haiku"), AGENT_MD.replace("model: inherit", "model: haiku"));
  assert.equal(
    setAgentModel("---\nname: a\n---\nmodel: x\n", "opus"),
    "---\nname: a\nmodel: opus\n---\nmodel: x\n",
  );
});
