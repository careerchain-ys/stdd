// agent の共通の部品（scripts/lib/shared-parts.mjs）と、生成器（scripts/build-adapters.mjs）での差し込みの振る舞いテスト。
//   node --test test/shared-parts.test.mjs
// 規約は docs/config-driven-authoring.md §10。このディレクトリ（test/）は配布対象外。
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

import { SHARED_DIR, classifyLine, expandAll, findDuplicateBlocks } from "../scripts/lib/shared-parts.mjs";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const agentsDir = path.join(repoRoot, "packages", "core", "agents");
const GENERATOR = path.join(repoRoot, "scripts", "build-adapters.mjs");

const agent = (rel, body) => ({ rel, text: `---\nname: ${rel.replace(/\.md$/, "")}\n---\n\n${body}\n` });
const part = (id, text) => ({ name: `${id}.md`, text });

// ---- 行の分類 ---------------------------------------------------------------

test("正しい形の差し込みの行を差し込みとして読む", () => {
  assert.deepEqual(classifyLine("<!-- shared: report-format -->"), { kind: "marker", id: "report-format" });
  assert.deepEqual(classifyLine("<!-- shared: a1 -->"), { kind: "marker", id: "a1" });
});

test("差し込みの書き損じを不合格の対象にする", () => {
  for (const line of [
    " <!-- shared: report-format -->", // 行頭の空白
    "<!-- shared: report-format --> ", // 行末の空白
    "<!--shared: report-format -->", // 空白落ち
    "<!-- shared report-format -->", // コロン落ち
    "<!-- SHARED: report-format -->", // 大文字
    "<!-- shared: report_format -->", // _ 区切り
    "<!-- shared: Report-Format -->", // id の大文字
    "<!-- shared: -->", // id が無い
    "- <!-- shared: report-format -->", // 行の途中
  ]) {
    assert.equal(classifyLine(line).kind, "malformed", line);
  }
});

test("通常の HTML コメントと、shared という語を含む普通の文は通す", () => {
  for (const line of [
    "<!-- .stdd.config.yml の各 apps[] について apps[].id を見出しに結果を列挙する -->",
    "部品は shared ディレクトリに置く。",
  ]) {
    assert.equal(classifyLine(line).kind, "plain", line);
  }
});

test("agent の本文で差し込みの書き方を説明すると書き損じとして扱う（説明は docs に書く）", () => {
  assert.equal(classifyLine("`<!-- shared: <id> -->` の形で書く").kind, "malformed");
});

// ---- 差し込みの解決 ---------------------------------------------------------

test("差し込みの行を部品の本文に置き換える（整合した例は合格）", () => {
  const r = expandAll(
    [agent("a.md", "前\n<!-- shared: p -->\n後"), agent("b.md", "<!-- shared: p -->\n<!-- shared: q -->")],
    [part("p", "部品 P の 1 行目\n部品 P の 2 行目\n\n"), part("q", "部品 Q")],
  );
  assert.deepEqual(r.errors, []);
  assert.equal(r.expanded.get("a.md"), "---\nname: a\n---\n\n前\n部品 P の 1 行目\n部品 P の 2 行目\n後\n");
  assert.equal(r.expanded.get("b.md"), "---\nname: b\n---\n\n部品 P の 1 行目\n部品 P の 2 行目\n部品 Q\n");
  assert.deepEqual(r.stats, { agents: 2, parts: 2, insertions: 3 });
});

test("差し込みの無い agent と通常の HTML コメントはそのまま通す", () => {
  const body = "本文\n<!-- 説明のコメント -->";
  const r = expandAll([agent("a.md", body), agent("b.md", "<!-- shared: p -->")], [part("p", "P")]);
  assert.deepEqual(r.errors, []);
  assert.equal(r.expanded.get("a.md"), agent("a.md", body).text);
});

