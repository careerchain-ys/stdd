import fs from "node:fs/promises";
import path from "node:path";
import crypto from "node:crypto";

export class InstallError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InstallError";
  }
}

export type FileAction = "created" | "overwritten" | "merged" | "kept" | "skipped";

/** .claude/ 配下を非破壊マージした結果（相対パスのリスト）。 */
export interface ClaudeMergeSummary {
  /** 新規作成した STDD ファイル。 */
  created: string[];
  /** 既存の（未編集）STDD ファイルを最新へ更新した。 */
  updated: string[];
  /** ユーザーが STDD パスに置いた別ファイルと衝突したため触らなかった。 */
  skippedConflict: string[];
  /** ユーザーが tailoring（編集）した STDD ファイルのため保持した（--force で更新）。 */
  skippedModified: string[];
  /** 配布から外れた旧 STDD ファイル（未編集）を削除した。 */
  removed: string[];
}

export interface InstallOptions {
  /** STDD を導入する対象ディレクトリ（通常は cwd）。 */
  targetDir: string;
  /** パッケージに同梱された配布アセットのルート（.claude/ と stdd.config.yml.tpl を含む）。 */
  assetsRoot: string;
  /** .stdd.config.yml の project.name に埋める値。 */
  projectName: string;
  /** ユーザーが編集した STDD ファイルも強制的に最新へ更新するか。 */
  overwriteClaude: boolean;
  /** manifest.json に記録する STDD パッケージの版数（省略時は "0.0.0"）。 */
  version?: string;
}

export interface InstallResult {
  claude: ClaudeMergeSummary;
  settings: FileAction;
  config: FileAction;
  mcp: FileAction;
  docs: FileAction;
}

const CLAUDE_DIR = ".claude";
const SETTINGS_FILE = "settings.json";
const MANIFEST_REL = path.join(".stdd", "manifest.json");
const CONFIG_FILE = ".stdd.config.yml";
const CONFIG_TEMPLATE = "stdd.config.yml.tpl";
const MCP_FILE = ".mcp.json";
const MCP_TEMPLATE = "mcp.json";
const DOCS_DIR = "docs";

/** manifest.json に記録する 1 ファイル分のエントリ。 */
interface ManifestEntry {
  /** .claude/ からの相対パス（POSIX 区切り）。 */
  path: string;
  /** 導入時点のファイル内容の sha256。ユーザー編集検出に使う。 */
  sha256: string;
  /** 由来。常に "stdd"。 */
  source: "stdd";
}

interface Manifest {
  version: string;
  installedAt: string;
  files: ManifestEntry[];
}

/**
 * カレントプロジェクト（新規・既存いずれも）へ STDD 一式を導入する。
 * - .claude/（skill / agent / hook / rules）を **ファイル単位で非破壊マージ**して配置
 *   （ユーザーファイル・tailoring 済みファイルは保持。導入物は .claude/.stdd/manifest.json に記録）
 * - .claude/settings.json は **deep-merge**（ユーザー設定を残し STDD 設定を追記）
 * - .stdd.config.yml / .mcp.json を生成（既存なら維持）
 * - docs/ を用意
 */
export async function install(opts: InstallOptions): Promise<InstallResult> {
  const { targetDir, assetsRoot, projectName, overwriteClaude, version = "0.0.0" } = opts;

  await assertAssets(assetsRoot);
  await fs.mkdir(targetDir, { recursive: true });

  const claude = await mergeClaude(assetsRoot, targetDir, overwriteClaude, version);
  const settings = await mergeSettingsFile(assetsRoot, targetDir);
  const config = await installConfig(assetsRoot, targetDir, projectName);
  const mcp = await installMcp(assetsRoot, targetDir);
  const docs = await ensureDocs(targetDir);

  return { claude, settings, config, mcp, docs };
}

