// stdd パッケージに同梱する配布アセットを、リポジトリ本体（source of truth）から
// packages/stdd/assets/ へ同期する。build / prepack の前段で実行され、npm tarball には
// この assets/ が含まれる（assets/ 自体は .gitignore 済みの生成物）。
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const packageRoot = path.resolve(scriptDir, "..");
const repoRoot = path.resolve(packageRoot, "..", "..");
const assetsDir = path.join(packageRoot, "assets");

// (source, destination) のペア。source はリポジトリ本体の正典。
const COPIES = [
  { src: path.join(repoRoot, ".claude"), dst: path.join(assetsDir, ".claude") },
  {
    src: path.join(repoRoot, "templates", "minimal", ".stdd.config.yml.tpl"),
    dst: path.join(assetsDir, "stdd.config.yml.tpl"),
  },
];

// .claude 配下でプロジェクトに持ち込まない開発専用ファイル
const EXCLUDE_NAMES = new Set([
  ".gitignore",
  "settings.local.json",
  "session-logs",
  "scheduled_tasks.lock",
]);

async function copyRecursive(src, dst) {
  const stat = await fs.stat(src);
  if (stat.isDirectory()) {
    await fs.mkdir(dst, { recursive: true });
    const entries = await fs.readdir(src, { withFileTypes: true });
    for (const entry of entries) {
      if (EXCLUDE_NAMES.has(entry.name)) continue;
      await copyRecursive(path.join(src, entry.name), path.join(dst, entry.name));
    }
  } else {
    await fs.mkdir(path.dirname(dst), { recursive: true });
    await fs.copyFile(src, dst);
  }
}

async function main() {
  await fs.rm(assetsDir, { recursive: true, force: true });
  await fs.mkdir(assetsDir, { recursive: true });
  for (const { src, dst } of COPIES) {
    try {
      await copyRecursive(src, dst);
    } catch (err) {
      if (err && err.code === "ENOENT") {
        throw new Error(`同期元が見つかりません: ${src}`);
      }
      throw err;
    }
  }
  console.log(`[sync-assets] assets/ を同期しました (${COPIES.length} 件)`);
}

main().catch((err) => {
  console.error(`[sync-assets] 失敗: ${err.message}`);
  process.exit(1);
});
