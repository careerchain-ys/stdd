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

/** 導入対象のエージェント種別。 */
export type AgentTarget = "claude" | "codex";

/** ファイル単位で非破壊マージした結果（相対パスのリスト）。 */
export interface MergeSummary {
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

/** 後方互換のためのエイリアス（従来 result.claude の型名）。 */
export type ClaudeMergeSummary = MergeSummary;

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
  /** 導入するエージェントビュー（省略時は ["claude"]）。 */
  agents?: AgentTarget[];
}

export interface InstallResult {
  /** Claude ビュー（.claude/）のマージ結果。agents に "claude" を含む場合のみ。 */
  claude?: MergeSummary;
  settings?: FileAction;
  mcp?: FileAction;
  /** Codex ビュー（.agents/ + .codex/）のマージ結果。agents に "codex" を含む場合のみ。 */
  codex?: MergeSummary;
  /** AGENTS.md への spec-first ルール注入結果（Codex）。 */
  agentsMd?: FileAction;
  /** .codex/config.toml（MCP）の配置結果（Codex）。 */
  codexConfig?: FileAction;
  config: FileAction;
  docs: FileAction;
}

const CLAUDE_DIR = ".claude";
const AGENTS_DIR = ".agents";
const CODEX_DIR = ".codex";
const SETTINGS_FILE = "settings.json";
const CLAUDE_MANIFEST_REL = path.join(".claude", ".stdd", "manifest.json");
const CODEX_MANIFEST_REL = path.join(".stdd", "codex-manifest.json");
const CONFIG_FILE = ".stdd.config.yml";
const CONFIG_TEMPLATE = "stdd.config.yml.tpl";
const MCP_FILE = ".mcp.json";
const MCP_TEMPLATE = "mcp.json";
const DOCS_DIR = "docs";
const AGENTS_MD_FILE = "AGENTS.md";
const CODEX_CONFIG_REL = path.join(".codex", "config.toml");
const RULE_REL = path.join("rules", "stdd-spec-first.md");
const AGENTS_MARK_BEGIN = "<!-- STDD:BEGIN spec-first -->";
const AGENTS_MARK_END = "<!-- STDD:END spec-first -->";

