// agent の定義に差し込む共通の部品（packages/core/agents/_shared/<id>.md）の解決。
// 規約は docs/config-driven-authoring.md §10。
//
// 判定はすべて純粋関数に置く。生成器（scripts/build-adapters.mjs）と文字数の検査
// （scripts/check-harness-size.mjs）が同じ関数で解決し、テスト（test/shared-parts.test.mjs）が振る舞いを確かめる。
//
// 書き方: agent の本文で、部品を入れたい位置に次の 1 行だけを置く（行頭から・前後に空白を置かない）。
//   <!-- shared: <id> -->
// id は英小文字・数字・ハイフン。生成物では、この行が部品の本文に置き換わる。

/** 部品の置き場（packages/core/agents からの相対）。この下のファイルは agent として扱わず、配布もしない。 */
export const SHARED_DIR = "_shared";

const ID = "[a-z0-9]+(?:-[a-z0-9]+)*";
const MARKER = new RegExp(`^<!-- shared: (${ID}) -->$`);
const PART_FILE = new RegExp(`^(${ID})\\.md$`);
/** 書き損じの網: HTML コメントの開きと `shared` を同じ行に含むもの。正しい形でなければ不合格にする。 */
const NEAR_MISS = /<!--.*shared/i;

/**
 * 1 行を分類する。
 * - marker: 正しい形の差し込み位置
 * - malformed: 差し込みを書こうとして形を誤ったもの（空白の過不足・大文字・コロン落ち・`_` 区切りなど）
 * - plain: それ以外（通常の HTML コメントを含む）
 *
 * 書き損じを plain として通すと、ただの HTML コメントとして生成物に残り、その agent から規律が黙って消える。
 * @returns {{ kind: "marker", id: string } | { kind: "malformed" } | { kind: "plain" }}
 */
export function classifyLine(line) {
  const m = MARKER.exec(line);
  if (m) return { kind: "marker", id: m[1] };
  if (NEAR_MISS.test(line)) return { kind: "malformed" };
  return { kind: "plain" };
}

/**
 * 部品のファイルを読み込む。
 * @param {Array<{ name: string, text: string }>} entries `_shared/` の直下のファイル（name はファイル名）
 * @param {string} dirLabel 診断に出す置き場の表記
 * @returns {{ parts: Map<string, string>, errors: string[] }}
 */
export function loadParts(entries, dirLabel = `packages/core/agents/${SHARED_DIR}`) {
  const parts = new Map();
  const errors = [];
  for (const { name, text } of entries) {
    const where = `${dirLabel}/${name}`;
    const m = PART_FILE.exec(name);
    if (!m) {
      errors.push(`${where}: 部品のファイル名は <id>.md（id は英小文字・数字・ハイフン）にする`);
      continue;
    }
    const body = text.replace(/\s+$/, "");
    if (body.trim() === "") {
      errors.push(`${where}: 部品が空`);
      continue;
    }
    body.split("\n").forEach((line, i) => {
      if (classifyLine(line).kind !== "plain") {
        errors.push(`${where}:${i + 1}: 部品の中に差し込みは書けない（入れ子は解決しない）: ${line.trim()}`);
      }
    });
    parts.set(m[1], body);
  }
  return { parts, errors };
}

/**
 * agent 1 本の差し込みを解決する。
 * @returns {{ text: string, used: string[], errors: string[] }}
 */
export function expandAgent(rel, text, parts, dirLabel = "packages/core/agents") {
  const errors = [];
  const used = [];
  const out = text.split("\n").map((line, i) => {
    const c = classifyLine(line);
    const where = `${dirLabel}/${rel}:${i + 1}`;
    if (c.kind === "malformed") {
      errors.push(`${where}: 差し込みの書き方が正しくない（正しい形は「<!-- shared: <id> -->」を行頭から 1 行で）: ${line.trim()}`);
      return line;
    }
    if (c.kind !== "marker") return line;
    const body = parts.get(c.id);
    if (body === undefined) {
      errors.push(`${where}: 部品 ${c.id} が無い（${SHARED_DIR}/${c.id}.md）`);
      return line;
    }
    used.push(c.id);
    return body;
  });
  return { text: out.join("\n"), used, errors };
}

/**
 * agent 全体の差し込みを解決する。
 * @param {Array<{ rel: string, text: string }>} agents agent の定義（rel は packages/core/agents からの相対）
 * @param {Array<{ name: string, text: string }>} partEntries `_shared/` の直下のファイル
 * @returns {{ expanded: Map<string, string>, errors: string[], stats: { agents: number, parts: number, insertions: number } }}
 */
export function expandAll(agents, partEntries) {
  const { parts, errors } = loadParts(partEntries);
  const expanded = new Map();
  const referenced = new Set();
  let insertions = 0;
  if (agents.length === 0) errors.push("agent の定義が 1 本も見つからない（packages/core/agents の取り違えを疑う）");
  for (const { rel, text } of agents) {
    const r = expandAgent(rel, text, parts);
    errors.push(...r.errors);
    for (const id of r.used) referenced.add(id);
    insertions += r.used.length;
    expanded.set(rel, r.text);
  }
  for (const id of parts.keys()) {
    if (!referenced.has(id)) {
      errors.push(`packages/core/agents/${SHARED_DIR}/${id}.md: どの agent からも差し込まれていない（使わないなら消す）`);
    }
  }
  return { expanded, errors, stats: { agents: agents.length, parts: parts.size, insertions } };
}

/**
 * 複数の agent の正本に書き写された箇所を探す（部品に寄せる候補）。
 *
 * ほかの agent にも同じ行がある行を「重複行」とし、重複行が minRun 行以上続く箇所か、
 * longLine 字以上の重複行を報告する。1 文程度の言い回しの一致（責務の箇条の 1 項目など）は追わない。
 * 数えない行: frontmatter・空行・見出し・コードブロックの区切り・表の区切り・差し込みの行・minLineChars 字未満の行。
 * @returns {Array<{ rel: string, line: number, lines: number, others: string[], sample: string }>} line は 1 始まり
 */
export function findDuplicateBlocks(agents, { minLineChars = 20, minRun = 2, longLine = 80 } = {}) {
  const fm = /^---\n[\s\S]*?\n---\n/;
  const files = agents.map(({ rel, text }) => {
    const head = fm.exec(text)?.[0] ?? "";
    const blank = head.split("\n").slice(0, -1).map(() => "");
    return { rel, lines: [...blank, ...text.slice(head.length).split("\n")].map((l) => l.trim()) };
  });
  const eligible = (l) =>
    [...l].length >= minLineChars && !/^(#|```|\|[\s:-]*\|)/.test(l) && classifyLine(l).kind === "plain";
  const owners = new Map();
  for (const { rel, lines } of files) {
    for (const l of lines) {
      if (!eligible(l)) continue;
      if (!owners.has(l)) owners.set(l, new Set());
      owners.get(l).add(rel);
    }
  }
  const found = [];
  for (const { rel, lines } of files) {
    let start = -1;
    const flush = (end) => {
      if (start < 0) return;
      const run = lines.slice(start, end);
      if (run.length >= minRun || run.some((l) => [...l].length >= longLine)) {
        const others = new Set();
        for (const l of run) for (const r of owners.get(l)) if (r !== rel) others.add(r);
        found.push({ rel, line: start + 1, lines: run.length, others: [...others].sort(), sample: run[0] });
      }
      start = -1;
    };
    lines.forEach((l, i) => {
      const dup = eligible(l) && owners.get(l).size > 1;
      if (dup && start < 0) start = i;
      if (!dup) flush(i);
    });
    flush(lines.length);
  }
  return found;
}