async function assertAssets(assetsRoot: string): Promise<void> {
  const claudeSrc = path.join(assetsRoot, CLAUDE_DIR);
  const tplSrc = path.join(assetsRoot, CONFIG_TEMPLATE);
  if (!(await isDir(claudeSrc))) {
    throw new InstallError(
      `配布アセットが見つかりません: ${claudeSrc}\n（パッケージのビルド時に 'npm run sync-assets' が実行されていない可能性があります）`,
    );
  }
  if (!(await isFile(tplSrc))) {
    throw new InstallError(`設定テンプレートが見つかりません: ${tplSrc}`);
  }
  const mcpSrc = path.join(assetsRoot, MCP_TEMPLATE);
  if (!(await isFile(mcpSrc))) {
    throw new InstallError(`MCP 設定テンプレートが見つかりません: ${mcpSrc}`);
  }
}

/**
 * assets/.claude/ を target/.claude/ へファイル単位で非破壊マージする。
 * settings.json は別途 deep-merge するためここでは扱わない（除外）。
 */
async function mergeClaude(
  assetsRoot: string,
  targetDir: string,
  overwrite: boolean,
  version: string,
): Promise<ClaudeMergeSummary> {
  const src = path.join(assetsRoot, CLAUDE_DIR);
  const dst = path.join(targetDir, CLAUDE_DIR);

  // 配布対象ファイル（settings.json は deep-merge 管理のため除外）
  const shipped = (await listFilesRel(src)).filter((rel) => rel !== SETTINGS_FILE);
  const prev = await readManifest(dst);
  const prevByPath = new Map(prev.files.map((f) => [f.path, f]));

  const summary: ClaudeMergeSummary = {
    created: [],
    updated: [],
    skippedConflict: [],
    skippedModified: [],
    removed: [],
  };
  const nextFiles: ManifestEntry[] = [];

  for (const rel of shipped) {
    const srcAbs = path.join(src, toNative(rel));
    const dstAbs = path.join(dst, toNative(rel));
    const content = await fs.readFile(srcAbs);
    const newHash = sha256(content);
    const recorded = prevByPath.get(rel);

    if (!(await pathExists(dstAbs))) {
      // 実体なし → 作成
      await writeFileEnsured(dstAbs, content);
      summary.created.push(rel);
      nextFiles.push({ path: rel, sha256: newHash, source: "stdd" });
      continue;
    }

    const current = await fs.readFile(dstAbs);
    const currentHash = sha256(current);

    if (!recorded) {
      // STDD 管理外のユーザーファイルが同じパスに存在 → 触らない
      summary.skippedConflict.push(rel);
      continue;
    }
    if (currentHash === newHash) {
      // 既に最新（冪等）
      nextFiles.push({ path: rel, sha256: newHash, source: "stdd" });
      continue;
    }
    if (currentHash !== recorded.sha256 && !overwrite) {
      // ユーザーが tailoring した STDD ファイル → 保持（manifest の記録は据え置き）
      summary.skippedModified.push(rel);
      nextFiles.push(recorded);
      continue;
    }
    // 未編集（or --force）→ 最新へ更新
    await writeFileEnsured(dstAbs, content);
    summary.updated.push(rel);
    nextFiles.push({ path: rel, sha256: newHash, source: "stdd" });
  }

  // orphan: 旧 manifest にあり、今回配布されない STDD ファイル。未編集なら削除。
  const shippedSet = new Set(shipped);
  for (const old of prev.files) {
    if (shippedSet.has(old.path)) continue;
    const oldAbs = path.join(dst, toNative(old.path));
    if (!(await pathExists(oldAbs))) continue;
    const currentHash = sha256(await fs.readFile(oldAbs));
    if (currentHash === old.sha256 || overwrite) {
      await fs.rm(oldAbs, { force: true });
      await pruneEmptyDirs(path.dirname(oldAbs), dst);
      summary.removed.push(old.path);
    } else {
      // ユーザーが編集していたら残し、引き続き管理対象として記録
      summary.skippedModified.push(old.path);
      nextFiles.push(old);
    }
  }

  await writeManifest(dst, nextFiles, version);
  return summary;
}