/** manifest.json に記録する 1 ファイル分のエントリ。 */
interface ManifestEntry {
  /** 記録ベースからの相対パス（POSIX 区切り）。 */
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

/** 1 ファイル分のマージ指示。rel は manifest に記録する相対パス。 */
interface FileSpec {
  rel: string;
  srcAbs: string;
  dstAbs: string;
}

/**
 * カレントプロジェクト（新規・既存いずれも）へ STDD 一式を導入する。
 * - agents に応じて Claude ビュー（.claude/）と Codex ビュー（.agents/ + .codex/）を配置
 * - いずれもファイル単位の非破壊マージ（ユーザーファイル・tailoring 済みは保持、manifest で由来管理）
 * - .stdd.config.yml を生成し docs/ を用意（共通）
 */
export async function install(opts: InstallOptions): Promise<InstallResult> {
  const {
    targetDir,
    assetsRoot,
    projectName,
    overwriteClaude,
    version = "0.0.0",
    agents = ["claude"],
  } = opts;

  await assertAssets(assetsRoot, agents);
  await fs.mkdir(targetDir, { recursive: true });

  const result: InstallResult = {
    config: "skipped",
    docs: "skipped",
  };

  if (agents.includes("claude")) {
    result.claude = await mergeClaude(assetsRoot, targetDir, overwriteClaude, version);
    result.settings = await mergeSettingsFile(assetsRoot, targetDir);
    result.mcp = await installMcp(assetsRoot, targetDir);
  }

  if (agents.includes("codex")) {
    result.codex = await mergeCodex(assetsRoot, targetDir, overwriteClaude, version);
    result.agentsMd = await injectAgentsMd(assetsRoot, targetDir);
    result.codexConfig = await installCodexConfig(assetsRoot, targetDir);
  }

  result.config = await installConfig(assetsRoot, targetDir, projectName);
  result.docs = await ensureDocs(targetDir);

  return result;
}

async function assertAssets(assetsRoot: string, agents: AgentTarget[]): Promise<void> {
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
  if (agents.includes("codex")) {
    if (
      !(await isDir(path.join(assetsRoot, AGENTS_DIR))) ||
      !(await isDir(path.join(assetsRoot, CODEX_DIR)))
    ) {
      throw new InstallError(
        `Codex ビューの配布アセットが見つかりません: ${path.join(assetsRoot, AGENTS_DIR)} / ${path.join(assetsRoot, CODEX_DIR)}\n（'npm run build:adapters && npm run sync-assets' で生成されます）`,
      );
    }
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
): Promise<MergeSummary> {
  const src = path.join(assetsRoot, CLAUDE_DIR);
  const dst = path.join(targetDir, CLAUDE_DIR);
  const shipped = (await listFilesRel(src)).filter((rel) => rel !== SETTINGS_FILE);
  const specs: FileSpec[] = shipped.map((rel) => ({
    rel,
    srcAbs: path.join(src, toNative(rel)),
    dstAbs: path.join(dst, toNative(rel)),
  }));
  const manifestAbs = path.join(targetDir, CLAUDE_MANIFEST_REL);
  return mergeManagedTree(specs, manifestAbs, (rel) => path.join(dst, toNative(rel)), dst, overwrite, version);
}

/**
 * assets/.agents/ + assets/.codex/ を target へ非破壊マージする（Codex ビュー）。
 * .codex/config.toml は「無ければ作成・あれば維持」のため別扱い（specs から除外）。
 * manifest の相対パスは target ルート基準（".agents/…" / ".codex/…"）。
 */
async function mergeCodex(
  assetsRoot: string,
  targetDir: string,
  overwrite: boolean,
  version: string,
): Promise<MergeSummary> {
  const specs: FileSpec[] = [];

  const agentsSrc = path.join(assetsRoot, AGENTS_DIR);
  for (const rel of await listFilesRel(agentsSrc)) {
    specs.push({
      rel: `${AGENTS_DIR}/${rel}`,
      srcAbs: path.join(agentsSrc, toNative(rel)),
      dstAbs: path.join(targetDir, AGENTS_DIR, toNative(rel)),
    });
  }

  const codexSrc = path.join(assetsRoot, CODEX_DIR);
  for (const rel of await listFilesRel(codexSrc)) {
    if (rel === "config.toml") continue; // create-if-absent（installCodexConfig）
    specs.push({
      rel: `${CODEX_DIR}/${rel}`,
      srcAbs: path.join(codexSrc, toNative(rel)),
      dstAbs: path.join(targetDir, CODEX_DIR, toNative(rel)),
    });
  }

  const manifestAbs = path.join(targetDir, CODEX_MANIFEST_REL);
  return mergeManagedTree(
    specs,
    manifestAbs,
    (rel) => path.join(targetDir, toNative(rel)),
    targetDir,
    overwrite,
    version,
  );
}

/**
 * FileSpec 群を非破壊マージし manifest を更新する（Claude / Codex 共通の中核）。
 * - relToDstAbs: orphan 掃除で manifest の rel から実体パスを解決する
 * - pruneRoot: orphan 削除後に空ディレクトリを遡って掃除する上限（含まず）
 */
async function mergeManagedTree(
  specs: FileSpec[],
  manifestAbs: string,
  relToDstAbs: (rel: string) => string,
  pruneRoot: string,
  overwrite: boolean,
  version: string,
): Promise<MergeSummary> {
  const prev = await readManifest(manifestAbs);
  const prevByPath = new Map(prev.files.map((f) => [f.path, f]));
  const shippedSet = new Set(specs.map((s) => s.rel));

  const summary: MergeSummary = {
    created: [],
    updated: [],
    skippedConflict: [],
    skippedModified: [],
    removed: [],
  };
  const nextFiles: ManifestEntry[] = [];

  for (const { rel, srcAbs, dstAbs } of specs) {
    const content = await fs.readFile(srcAbs);
    const newHash = sha256(content);
    const recorded = prevByPath.get(rel);

    if (!(await pathExists(dstAbs))) {
      await writeFileEnsured(dstAbs, content);
      summary.created.push(rel);
      nextFiles.push({ path: rel, sha256: newHash, source: "stdd" });
      continue;
    }

    const current = await fs.readFile(dstAbs);
    const currentHash = sha256(current);

    if (!recorded) {
      summary.skippedConflict.push(rel);
      continue;
    }
    if (currentHash === newHash) {
      nextFiles.push({ path: rel, sha256: newHash, source: "stdd" });
      continue;
    }
    if (currentHash !== recorded.sha256 && !overwrite) {
      summary.skippedModified.push(rel);
      nextFiles.push(recorded);
      continue;
    }
    await writeFileEnsured(dstAbs, content);
    summary.updated.push(rel);
    nextFiles.push({ path: rel, sha256: newHash, source: "stdd" });
  }

  // orphan: 旧 manifest にあり、今回配布されない STDD ファイル。未編集なら削除。
  for (const old of prev.files) {
    if (shippedSet.has(old.path)) continue;
    const oldAbs = relToDstAbs(old.path);
    if (!(await pathExists(oldAbs))) continue;
    const currentHash = sha256(await fs.readFile(oldAbs));
    if (currentHash === old.sha256 || overwrite) {
      await fs.rm(oldAbs, { force: true });
      await pruneEmptyDirs(path.dirname(oldAbs), pruneRoot);
      summary.removed.push(old.path);
    } else {
      summary.skippedModified.push(old.path);
      nextFiles.push(old);
    }
  }

  await writeManifest(manifestAbs, nextFiles, version);
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

/**
 * spec-first ルールを downstream の AGENTS.md へ非破壊注入する（マーカー区切りブロック）。
 * - AGENTS.md が無ければブロック付きで新規作成
 * - マーカーがあれば既存ブロックを置換（冪等）、無ければ末尾に追記
 */
async function injectAgentsMd(assetsRoot: string, targetDir: string): Promise<FileAction> {
  const ruleAbs = path.join(assetsRoot, CLAUDE_DIR, RULE_REL);
  if (!(await isFile(ruleAbs))) return "skipped";
  const rule = (await fs.readFile(ruleAbs, "utf8")).trim();
  const block =
    `${AGENTS_MARK_BEGIN}\n` +
    `<!-- このブロックは STDD が管理します。編集は packages/core 側で行い、手動編集は次回 stdd init で上書きされます。 -->\n\n` +
    `${rule}\n\n` +
    `${AGENTS_MARK_END}`;

  const dst = path.join(targetDir, AGENTS_MD_FILE);
  if (!(await pathExists(dst))) {
    await writeFileEnsured(dst, Buffer.from(`# AGENTS.md\n\n${block}\n`));
    return "created";
  }

  const existing = await fs.readFile(dst, "utf8");
  const b = existing.indexOf(AGENTS_MARK_BEGIN);
  const e = existing.indexOf(AGENTS_MARK_END);
  if (b !== -1 && e !== -1 && e > b) {
    const next = existing.slice(0, b) + block + existing.slice(e + AGENTS_MARK_END.length);
    if (next === existing) return "kept";
    await fs.writeFile(dst, next);
    return "merged";
  }

  const base = existing.endsWith("\n") ? existing : `${existing}\n`;
  await fs.writeFile(dst, `${base}\n${block}\n`);
  return "merged";
}

/**
 * Codex の MCP 設定 .codex/config.toml を配置する。無ければ作成、既存は維持（破壊しない）。
 * セキュリティ鍵ではなく mcp_servers のみのため project-local に置いてよい。
 */
async function installCodexConfig(assetsRoot: string, targetDir: string): Promise<FileAction> {
  const srcAbs = path.join(assetsRoot, CODEX_DIR, "config.toml");
  if (!(await isFile(srcAbs))) return "skipped";
  const dst = path.join(targetDir, CODEX_CONFIG_REL);
  if (await pathExists(dst)) return "kept";
  await writeFileEnsured(dst, await fs.readFile(srcAbs));
  return "created";
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

async function readManifest(manifestAbs: string): Promise<Manifest> {
  try {
    const parsed = JSON.parse(await fs.readFile(manifestAbs, "utf8")) as Partial<Manifest>;
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
  manifestAbs: string,
  files: ManifestEntry[],
  version: string,
): Promise<void> {
  const sorted = dedupeByPath([...files].sort((a, b) => a.path.localeCompare(b.path)));
  const manifest: Manifest = {
    version,
    installedAt: new Date().toISOString(),
    files: sorted,
  };
  await fs.mkdir(path.dirname(manifestAbs), { recursive: true });
  await fs.writeFile(manifestAbs, `${JSON.stringify(manifest, null, 2)}\n`);
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

/** dir 配下の全ファイルを dir からの相対パス（POSIX 区切り）で列挙する。dir が無ければ空配列。 */
async function listFilesRel(dir: string, base = dir): Promise<string[]> {
  const out: string[] = [];
  let entries;
  try {
    entries = await fs.readdir(dir, { withFileTypes: true });
  } catch (err) {
    if (isErrnoCode(err, "ENOENT")) return [];
    throw err;
  }
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
