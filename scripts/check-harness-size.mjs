// skill / agent / rule の定義の文字数を検査する（オリジナルの保守用。配布はしない）。
//
// 定義の文章は読みやすさを理由に育ちやすく、エージェントが読み込む量（トークン）の増加は
// レビューでは見えにくい。そこで次の 2 つを機械で確かめる。
//
//   1. 1 本あたりの上限: 種別ごとの上限（台帳の limits）を超える定義を新しく作らない。
//      いま上限を超えているものは台帳の over_limit に在庫として載せ、その値までは許す（増やさない）。
//   2. 総量の基準値: 種別ごとの合計（台帳の totals）を、基準値より増やす変更を検出する。
//
// 種別（読み込まれる時機が違うので分けて数える）:
//   skill              skill の本体（SKILL.md 全体）。skill の起動時に読まれる
//   skill-metadata     skill の description + when_to_use。全セッションで常に読まれる
//   agent              agent の定義（.md 全体。共通の部品を差し込んだ後の文字数）。agent の起動時にシステムプロンプトへ載る
//   agent-description  agent の description。全セッションで常に読まれる
//   rule               rules/*.md。全セッションで常に読まれる
//   all                skills / agents / rules 配下の .md の合計（references/ や templates/ を含む）
//
// 文字数は Unicode のコードポイントで数える（日本語 1 文字 = 1）。
// 規約は docs/config-driven-authoring.md §7。
//
// 使い方:
//   node scripts/check-harness-size.mjs                    検査（不合格で exit 1）
//   node scripts/check-harness-size.mjs --update-baseline  減った分だけ台帳を締め直す（増やす方向には書かない）
//   node scripts/check-harness-size.mjs --accept-growth    増えた総量を台帳に書く（理由を PR に書くこと）
//   node scripts/check-harness-size.mjs --root <dir>       対象のリポジトリを指定する（テスト用）
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { SHARED_DIR, expandAll } from "./lib/shared-parts.mjs";

export const BASELINE_REL = path.join("scripts", "harness-size-baseline.json");
export const KINDS = ["skill", "skill-metadata", "agent", "agent-description", "rule", "all"];
/**
 * 在庫の値は、実測をこの幅で切り上げる（並行する小さな編集ですぐ不合格にならないように）。
 * 幅を大きくしすぎると育っても気づけないので、常に読まれる短い種別は幅を小さくする。
 */
export const INVENTORY_STEP = { skill: 500, agent: 500, rule: 500, "skill-metadata": 50, "agent-description": 50 };

export const charCount = (s) => [...s].length;