/** 整合した例から 1 か所だけ壊し、その 1 件だけが不合格になることを確かめる。 */
function expectOneError(agents, parts, pattern) {
  const r = expandAll(agents, parts);
  assert.equal(r.errors.length, 1, r.errors.join("\n"));
  assert.match(r.errors[0], pattern);
}

test("無い部品を参照すると不合格（ファイルと行を示す）", () => {
  expectOneError([agent("a.md", "<!-- shared: p -->\n<!-- shared: missing -->")], [part("p", "P")], /a\.md:6: 部品 missing が無い/);
});

test("書き損じた差し込みは不合格", () => {
  expectOneError([agent("a.md", "<!-- shared: p -->\n<!--shared: p -->")], [part("p", "P")], /a\.md:6: 差し込みの書き方が正しくない/);
});

test("部品の中の差し込みは不合格（入れ子は解決しない）", () => {
  expectOneError(
    [agent("a.md", "<!-- shared: p -->\n<!-- shared: q -->")],
    [part("p", "P\n<!-- shared: q -->"), part("q", "Q")],
    /p\.md:2: 部品の中に差し込みは書けない/,
  );
});

test("空の部品は不合格", () => {
  expectOneError([agent("a.md", "<!-- shared: p -->")], [part("p", "P"), part("q", "\n  \n")], /q\.md: 部品が空/);
});

test("どの agent からも使われない部品は不合格", () => {
  expectOneError([agent("a.md", "<!-- shared: p -->")], [part("p", "P"), part("unused", "U")], /unused\.md: どの agent からも/);
});

test("部品のファイル名が id の形でなければ不合格", () => {
  expectOneError([agent("a.md", "<!-- shared: p -->")], [part("p", "P"), { name: "Bad_Name.md", text: "X" }], /Bad_Name\.md: 部品のファイル名/);
});

test("agent が 0 本のときは合格にしない", () => {
  expectOneError([], [], /agent の定義が 1 本も見つからない/);
});

// ---- 書き写しの検出 ---------------------------------------------------------

test("2 行以上続けて書き写した箇所を見つける", () => {
  const copied = "報告は所定の書式で書き、指摘ごとに条件と影響を書く。\n直すかどうかは呼び出し元が台帳で決める。";
  const found = findDuplicateBlocks([agent("a.md", `A 固有の文です。\n${copied}`), agent("b.md", `${copied}\nB 固有の文です。`)]);
  assert.deepEqual(
    found.map((f) => [f.rel, f.line, f.lines, f.others]),
    [
      ["a.md", 6, 2, ["b.md"]],
      ["b.md", 5, 2, ["a.md"]],
    ],
  );
});

test("長い 1 行の書き写しも見つける", () => {
  const long = "あ".repeat(80);
  assert.equal(findDuplicateBlocks([agent("a.md", long), agent("b.md", long)]).length, 2);
});

test("1 文程度の一致・差し込みの行・見出しは書き写しとして数えない", () => {
  const found = findDuplicateBlocks([
    agent("a.md", "## 編集の範囲\n\n<!-- shared: p -->\n<!-- shared: q -->\n5. **規約準拠**: AGENTS.md の規約に沿っているか"),
    agent("b.md", "## 編集の範囲\n\n<!-- shared: p -->\n<!-- shared: q -->\n5. **規約準拠**: AGENTS.md の規約に沿っているか"),
  ]);
  assert.deepEqual(found, []);
});

// ---- 配る agent の現物 -------------------------------------------------------

async function realAgents() {
  const agents = [];
  for (const f of (await fs.readdir(agentsDir)).filter((n) => n.endsWith(".md")).sort()) {
    agents.push({ rel: f, text: await fs.readFile(path.join(agentsDir, f), "utf8") });
  }
  const parts = [];
  for (const f of (await fs.readdir(path.join(agentsDir, SHARED_DIR))).sort()) {
    parts.push({ name: f, text: await fs.readFile(path.join(agentsDir, SHARED_DIR, f), "utf8") });
  }
  return { agents, parts };
}

