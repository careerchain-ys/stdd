// install.ts の非破壊マージ挙動の検証。
// hermetic な assetsRoot を一時ディレクトリに組み、dist/install.js の公開 API を叩く。
// 実行前に `npm run build`（dist 生成）が必要。
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { install, mergeSettings } from "../dist/install.js";

const MANIFEST_REL = path.join(".claude", ".stdd", "manifest.json");

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
