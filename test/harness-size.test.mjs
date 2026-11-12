// scripts/check-harness-size.mjs の振る舞いテスト。
//   node --test test/harness-size.test.mjs
// このディレクトリ（test/）は配布対象外。
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

import {
  charCount,
  evaluate,
  frontmatterValues,
  inventoryValue,
  measure,
  updatedBaseline,
} from "../scripts/check-harness-size.mjs";

const SCRIPT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "scripts", "check-harness-size.mjs");

const LIMITS = { skill: 100, "skill-metadata": 20, agent: 80, "agent-description": 10, rule: 50 };

/** skill 2 本・agent 1 本・rule 1 本の最小のリポジトリを作る。 */
async function makeRoot() {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "stdd-size-"));
  const core = path.join(root, "packages", "core");
  await fs.mkdir(path.join(core, "skills", "a", "references"), { recursive: true });
  await fs.mkdir(path.join(core, "skills", "b"), { recursive: true });
  await fs.mkdir(path.join(core, "agents"), { recursive: true });
  await fs.mkdir(path.join(core, "rules"), { recursive: true });
  await fs.mkdir(path.join(root, "scripts"), { recursive: true });
  await fs.writeFile(
    path.join(core, "skills", "a", "SKILL.md"),
    "---\nname: a\ndescription: |-\n  説明です\nwhen_to_use: 起動語\n---\n本文\n",
  );
  await fs.writeFile(path.join(core, "skills", "a", "references", "detail.md"), "詳細\n");
  await fs.writeFile(path.join(core, "skills", "b", "SKILL.md"), "---\nname: b\ndescription: B\n---\nB\n");
  await fs.writeFile(path.join(core, "agents", "x.md"), "---\nname: x\ndescription: 担当\n---\n役割\n");
  await fs.writeFile(path.join(core, "rules", "r.md"), "規則\n");
  return root;
}

async function writeBaseline(root, baseline) {
  await fs.writeFile(path.join(root, "scripts", "harness-size-baseline.json"), JSON.stringify(baseline, null, 2));
}

async function freshBaseline(root, extra = {}) {
  const m = await measure(root);
  const b = { limits: LIMITS, over_limit: {}, totals: { ...m.totals }, ...extra };
  await writeBaseline(root, b);
  return b;
}

function run(root, ...args) {
  try {
    const out = execFileSync(process.execPath, [SCRIPT, "--root", root, ...args], { encoding: "utf8", stdio: "pipe" });
    return { rc: 0, out };
  } catch (err) {
    return { rc: err.status, out: `${err.stdout}${err.stderr}` };
  }
}

test("文字数はコードポイントで数える（日本語 1 文字 = 1）", () => {
  assert.equal(charCount("あいう"), 3);
  assert.equal(charCount("ab"), 2);
});

test("frontmatter のブロック記法と 1 行の値を読む", () => {
  const fm = frontmatterValues("---\nname: a\ndescription: |-\n  一行目\n  二行目\nwhen_to_use: \"起動語\"\n---\n本文");
  assert.equal(fm.description, "一行目\n二行目");
  assert.equal(fm.when_to_use, "起動語");
  assert.deepEqual(frontmatterValues("frontmatter なし"), {});
});

test("種別ごとに数え、all は references/ を含む", async () => {
  const root = await makeRoot();
  const m = await measure(root);
  assert.equal(m.counts.skill, 2);
  assert.equal(m.counts.agent, 1);
  assert.equal(m.counts.rule, 1);
  assert.equal(m.counts.all, 5);
  assert.equal(m.items.find((i) => i.id === "skill-metadata:a").size, charCount("説明です\n起動語"));
  assert.equal(m.items.find((i) => i.id === "agent-description:x").size, 2);
  assert.ok(m.totals.all > m.totals.skill + m.totals.agent);
});

test("基準値どおりなら合格", async () => {
  const root = await makeRoot();
  await freshBaseline(root);
  const r = run(root);
  assert.equal(r.rc, 0, r.out);
  assert.match(r.out, /OK: skill \d+ 字\/2 件/);
});

test("総量が増えたら不合格にし、増えた量を示す", async () => {
  const root = await makeRoot();
  await freshBaseline(root);
  await fs.appendFile(path.join(root, "packages", "core", "skills", "a", "references", "detail.md"), "追記");
  const r = run(root);
  assert.equal(r.rc, 1);
  assert.match(r.out, /all の総量が基準値より増えた: \d+ → \d+ 字（\+2 字）/);
  assert.match(r.out, /--accept-growth/);
});

test("skill を 1 本足して総量が増えても不合格（1 本あたりの上限内でも検出する）", async () => {
  const root = await makeRoot();
  await freshBaseline(root);
  await fs.mkdir(path.join(root, "packages", "core", "skills", "c"));
  await fs.writeFile(path.join(root, "packages", "core", "skills", "c", "SKILL.md"), "---\nname: c\n---\nC\n");
  const r = run(root);
  assert.equal(r.rc, 1);
  assert.match(r.out, /skill の総量が基準値より増えた/);
});

test("上限を超える定義を新しく作ったら不合格", async () => {
  const root = await makeRoot();
  await fs.writeFile(path.join(root, "packages", "core", "agents", "x.md"), `---\nname: x\n---\n${"あ".repeat(100)}`);
  await freshBaseline(root);
  const r = run(root);
  assert.equal(r.rc, 1);
  assert.match(r.out, /agent:x が上限を超えている: \d+ 字 > 80 字/);
});

