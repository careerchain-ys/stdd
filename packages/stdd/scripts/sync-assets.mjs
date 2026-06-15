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
  {
    src: path.join(repoRoot, "templates", "minimal", ".mcp.json"),
    dst: path.join(assetsDir, "mcp.json"),
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

/**
 * 配布する settings.json にだけ Playwright MCP の有効化設定を注入する。
 * リポジトリ本体（dev 環境）の .claude/settings.json は変更せず、assets/ に
 * コピーされた生成物のみをパッチする。これにより「install した瞬間から
 * Playwright MCP がプロンプトなしで使える」状態を配布物に閉じて実現する。
 * - enabledMcpjsonServers に "playwright" を追加（MCP 承認プロンプトの抑止）
 * - permissions.allow に "mcp__playwright__*" を追加（ツール許可プロンプトの抑止）
 */
async function injectMcpSettings() {
  const settingsPath = path.join(assetsDir, ".claude", "settings.json");
  let settings;
  try {
    settings = JSON.parse(await fs.readFile(settingsPath, "utf8"));
  } catch (err) {
    if (err && err.code === "ENOENT") {
      throw new Error(`settings.json が見つかりません: ${settingsPath}`);
    }
    throw new Error(`settings.json を解析できません: ${err.message}`);
  }

  const servers = new Set(settings.enabledMcpjsonServers ?? []);
  servers.add("playwright");
  settings.enabledMcpjsonServers = [...servers];

  settings.permissions ??= {};
  const allow = new Set(settings.permissions.allow ?? []);
  allow.add("mcp__playwright__*");
  settings.permissions.allow = [...allow];

  await fs.writeFile(settingsPath, `${JSON.stringify(settings, null, 2)}\n`);
}

/**
 * 配布する skill / agent の frontmatter にだけ `source: stdd` マーカーを注入する。
 * リポジトリ本体（正典）の .claude/ は変更せず、assets/ にコピーされた生成物のみを
 * パッチする。これにより「導入先プロジェクトで STDD 由来の skill/agent が明示的に
 * 判別できる」状態を配布物に閉じて実現する（由来の一覧は manifest.json も保持）。
 * 対象: assets/.claude/skills/<name>/SKILL.md（再帰）, assets/.claude/agents/*.md
 */
async function injectStddMarker() {
  const claudeDir = path.join(assetsDir, ".claude");
  const files = [
    ...(await findFiles(path.join(claudeDir, "skills"), (name) => name === "SKILL.md")),
    ...(await findFiles(path.join(claudeDir, "agents"), (name) => name.endsWith(".md"))),
  ];
  let count = 0;
  for (const file of files) {
    if (await addSourceMarker(file)) count++;
  }
  return count;
}

/** dir 配下を再帰し、predicate(name) を満たすファイルの絶対パスを返す。dir が無ければ空配列。 */
async function findFiles(dir, predicate) {
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
    if (entry.isDirectory()) {
      out.push(...(await findFiles(abs, predicate)));
    } else if (predicate(entry.name)) {
      out.push(abs);
    }
  }
  return out;
}

/**
 * frontmatter の先頭キーとして `source: stdd` を挿入する。
 * frontmatter が無い / 既に source: がある場合は何もしない。挿入したら true。
 */
async function addSourceMarker(file) {
  const content = await fs.readFile(file, "utf8");
  if (!content.startsWith("---\n")) return false;
  const fmEnd = content.indexOf("\n---", 3);
  if (fmEnd === -1) return false;
  const frontmatter = content.slice(4, fmEnd);
  if (/^source:/m.test(frontmatter)) return false;
  const patched = `---\nsource: stdd\n${content.slice(4)}`;
  await fs.writeFile(file, patched);
  return true;
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
  await injectMcpSettings();
  const marked = await injectStddMarker();
  console.log(
    `[sync-assets] assets/ を同期しました (${COPIES.length} 件 + MCP 設定注入 + source:stdd マーカー ${marked} 件)`,
  );
}

main().catch((err) => {
  console.error(`[sync-assets] 失敗: ${err.message}`);
  process.exit(1);
});
