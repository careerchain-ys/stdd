import fs from "node:fs/promises";
import path from "node:path";

export class InstallError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InstallError";
  }
}

export type FileAction = "created" | "overwritten" | "kept" | "skipped";

export interface InstallOptions {
  /** STDD を導入する対象ディレクトリ（通常は cwd）。 */
  targetDir: string;
  /** パッケージに同梱された配布アセットのルート（.claude/ と stdd.config.yml.tpl を含む）。 */
  assetsRoot: string;
  /** .stdd.config.yml の project.name に埋める値。 */
  projectName: string;
  /** 既存の .claude/ を上書きするか。false の場合は維持する。 */
  overwriteClaude: boolean;
}

export interface InstallResult {
  claude: FileAction;
  config: FileAction;
  docs: FileAction;
}

const CLAUDE_DIR = ".claude";
const CONFIG_FILE = ".stdd.config.yml";
const CONFIG_TEMPLATE = "stdd.config.yml.tpl";
const DOCS_DIR = "docs";

/**
 * カレントプロジェクト（新規・既存いずれも）へ STDD 一式を導入する。
 * - .claude/（skill / agent / hook）を配置
 * - .stdd.config.yml を生成（既存なら維持）
 * - docs/ を用意
 * 既存ファイルを不用意に破壊しない（config は維持、.claude は明示時のみ上書き）。
 */
export async function install(opts: InstallOptions): Promise<InstallResult> {
  const { targetDir, assetsRoot, projectName, overwriteClaude } = opts;

  await assertAssets(assetsRoot);
  await fs.mkdir(targetDir, { recursive: true });

  const claude = await installClaude(assetsRoot, targetDir, overwriteClaude);
  const config = await installConfig(assetsRoot, targetDir, projectName);
  const docs = await ensureDocs(targetDir);

  return { claude, config, docs };
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
}

async function installClaude(
  assetsRoot: string,
  targetDir: string,
  overwrite: boolean,
): Promise<FileAction> {
  const src = path.join(assetsRoot, CLAUDE_DIR);
  const dst = path.join(targetDir, CLAUDE_DIR);
  const exists = await pathExists(dst);

  if (exists && !overwrite) return "skipped";
  if (exists) await fs.rm(dst, { recursive: true, force: true });

  await copyTree(src, dst);
  return exists ? "overwritten" : "created";
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

async function ensureDocs(targetDir: string): Promise<FileAction> {
  const dir = path.join(targetDir, DOCS_DIR);
  if (await pathExists(dir)) return "kept";
  await fs.mkdir(dir, { recursive: true });
  return "created";
}

async function copyTree(src: string, dst: string): Promise<void> {
  await fs.mkdir(dst, { recursive: true });
  const entries = await fs.readdir(src, { withFileTypes: true });
  for (const entry of entries) {
    const srcPath = path.join(src, entry.name);
    const dstPath = path.join(dst, entry.name);
    if (entry.isDirectory()) {
      await copyTree(srcPath, dstPath);
    } else if (entry.isSymbolicLink()) {
      const link = await fs.readlink(srcPath);
      await fs.symlink(link, dstPath);
    } else {
      await fs.copyFile(srcPath, dstPath);
    }
  }
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