test("在庫に載せた超過は、その値までは通し、超えたら不合格", async () => {
  const root = await makeRoot();
  const agent = path.join(root, "packages", "core", "agents", "x.md");
  await fs.writeFile(agent, `---\nname: x\n---\n${"あ".repeat(100)}`);
  const size = charCount(await fs.readFile(agent, "utf8"));
  await freshBaseline(root, { over_limit: { "agent:x": size + 5 } });
  assert.equal(run(root).rc, 0);

  await fs.appendFile(agent, "あ".repeat(6));
  await freshBaseline(root, { over_limit: { "agent:x": size + 5 } });
  const r = run(root);
  assert.equal(r.rc, 1);
  assert.match(r.out, /agent:x が在庫の値を超えている/);
});

test("在庫の定義が消えたら台帳から外すよう不合格にする", async () => {
  const root = await makeRoot();
  await freshBaseline(root, { over_limit: { "skill:gone": 500 } });
  const r = run(root);
  assert.equal(r.rc, 1);
  assert.match(r.out, /over_limit の skill:gone に当たる定義が無い/);
});

test("対象が 0 件なら合格にしない", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "stdd-size-empty-"));
  await fs.mkdir(path.join(root, "scripts"));
  await writeBaseline(root, { limits: LIMITS, over_limit: {}, totals: {} });
  const r = run(root);
  assert.equal(r.rc, 1);
  assert.match(r.out, /1 件も見つからない/);
});

test("台帳が無ければ不合格、--root の値が無ければ引数の誤り", async () => {
  const root = await makeRoot();
  assert.equal(run(root).rc, 1);
  const r = run(root, "--update-baseline");
  assert.equal(r.rc, 1);
  try {
    execFileSync(process.execPath, [SCRIPT, "--root"], { stdio: "pipe" });
    assert.fail("exit 0 になった");
  } catch (err) {
    assert.equal(err.status, 1);
    assert.match(String(err.stderr), /--root に値が無い/);
  }
});

test("--update-baseline は減った分だけ書き、増えた分は書かない", async () => {
  const root = await makeRoot();
  const base = await freshBaseline(root);
  await fs.writeFile(path.join(root, "packages", "core", "rules", "r.md"), "規");
  await fs.appendFile(path.join(root, "packages", "core", "skills", "b", "SKILL.md"), "追記");
  const next = updatedBaseline(await measure(root), base);
  assert.ok(next.totals.rule < base.totals.rule);
  assert.equal(next.totals.skill, base.totals.skill);

  const grown = updatedBaseline(await measure(root), base, { growth: true });
  assert.ok(grown.totals.skill > base.totals.skill);
});

test("--update-baseline は上限内に戻った在庫を外し、在庫の値を締め直す", async () => {
  const m = {
    items: [
      { id: "agent:x", kind: "agent", size: 70 },
      { id: "agent:y", kind: "agent", size: 1200 },
    ],
    totals: {},
  };
  const next = updatedBaseline(m, { limits: LIMITS, over_limit: { "agent:x": 500, "agent:y": 3000 }, totals: {} });
  assert.deepEqual(next.over_limit, { "agent:y": inventoryValue(1200, "agent") });
  assert.equal(inventoryValue(1200, "agent"), 1500);
  assert.equal(inventoryValue(532, "skill-metadata"), 550);
});

test("evaluate: 減ったものは注記にとどめ、不合格にしない", () => {
  const m = {
    items: [{ id: "skill:a", kind: "skill", size: 10 }, { id: "agent:x", kind: "agent", size: 10 }],
    totals: { skill: 10, "skill-metadata": 0, agent: 10, "agent-description": 0, rule: 0, all: 20 },
    counts: { skill: 1, agent: 1 },
  };
  const { errors, notes } = evaluate(m, {
    limits: LIMITS,
    over_limit: {},
    totals: { skill: 20, "skill-metadata": 0, agent: 10, "agent-description": 0, rule: 0, all: 30 },
  });
  assert.deepEqual(errors, []);
  assert.equal(notes.length, 2);
});

test("リポジトリの台帳はいまの定義で合格する", () => {
  const out = execFileSync(process.execPath, [SCRIPT], { encoding: "utf8" });
  assert.match(out, /harness のサイズ検査 OK/);
});

test("agent は部品を差し込んだ後の文字数で数え、部品は all にだけ入る", async () => {
  const root = await makeRoot();
  const agents = path.join(root, "packages", "core", "agents");
  await fs.mkdir(path.join(agents, "_shared"), { recursive: true });
  await fs.writeFile(path.join(agents, "x.md"), "---\nname: x\ndescription: 担当\n---\n役割\n<!-- shared: p -->\n");
  await fs.writeFile(path.join(agents, "_shared", "p.md"), "部品の本文\n");
  const m = await measure(root);
  assert.equal(m.counts.agent, 1, "部品を agent として数えない");
  const x = m.items.find((it) => it.id === "agent:x");
  assert.equal(x.size, charCount("---\nname: x\ndescription: 担当\n---\n役割\n部品の本文\n"));
  assert.ok(!m.items.some((it) => it.id === "agent:p"));
});

test("部品の参照が壊れていれば、例外で止まらず不合格を表示する", async () => {
  const root = await makeRoot();
  await fs.writeFile(path.join(root, "packages", "core", "agents", "x.md"), "---\nname: x\ndescription: 担当\n---\n<!-- shared: missing -->\n");
  await freshBaseline(root).catch(() => writeBaseline(root, { limits: LIMITS, over_limit: {}, totals: {} }));
  const r = run(root);
  assert.equal(r.rc, 1);
  assert.match(r.out, /harness のサイズ検査 NG: agent の部品を解決できない.*部品 missing が無い/);
});
