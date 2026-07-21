// STDD adapters generator.
// SSoT は packages/core/{skills,agents,hooks,rules}（エージェント非依存の中立コンテンツ）。
// 本スクリプトは core を各エージェントのネイティブ配置へ「投影（生成）」する。
// 生成物はコミットする（案 X）。編集は core 側で行い、生成物を直接編集しない。
//
// Phase 1: Claude ビュー（core → repo-root .claude/{skills,agents,hooks,rules}）のみ。
//   .claude/settings.json は Claude 固有の authored ファイルとして touch しない。
// Phase 2 で Codex ビュー（.agents/skills / .codex/agents/*.toml / .codex/hooks.json /
//   config.toml / AGENTS.md）を追加予定。
//
// 使い方:
//   node scripts/build-adapters.mjs           生成物を core から再生成する
//   node scripts/build-adapters.mjs --check    生成物が core と一致するか検査（CI 用・不一致で exit 1）
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const coreRoot = path.join(repoRoot, "packages", "core");

const CHECK = process.argv.includes("--check");

// core のサブディレクトリ → 生成先（現状は Claude ビューのみ）。
const CLAUDE_VIEW = [
  { src: path.join(coreRoot, "skills"), dst: path.join(repoRoot, ".claude", "skills") },
  { src: path.join(coreRoot, "agents"), dst: path.join(repoRoot, ".claude", "agents") },
  { src: path.join(coreRoot, "hooks"), dst: path.join(repoRoot, ".claude", "hooks") },
  { src: path.join(coreRoot, "rules"), dst: path.join(repoRoot, ".claude", "rules") },
];

/** dir 配下の全ファイルを dir からの相対パス（POSIX）で列挙。dir が無ければ空配列。 */
async function listFilesRel(dir, base = dir) {
  let entries;
  try {
    entries = await fs.readdir(dir, { withFileTypes: true });
  } catch (err) {
    if (err && err.code === "ENOENT") return [];
    throw err;
  }
  const out = [];
  for (const entry of entries) {
    const abs = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...(await listFilesRel(abs, base)));
    else out.push(path.relative(base, abs).split(path.sep).join("/"));
  }
  return out;
}

async function readIfExists(p) {
  try {
    return await fs.readFile(p);
  } catch (err) {
    if (err && err.code === "ENOENT") return null;
    throw err;
  }
}

async function modeOf(p) {
  const st = await fs.stat(p);
  return st.mode & 0o777;
}

/**
 * src ツリーを dst へミラーする（内容・実行ビットを含む）。src に無い dst ファイルは orphan として掃除。
 * CHECK モードでは書き込まず、差分（作成/更新/削除）を drift として集計する。
 */
async function mirror(src, dst, drift) {
  const srcFiles = await listFilesRel(src);
  const dstFiles = new Set(await listFilesRel(dst));

  for (const rel of srcFiles) {
    const s = path.join(src, rel);
    const d = path.join(dst, rel);
    const [srcBuf, srcMode] = [await fs.readFile(s), await modeOf(s)];
    const dstBuf = await readIfExists(d);
    const same = dstBuf !== null && dstBuf.equals(srcBuf) && (await safeMode(d)) === srcMode;
    if (!same) {
      drift.push(`${dstBuf === null ? "create" : "update"} .claude/${path.basename(dst)}/${rel}`);
      if (!CHECK) {
        await fs.mkdir(path.dirname(d), { recursive: true });
        await fs.writeFile(d, srcBuf);
        await fs.chmod(d, srcMode);
      }
    }
    dstFiles.delete(rel);
  }

  // orphan: src に無い dst ファイル
  for (const rel of dstFiles) {
    drift.push(`remove .claude/${path.basename(dst)}/${rel}`);
    if (!CHECK) await fs.rm(path.join(dst, rel), { force: true });
  }
}

async function safeMode(p) {
  try {
    return await modeOf(p);
  } catch {
    return -1;
  }
}

async function main() {
  const drift = [];
  for (const { src, dst } of CLAUDE_VIEW) await mirror(src, dst, drift);

  if (CHECK) {
    if (drift.length > 0) {
      console.error(
        `[build-adapters] ドリフト検出: 生成物が packages/core と一致しません（${drift.length} 件）。` +
          `\n編集は packages/core 側で行い 'npm run build:adapters' を実行してください。\n` +
          drift.map((d) => `  - ${d}`).join("\n"),
      );
      process.exit(1);
    }
    console.log("[build-adapters] OK: 生成物は packages/core と一致しています。");
    return;
  }

  console.log(
    drift.length === 0
      ? "[build-adapters] 変更なし（生成物は最新）。"
      : `[build-adapters] Claude ビューを再生成しました（${drift.length} 件更新）。`,
  );
}

main().catch((err) => {
  console.error(`[build-adapters] 失敗: ${err.message}`);
  process.exit(1);
});
