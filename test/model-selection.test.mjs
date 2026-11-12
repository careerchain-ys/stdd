// subagent のモデルの使い分け（packages/core/docs/model-selection.md）の検査。
// - 配布する agent の既定のモデルが章 §2 の表どおり（判断が中心の agent は opus から下げない）
// - Codex 向けの生成物にはモデルを出力しない
// - モデルの別名の一覧が、生成器・導入コマンド・設定の schema で一致している
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const agentsDir = path.join(repoRoot, "packages", "core", "agents");

async function agentNames() {
  return (await fs.readdir(agentsDir)).filter((f) => f.endsWith(".md")).map((f) => f.replace(/\.md$/, ""));
}

function aliasesIn(source, re) {
  const m = re.exec(source);
  assert.ok(m, `別名の一覧が見つからない: ${re}`);
  return [...m[1].matchAll(/"([a-z]+)"/g)].map((x) => x[1]);
}

// 章 packages/core/docs/model-selection.md §2 の表と同じ。変えるときは章と一緒に変える。
const EXPECTED_MODELS = {
  "requirements-reviewer": "opus",
  "tech-specs-reviewer": "opus",
  "test-reviewer": "opus",
  "code-reviewer": "opus",
  "qa-engineer": "opus",
};

test("配布する agent の既定のモデルが章 §2 の表どおり（Claude 向けの生成物も同じ）", async () => {
  assert.deepEqual((await agentNames()).sort(), Object.keys(EXPECTED_MODELS).sort(), "agent を足したら既定のモデルを決める");
  for (const [name, model] of Object.entries(EXPECTED_MODELS)) {
    for (const file of [path.join(agentsDir, `${name}.md`), path.join(repoRoot, ".claude", "agents", `${name}.md`)]) {
      const md = await fs.readFile(file, "utf8");
      const fm = md.slice(0, md.indexOf("\n---", 3));
      assert.match(fm, new RegExp(`^model: ${model}$`, "m"), file);
    }
  }
});

test("章 §2 の表が、テストの既定の一覧と一致する", async () => {
  const doc = await fs.readFile(path.join(repoRoot, "packages", "core", "docs", "model-selection.md"), "utf8");
  for (const [name, model] of Object.entries(EXPECTED_MODELS)) {
    assert.match(doc, new RegExp(`^\\| ${name} \\| \`${model}\` \\|`, "m"), name);
  }
});

test("Codex 向けの agent の生成物にはモデルを出力しない", async () => {
  for (const name of await agentNames()) {
    const toml = await fs.readFile(path.join(repoRoot, ".codex", "agents", `${name}.toml`), "utf8");
    const head = toml.slice(0, toml.indexOf("developer_instructions"));
    assert.doesNotMatch(head, /^model\s*=/m, name);
  }
});

test("モデルの別名の一覧が生成器・導入コマンド・schema で一致する", async () => {
  const build = aliasesIn(
    await fs.readFile(path.join(repoRoot, "scripts", "build-adapters.mjs"), "utf8"),
    /const MODEL_ALIASES = \[([^\]]*)\]/,
  );
  const install = aliasesIn(
    await fs.readFile(path.join(repoRoot, "packages", "stdd", "src", "install.ts"), "utf8"),
    /export const MODEL_ALIASES = \[([^\]]*)\]/,
  );
  const schema = JSON.parse(
    await fs.readFile(path.join(repoRoot, "packages", "core", "schema", ".stdd.config.schema.json"), "utf8"),
  );
  const enumValues = schema.$defs.modelAlias.enum;
  assert.deepEqual(build, enumValues);
  assert.deepEqual(install, enumValues);
  assert.ok(enumValues.includes("inherit"));
  assert.ok(enumValues.every((v) => !v.startsWith("claude-")));
});