test("配る agent の差し込みがすべて解決する", async () => {
  const { agents, parts } = await realAgents();
  const r = expandAll(agents, parts);
  assert.deepEqual(r.errors, []);
  assert.ok(r.stats.agents > 0 && r.stats.parts > 0 && r.stats.insertions > 0, JSON.stringify(r.stats));
});

test("配る agent の正本に、部品に寄せていない書き写しが無い", async () => {
  const { agents } = await realAgents();
  const found = findDuplicateBlocks(agents);
  assert.deepEqual(
    found.map((f) => `${f.rel}:${f.line}（${f.lines} 行・${f.others.join(", ")} と同じ）: ${f.sample}`),
    [],
    "共通の記述は packages/core/agents/_shared/ の部品にする（docs/config-driven-authoring.md §10）",
  );
});

test("生成物に差し込みの行と部品のファイルが残っていない", async () => {
  for (const [dir, ext] of [
    [path.join(repoRoot, ".claude", "agents"), ".md"],
    [path.join(repoRoot, ".codex", "agents"), ".toml"],
  ]) {
    const names = await fs.readdir(dir);
    assert.ok(!names.includes(SHARED_DIR), `${dir} に ${SHARED_DIR}/ を配らない`);
    const files = names.filter((n) => n.endsWith(ext));
    assert.ok(files.length > 0, `${dir} に生成物が無い`);
    for (const f of files) {
      const text = await fs.readFile(path.join(dir, f), "utf8");
      const left = text.split("\n").filter((l) => classifyLine(l).kind !== "plain");
      assert.deepEqual(left, [], `${dir}/${f}`);
    }
  }
});

// ---- 生成器の振る舞い ---------------------------------------------------------

/** 生成器が読む範囲（packages/core と MCP の定義）だけを複製した作業用のリポジトリ。 */
async function makeRoot() {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "stdd-parts-"));
  await fs.cp(path.join(repoRoot, "packages", "core"), path.join(root, "packages", "core"), { recursive: true });
  await fs.mkdir(path.join(root, "templates", "minimal"), { recursive: true });
  await fs.copyFile(path.join(repoRoot, "templates", "minimal", ".mcp.json"), path.join(root, "templates", "minimal", ".mcp.json"));
  return root;
}

const generate = (root, ...args) => spawnSync(process.execPath, [GENERATOR, "--root", root, ...args], { encoding: "utf8" });
const exists = (p) => fs.access(p).then(() => true, () => false);

test("生成器: 部品込みで生成し、--check も部品込みで一致を判定する", async () => {
  const root = await makeRoot();
  const first = generate(root);
  assert.equal(first.status, 0, first.stderr);
  assert.match(first.stdout, /agent \d+ 本・部品 \d+ 個・差し込み \d+ か所/);
  assert.equal(generate(root, "--check").status, 0);

  // 部品だけを変えると、生成物（Claude・Codex の両方）が古いとして --check が不合格になる
  const partFile = path.join(root, "packages", "core", "agents", SHARED_DIR, "report-format.md");
  await fs.appendFile(partFile, "部品に足した 1 行\n");
  const check = generate(root, "--check");
  assert.equal(check.status, 1);
  assert.match(check.stderr, /update \.claude\/agents\/\S+\.md/);
  assert.match(check.stderr, /update \.codex\/agents\/\S+\.toml/);
  await fs.rm(root, { recursive: true, force: true });
});

test("生成器: 壊れた参照があれば何も書かずに失敗する", async () => {
  const root = await makeRoot();
  const agentFile = path.join(root, "packages", "core", "agents", "code-reviewer.md");
  const text = await fs.readFile(agentFile, "utf8");
  await fs.writeFile(agentFile, text.replace("<!-- shared: report-format -->", "<!-- shared: report-formats -->"));
  const r = generate(root);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /code-reviewer\.md:\d+: 部品 report-formats が無い/);
  assert.equal(await exists(path.join(root, ".claude")), false, "失敗したときは生成物を書かない");
  await fs.rm(root, { recursive: true, force: true });
});