/** frontmatter（先頭の --- ブロック）からキーの値を取り出す。ブロック記法（| / |- / > / >-）にも対応する。 */
export function frontmatterValues(text) {
  const m = /^---\r?\n([\s\S]*?)\r?\n---/.exec(text);
  if (!m) return {};
  const lines = m[1].split(/\r?\n/);
  const out = {};
  for (let i = 0; i < lines.length; i++) {
    const kv = /^([A-Za-z_][\w-]*):\s?(.*)$/.exec(lines[i]);
    if (!kv) continue;
    const [, key, rest] = kv;
    if (/^[|>][+-]?\s*$/.test(rest)) {
      const body = [];
      while (i + 1 < lines.length && (/^\s/.test(lines[i + 1]) || lines[i + 1] === "")) {
        body.push(lines[++i].replace(/^\s+/, ""));
      }
      out[key] = body.join("\n").trim();
    } else {
      out[key] = rest.trim().replace(/^(["'])(.*)\1$/, "$2");
    }
  }
  return out;
}

async function listFiles(dir) {
  const out = [];
  let entries;
  try {
    entries = await fs.readdir(dir, { withFileTypes: true });
  } catch (err) {
    if (err?.code === "ENOENT") return out;
    throw err;
  }
  for (const e of entries) {
    const abs = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...(await listFiles(abs)));
    else out.push(abs);
  }
  return out;
}

/**
 * 計測する。返り値は { items: [{ id, kind, size }], totals: { kind: n }, counts: { kind: n } }。
 * id は `skill:<name>` / `skill-metadata:<name>` / `agent:<name>` / `agent-description:<name>` / `rule:<name>`。
 */
export async function measure(root) {
  const core = path.join(root, "packages", "core");
  const items = [];
  let all = 0;
  let allCount = 0;

  const skillsDir = path.join(core, "skills");
  for (const e of await fs.readdir(skillsDir, { withFileTypes: true }).catch(() => [])) {
    if (!e.isDirectory()) continue;
    const text = await fs.readFile(path.join(skillsDir, e.name, "SKILL.md"), "utf8").catch(() => null);
    if (text === null) continue;
    items.push({ id: `skill:${e.name}`, kind: "skill", size: charCount(text) });
    const fm = frontmatterValues(text);
    const meta = [fm.description, fm.when_to_use].filter(Boolean).join("\n");
    items.push({ id: `skill-metadata:${e.name}`, kind: "skill-metadata", size: charCount(meta) });
  }

  // agent は起動時に読まれる量で数えるので、部品（_shared/）を差し込んだ後の本文を測る。
  // 部品のファイルそのものは agent として数えず、all（書いた量）にだけ入る。
  const agentsDir = path.join(core, "agents");
  const sharedDir = path.join(agentsDir, SHARED_DIR);
  const agentSources = [];
  const partEntries = [];
  for (const abs of await listFiles(agentsDir)) {
    if (!abs.endsWith(".md")) continue;
    const text = await fs.readFile(abs, "utf8");
    if (path.dirname(abs) === sharedDir) partEntries.push({ name: path.basename(abs), text });
    else if (!abs.startsWith(sharedDir + path.sep)) agentSources.push({ rel: path.relative(agentsDir, abs), text });
  }
  const resolved = agentSources.length > 0 ? expandAll(agentSources, partEntries) : { expanded: new Map(), errors: [] };
  if (resolved.errors.length > 0) {
    throw new Error(`agent の部品を解決できない（npm run build:adapters で詳細を確かめる）: ${resolved.errors[0]}`);
  }
  for (const { rel } of agentSources) {
    const name = path.basename(rel, ".md");
    const text = resolved.expanded.get(rel);
    items.push({ id: `agent:${name}`, kind: "agent", size: charCount(text) });
    items.push({
      id: `agent-description:${name}`,
      kind: "agent-description",
      size: charCount(frontmatterValues(text).description ?? ""),
    });
  }

  const rulesDir = path.join(core, "rules");
  for (const abs of await listFiles(rulesDir)) {
    if (!abs.endsWith(".md")) continue;
    items.push({ id: `rule:${path.basename(abs, ".md")}`, kind: "rule", size: charCount(await fs.readFile(abs, "utf8")) });
  }

  for (const d of [skillsDir, agentsDir, rulesDir]) {
    for (const abs of await listFiles(d)) {
      if (!abs.endsWith(".md")) continue;
      all += charCount(await fs.readFile(abs, "utf8"));
      allCount++;
    }
  }

  const totals = Object.fromEntries(KINDS.map((k) => [k, 0]));
  const counts = Object.fromEntries(KINDS.map((k) => [k, 0]));
  for (const it of items) {
    totals[it.kind] += it.size;
    counts[it.kind]++;
  }
  totals.all = all;
  counts.all = allCount;
  return { items, totals, counts };
}

/** 在庫に載せる値（実測に幅を足して切り上げる）。 */
export const inventoryValue = (size, kind) => {
  const step = INVENTORY_STEP[kind] ?? 500;
  return Math.ceil((size + 1) / step) * step;
};

/**
 * 判定する（純関数）。返り値は { errors: string[], notes: string[] }。
 * errors が 1 件でもあれば不合格。notes は締め直せる箇所などの案内。
 */
export function evaluate(measured, baseline) {
  const errors = [];
  const notes = [];
  const limits = baseline.limits ?? {};
  const overLimit = baseline.over_limit ?? {};
  const totals = baseline.totals ?? {};

  if ((measured.counts.skill ?? 0) === 0 || (measured.counts.agent ?? 0) === 0) {
    errors.push("skill または agent が 1 件も見つからない（対象のディレクトリの取り違えを疑う）");
    return { errors, notes };
  }
  for (const kind of Object.keys(limits)) {
    if (!KINDS.includes(kind)) errors.push(`台帳の limits に未知の種別がある: ${kind}`);
  }

  const ids = new Set(measured.items.map((it) => it.id));
  for (const it of measured.items) {
    const limit = limits[it.kind];
    if (limit === undefined) continue;
    const allowed = overLimit[it.id];
    if (allowed === undefined) {
      if (it.size > limit) {
        errors.push(`${it.id} が上限を超えている: ${it.size} 字 > ${limit} 字（+${it.size - limit} 字）`);
      }
    } else if (it.size > allowed) {
      errors.push(`${it.id} が在庫の値を超えている: ${it.size} 字 > ${allowed} 字（在庫は増やさない）`);
    } else if (it.size <= limit) {
      notes.push(`${it.id} は上限内に収まった（${it.size} 字 ≦ ${limit} 字）。over_limit から外せる`);
    } else if (inventoryValue(it.size, it.kind) < allowed) {
      notes.push(`${it.id} の在庫の値を ${allowed} → ${inventoryValue(it.size, it.kind)} 字に締め直せる`);
    }
  }
  for (const id of Object.keys(overLimit)) {
    if (!ids.has(id)) errors.push(`over_limit の ${id} に当たる定義が無い（台帳から外す）`);
  }

  for (const kind of KINDS) {
    const base = totals[kind];
    const now = measured.totals[kind];
    if (base === undefined) {
      errors.push(`台帳の totals に ${kind} が無い`);
      continue;
    }
    if (now > base) {
      errors.push(
        `${kind} の総量が基準値より増えた: ${base} → ${now} 字（+${now - base} 字）。` +
          "増やすと決めたら --accept-growth で台帳を更新し、理由を PR に書く",
      );
    } else if (now < base) {
      notes.push(`${kind} の総量が基準値より減った: ${base} → ${now} 字。--update-baseline で締め直せる`);
    }
  }
  return { errors, notes };
}

/** 台帳を締め直す（減った分だけ）。growth=true なら増えた総量も書く。 */
export function updatedBaseline(measured, baseline, { growth = false } = {}) {
  const next = structuredClone(baseline);
  next.totals = { ...(baseline.totals ?? {}) };
  for (const kind of KINDS) {
    const base = next.totals[kind];
    const now = measured.totals[kind];
    if (base === undefined || now < base || (growth && now > base)) next.totals[kind] = now;
  }
  const sizes = new Map(measured.items.map((it) => [it.id, it]));
  const overLimit = {};
  for (const [id, allowed] of Object.entries(baseline.over_limit ?? {})) {
    const it = sizes.get(id);
    if (!it) continue;
    const limit = baseline.limits?.[it.kind];
    if (limit !== undefined && it.size <= limit) continue;
    overLimit[id] = Math.min(allowed, inventoryValue(it.size, it.kind));
  }
  next.over_limit = overLimit;
  return next;
}

function formatTotals(measured) {
  return KINDS.map((k) => `${k} ${measured.totals[k]} 字/${measured.counts[k]} 件`).join("、");
}

async function main(argv) {
  let root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
  const rootAt = argv.indexOf("--root");
  if (rootAt !== -1) {
    const v = argv[rootAt + 1];
    if (!v || v.startsWith("--")) {
      console.error("harness のサイズ検査 NG（引数）: --root に値が無い");
      return 1;
    }
    root = path.resolve(v);
  }
  const baselineAbs = path.join(root, BASELINE_REL);
  let baseline;
  try {
    baseline = JSON.parse(await fs.readFile(baselineAbs, "utf8"));
  } catch {
    console.error(`harness のサイズ検査 NG: 台帳を読めない: ${baselineAbs}`);
    return 1;
  }
  let measured;
  try {
    measured = await measure(root);
  } catch (err) {
    console.error(`harness のサイズ検査 NG: ${err.message}`);
    return 1;
  }

  if (argv.includes("--update-baseline") || argv.includes("--accept-growth")) {
    const next = updatedBaseline(measured, baseline, { growth: argv.includes("--accept-growth") });
    await fs.writeFile(baselineAbs, `${JSON.stringify(next, null, 2)}\n`);
    console.log(`台帳を更新した: ${path.relative(root, baselineAbs)}（${formatTotals(measured)}）`);
    if (argv.includes("--accept-growth")) console.log("総量を増やした理由を PR の本文に書くこと");
    return 0;
  }

  const { errors, notes } = evaluate(measured, baseline);
  for (const n of notes) console.log(`  注記: ${n}`);
  if (errors.length > 0) {
    for (const e of errors) console.error(`  NG: ${e}`);
    console.error(`harness のサイズ検査 NG（${errors.length} 件）。規約は docs/config-driven-authoring.md §7`);
    return 1;
  }
  console.log(`harness のサイズ検査 OK: ${formatTotals(measured)}`);
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = await main(process.argv.slice(2));
}
