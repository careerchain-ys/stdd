// 配る agent の役割の検査（packages/core/docs/skill-and-agent.md §4・§6）。
//   node --test test/agent-roles.test.mjs
// 書く作業はメインのセッションが skill で行うので、agent には書き込みの道具を持たせない。
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const agentsDir = path.join(root, "packages", "core", "agents");
const WRITE_TOOLS = new Set(["Edit", "Write", "MultiEdit", "NotebookEdit"]);

async function agents() {
  const names = (await fs.readdir(agentsDir)).filter((f) => f.endsWith(".md")).sort();
  return Promise.all(
    names.map(async (f) => {
      const md = await fs.readFile(path.join(agentsDir, f), "utf8");
      const fm = md.match(/^---\n([\s\S]*?)\n---/);
      const line = fm ? fm[1].split("\n").find((l) => l.startsWith("tools:")) : undefined;
      const tools = line ? line.slice("tools:".length).split(",").map((t) => t.trim()).filter(Boolean) : [];
      return { file: f, hasTools: Boolean(line), tools };
    }),
  );
}

test("どの agent も tools を明示している", async () => {
  for (const a of await agents()) assert.ok(a.hasTools, `${a.file}: tools が無いと全部の道具を持つ`);
});

test("どの agent も書き込みの道具を持たない", async () => {
  for (const a of await agents()) {
    const found = a.tools.filter((t) => WRITE_TOOLS.has(t));
    assert.deepEqual(found, [], `${a.file}: 書く作業は skill に書く（skill-and-agent.md §4）`);
  }
});

// シェルは実行して確かめる役割だけが持つ（skill-and-agent.md §4）。
// code-reviewer・test-reviewer は自分の作業ツリーで再現を実行し、qa-engineer は全件のテストを実行する。
const SHELL_AGENTS = new Set(["code-reviewer.md", "test-reviewer.md", "qa-engineer.md"]);

test("Bash を持てるのは code-reviewer・test-reviewer・qa-engineer だけ", async () => {
  for (const a of await agents()) {
    if (SHELL_AGENTS.has(a.file)) continue;
    assert.ok(!a.tools.includes("Bash"), `${a.file}: 文書のレビューにシェルは要らない（skill-and-agent.md §4）`);
  }
});

test("シェルを持つ reviewer は自分の作業ツリーで動く（isolation: worktree）", async () => {
  for (const f of ["code-reviewer.md", "test-reviewer.md"]) {
    const md = await fs.readFile(path.join(agentsDir, f), "utf8");
    const fm = md.match(/^---\n([\s\S]*?)\n---/)[1];
    assert.match(fm, /^isolation: worktree$/m, `${f}: 再現はレビューされる作業ツリーの外で実行する（agent-scope-guard.sh）`);
  }
});