/**
 * settings.json を deep-merge して書き出す。
 * 既存が無ければ STDD 版をそのまま作成、あればマージして更新。
 */
async function mergeSettingsFile(assetsRoot: string, targetDir: string): Promise<FileAction> {
  const srcAbs = path.join(assetsRoot, CLAUDE_DIR, SETTINGS_FILE);
  if (!(await isFile(srcAbs))) return "skipped";
  const incoming = JSON.parse(await fs.readFile(srcAbs, "utf8")) as Record<string, unknown>;

  const dstAbs = path.join(targetDir, CLAUDE_DIR, SETTINGS_FILE);
  if (!(await pathExists(dstAbs))) {
    await writeFileEnsured(dstAbs, Buffer.from(`${JSON.stringify(incoming, null, 2)}\n`));
    return "created";
  }

  const existing = JSON.parse(await fs.readFile(dstAbs, "utf8")) as Record<string, unknown>;
  const merged = mergeSettings(existing, incoming);
  await fs.writeFile(dstAbs, `${JSON.stringify(merged, null, 2)}\n`);
  return "merged";
}

/**
 * Claude Code の settings.json を非破壊マージする。
 * - スカラー / オブジェクトのキー: ユーザー値を優先し、STDD 側の不足キーのみ追加
 * - 配列（permissions.allow など）: union（既存→新規の順、重複排除）
 * - hooks: イベントごとに配列を union（JSON 等価で重複排除）
 */
export function mergeSettings(
  existing: Record<string, unknown>,
  incoming: Record<string, unknown>,
): Record<string, unknown> {
  const out: Record<string, unknown> = { ...incoming, ...existing };

  for (const key of Object.keys(incoming)) {
    const a = existing[key];
    const b = incoming[key];
    if (a === undefined) {
      out[key] = b;
    } else if (Array.isArray(a) && Array.isArray(b)) {
      out[key] = unionArray(a, b);
    } else if (isPlainObject(a) && isPlainObject(b)) {
      out[key] = mergeSettings(a, b);
    } else {
      out[key] = a; // スカラー競合はユーザー優先
    }
  }
  return out;
}

function unionArray(a: unknown[], b: unknown[]): unknown[] {
  const result = [...a];
  const seen = new Set(a.map((v) => stableKey(v)));
  for (const v of b) {
    const k = stableKey(v);
    if (!seen.has(k)) {
      seen.add(k);
      result.push(v);
    }
  }
  return result;
}

function stableKey(v: unknown): string {
  return typeof v === "object" && v !== null ? JSON.stringify(v) : String(v);
}

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

async function installConfig(
  assetsRoot: string,
  targetDir: string,
  projectName: string,
): Promise<FileAction> {
  const dst = path.join(targetDir, CONFIG_FILE);
  if (await pathExists(dst)) return "kept";

  const raw = await fs.readFile(path.join(assetsRoot, CONFIG_TEMPLATE), "utf8");
  const rendered = renderTemplate(raw, { "project.name": projectName });
  await fs.writeFile(dst, rendered);
  return "created";
}

/**
 * Playwright MCP（ブラウザ動作確認用）を有効化する .mcp.json を配置する。
 * テンプレートは静的（プレースホルダ無し）。既存があれば破壊しない（維持）。
 */
async function installMcp(assetsRoot: string, targetDir: string): Promise<FileAction> {
  const dst = path.join(targetDir, MCP_FILE);
  if (await pathExists(dst)) return "kept";

  const raw = await fs.readFile(path.join(assetsRoot, MCP_TEMPLATE), "utf8");
  await fs.writeFile(dst, raw);
  return "created";
}

async function ensureDocs(targetDir: string): Promise<FileAction> {
  const dir = path.join(targetDir, DOCS_DIR);
  if (await pathExists(dir)) return "kept";
  await fs.mkdir(dir, { recursive: true });
  return "created";
}

// ---- manifest --------------------------------------------------------------

