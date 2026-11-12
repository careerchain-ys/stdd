// Spec の構造定義（documenting-tech-specs/references/doc-structure.json）とテンプレートの一致を確かめる。
// 検査スクリプトは章名・列名を構造定義から読むので、テンプレートと食い違うと正しい文書を不合格にする。
//
//   node --test test/doc-structure.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const skillDir = path.join(repoRoot, "packages/core/skills/documenting-tech-specs");
const structure = JSON.parse(fs.readFileSync(path.join(skillDir, "references/doc-structure.json"), "utf8"));
const LANG = "ja"; // テンプレートの本文の言語

/** テンプレートの ````markdown ～ ```` の中身（文書として書き写す部分）。 */
function templateBody(text) {
  const lines = text.split("\n");
  const start = lines.indexOf("````markdown");
  const end = lines.indexOf("````", start + 1);
  if (start < 0 || end < 0) return null;
  return lines.slice(start + 1, end);
}

function headingText(name, number) {
  if (!number) return name;
  return number.includes(".") ? `${number} ${name}` : `${number}. ${name}`;
}

/** 1 本のテンプレートを構造定義と突き合わせ、食い違いの一覧を返す（空なら一致）。 */
export function checkTemplate(doc, text, lang, common) {
  const errors = [];
  const body = templateBody(text);
  if (!body) return ["````markdown のテンプレート構造が無い"];
  const headings = body.filter((l) => /^#{1,6} /.test(l)).map((l) => l.replace(/^#{1,6} /, ""));
  for (const [key, sec] of Object.entries(doc.sections)) {
    const want = headingText(sec[lang], sec.number);
    if (!headings.some((h) => h.startsWith(want))) errors.push(`章 ${key}: 見出し「${want}」が無い`);
  }
  for (const [key, label] of Object.entries(doc.labels ?? {})) {
    if (!body.some((l) => l.includes(`**${label[lang]}**:`))) errors.push(`ラベル ${key}: 「**${label[lang]}**:」が無い`);
  }
  for (const [key, table] of Object.entries(doc.tables)) {
    const header = `| ${Object.values(table.columns).map((c) => c[lang]).join(" | ")} |`;
    if (!body.includes(header)) errors.push(`表 ${key}: 見出しの行「${header}」が無い`);
    for (const [rowKey, row] of Object.entries(table.rows ?? {})) {
      if (!body.some((l) => l.startsWith(`| ${row[lang]} |`))) errors.push(`表 ${key} の行 ${rowKey}: 「| ${row[lang]} |」が無い`);
    }
  }
  for (const [key, words] of Object.entries(doc.vocabularies ?? {})) {
    for (const w of words) if (!text.includes(`\`${w[lang]}\``)) errors.push(`語彙 ${key}: 「${w[lang]}」がテンプレートに無い`);
  }
  const versionLine = body.find((l) => l.startsWith(`${common.template_version[lang]}: `));
  if (!versionLine) {
    errors.push(`末尾の「${common.template_version[lang]}: X.Y」が無い`);
  } else {
    const version = versionLine.split(": ")[1].trim();
    const history = text.split(`## ${common.template_history[lang]}`)[1];
    if (!history) errors.push(`「## ${common.template_history[lang]}」が無い`);
    else if (!history.includes(`| ${version} |`)) errors.push(`更新履歴に版 ${version} の行が無い`);
  }
  return errors;
}

const docs = Object.entries(structure.documents);

test("構造定義に文書がある（0 件で合格にしない）", () => {
  assert.ok(docs.length >= 8, `文書の数: ${docs.length}`);
});

test("すべての名前がすべての言語で定義されている", () => {
  const missing = [];
  const visit = (obj, where) => {
    for (const [k, v] of Object.entries(obj)) {
      if (v && typeof v === "object" && !Array.isArray(v) && ("ja" in v || "en" in v)) {
        for (const lang of structure.languages) if (!v[lang]) missing.push(`${where}.${k}.${lang}`);
      } else if (Array.isArray(v)) {
        v.forEach((w, i) => structure.languages.forEach((lang) => { if (!w[lang]) missing.push(`${where}.${k}[${i}].${lang}`); }));
      } else if (v && typeof v === "object") visit(v, `${where}.${k}`);
    }
  };
  visit(structure.common, "common");
  for (const [name, doc] of docs) visit({ sections: doc.sections, labels: doc.labels ?? {}, tables: doc.tables, vocabularies: doc.vocabularies ?? {} }, name);
  assert.deepEqual(missing, []);
});

test("feature 階層のテンプレートがすべて構造定義に載っている", () => {
  const listed = new Set(docs.map(([, d]) => path.resolve(skillDir, d.template)));
  const featureTemplates = fs.readdirSync(path.join(skillDir, "templates"))
    .filter((f) => f.endsWith(".md") && !f.endsWith("-common.md"))
    .map((f) => path.join(skillDir, "templates", f));
  assert.ok(featureTemplates.length > 0);
  assert.deepEqual(featureTemplates.filter((f) => !listed.has(f)), []);
});

for (const [name, doc] of docs) {
  test(`${name}: テンプレートの章・表・版が構造定義と一致する`, () => {
    const text = fs.readFileSync(path.resolve(skillDir, doc.template), "utf8");
    assert.deepEqual(checkTemplate(doc, text, LANG, structure.common), []);
  });
}

test("食い違うテンプレートを不合格にする", () => {
  const [, doc] = docs.find(([n]) => n === "api_design");
  const text = fs.readFileSync(path.resolve(skillDir, doc.template), "utf8");
  const broken = text
    .replace("## 2. 状態遷移", "## 2. ライフサイクル")
    .replace("| コード | commonCode | HTTP | 発生条件 |", "| コード | HTTP | 発生条件 |")
    .replace("| 冪等性 |", "| 再送 |")
    .replace("テンプレート版: 1.0", "テンプレート版: 9.9");
  const errors = checkTemplate(doc, broken, LANG, structure.common);
  assert.ok(errors.some((e) => e.includes("state_transitions")), errors.join("\n"));
  assert.ok(errors.some((e) => e.includes("response_codes")), errors.join("\n"));
  assert.ok(errors.some((e) => e.includes("idempotency")), errors.join("\n"));
  assert.ok(errors.some((e) => e.includes("9.9")), errors.join("\n"));
});

test("一致しているテンプレートを不合格にしない（版の宣言が無いものは不合格）", () => {
  const [, doc] = docs.find(([n]) => n === "screen_design");
  const text = fs.readFileSync(path.resolve(skillDir, doc.template), "utf8");
  assert.deepEqual(checkTemplate(doc, text, LANG, structure.common), []);
  const noVersion = text.replace(/\nテンプレート版: [0-9.]+\n/, "\n");
  assert.ok(checkTemplate(doc, noVersion, LANG, structure.common).some((e) => e.includes("テンプレート版")));
});