async function readManifest(claudeDir: string): Promise<Manifest> {
  const p = path.join(claudeDir, MANIFEST_REL);
  try {
    const parsed = JSON.parse(await fs.readFile(p, "utf8")) as Partial<Manifest>;
    return {
      version: parsed.version ?? "0.0.0",
      installedAt: parsed.installedAt ?? "",
      files: Array.isArray(parsed.files) ? parsed.files : [],
    };
  } catch {
    return { version: "0.0.0", installedAt: "", files: [] };
  }
}

async function writeManifest(
  claudeDir: string,
  files: ManifestEntry[],
  version: string,
): Promise<void> {
  const sorted = dedupeByPath([...files].sort((a, b) => a.path.localeCompare(b.path)));
  const manifest: Manifest = {
    version,
    installedAt: new Date().toISOString(),
    files: sorted,
  };
  const p = path.join(claudeDir, MANIFEST_REL);
  await fs.mkdir(path.dirname(p), { recursive: true });
  await fs.writeFile(p, `${JSON.stringify(manifest, null, 2)}\n`);
}

function dedupeByPath(files: ManifestEntry[]): ManifestEntry[] {
  const seen = new Set<string>();
  const out: ManifestEntry[] = [];
  for (const f of files) {
    if (seen.has(f.path)) continue;
    seen.add(f.path);
    out.push(f);
  }
  return out;
}

// ---- fs helpers ------------------------------------------------------------

/** dir 配下の全ファイルを .claude からの相対パス（POSIX 区切り）で列挙する。 */
async function listFilesRel(dir: string, base = dir): Promise<string[]> {
  const out: string[] = [];
  const entries = await fs.readdir(dir, { withFileTypes: true });
  for (const entry of entries) {
    const abs = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...(await listFilesRel(abs, base)));
    } else {
      out.push(toPosix(path.relative(base, abs)));
    }
  }
  return out;
}

async function writeFileEnsured(dstAbs: string, content: Buffer): Promise<void> {
  await fs.mkdir(path.dirname(dstAbs), { recursive: true });
  await fs.writeFile(dstAbs, content);
}

/** dir が空になったら、stopAt（含まず）まで遡って空ディレクトリを削除する。 */
async function pruneEmptyDirs(dir: string, stopAt: string): Promise<void> {
  let current = dir;
  while (current.startsWith(stopAt) && current !== stopAt) {
    let entries: string[];
    try {
      entries = await fs.readdir(current);
    } catch {
      return;
    }
    if (entries.length > 0) return;
    await fs.rm(current, { recursive: true, force: true });
    current = path.dirname(current);
  }
}

function sha256(content: Buffer): string {
  return crypto.createHash("sha256").update(content).digest("hex");
}

function toPosix(p: string): string {
  return p.split(path.sep).join("/");
}

function toNative(rel: string): string {
  return rel.split("/").join(path.sep);
}

/** {{ key }} を vars[key] に置換する。未定義のキーはそのまま残す（実行時プレースホルダ用）。 */
function renderTemplate(input: string, vars: Record<string, string>): string {
  return input.replace(
    /\{\{\s*([a-zA-Z0-9._-]+)\s*\}\}/g,
    (match, key: string) =>
      Object.prototype.hasOwnProperty.call(vars, key) ? vars[key] : match,
  );
}

async function pathExists(p: string): Promise<boolean> {
  try {
    await fs.stat(p);
    return true;
  } catch (err) {
    if (isErrnoCode(err, "ENOENT")) return false;
    throw err;
  }
}

async function isDir(p: string): Promise<boolean> {
  try {
    return (await fs.stat(p)).isDirectory();
  } catch {
    return false;
  }
}

async function isFile(p: string): Promise<boolean> {
  try {
    return (await fs.stat(p)).isFile();
  } catch {
    return false;
  }
}

function isErrnoCode(err: unknown, code: string): boolean {
  return (
    typeof err === "object" &&
    err !== null &&
    "code" in err &&
    (err as { code?: string }).code === code
  );
}
