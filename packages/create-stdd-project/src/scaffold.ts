import fs from "node:fs/promises";
import path from "node:path";

export class ScaffoldError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ScaffoldError";
  }
}

export interface ScaffoldOptions {
  projectName: string;
  targetDir: string;
  repoRoot: string;
  /** templates/<template> を選択。省略時は "minimal"。 */
  template?: string;
}

export interface ScaffoldResult {
  /** プロジェクトに展開したプラグイン id の一覧。 */
  plugins: string[];
}

/** テンプレートディレクトリに置く任意のマニフェスト（template.json）。 */
interface TemplateManifest {
  plugins?: string[];
}

// template.json はプロジェクトには展開しない（CLI 内部用のマニフェスト）
const MANIFEST_FILE = "template.json";

export async function scaffold(opts: ScaffoldOptions): Promise<ScaffoldResult> {
  const { projectName, targetDir, repoRoot } = opts;
  const template = opts.template ?? "minimal";

  await assertTargetWritable(targetDir);

  const templateDir = path.join(repoRoot, "templates", template);
  const claudeDir = path.join(repoRoot, ".claude");

  await assertTemplateExists(templateDir, template, repoRoot);
  await assertDirExists(claudeDir, ".claude");

  await fs.mkdir(targetDir, { recursive: true });

  // 1. テンプレート本体を展開（.tpl は変数置換、template.json は除外）
  await copyTree({
    src: templateDir,
    dst: targetDir,
    transformTplFiles: true,
    variables: { "project.name": projectName },
    exclude: [MANIFEST_FILE],
  });

  // 2. コア .claude/（skill / agent / hook）をそのままコピー
  await copyTree({
    src: claudeDir,
    dst: path.join(targetDir, ".claude"),
    transformTplFiles: false,
    variables: {},
  });

  // 3. テンプレートが宣言するプラグインの skills/ を .claude/skills/ へ展開
  const manifest = await readManifest(templateDir);
  const plugins = manifest.plugins ?? [];
  for (const pluginId of plugins) {
    await copyPluginSkills(repoRoot, pluginId, targetDir, template);
  }

  return { plugins };
}

async function readManifest(templateDir: string): Promise<TemplateManifest> {
  const manifestPath = path.join(templateDir, MANIFEST_FILE);
  let raw: string;
  try {
    raw = await fs.readFile(manifestPath, "utf8");
  } catch (err) {
    if (isErrnoCode(err, "ENOENT")) return {};
    throw err;
  }
  try {
    const parsed = JSON.parse(raw) as TemplateManifest;
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    throw new ScaffoldError(`${MANIFEST_FILE} の JSON が不正です: ${manifestPath}`);
  }
}

async function copyPluginSkills(
  repoRoot: string,
  pluginId: string,
  targetDir: string,
  template: string,
): Promise<void> {
  // パストラバーサル防止
  if (pluginId.includes("/") || pluginId.includes("\\") || pluginId.includes("..")) {
    throw new ScaffoldError(
      `テンプレート ${template} の plugins に不正な id があります: ${pluginId}`,
    );
  }
  const pluginSkillsDir = path.join(repoRoot, "plugins", pluginId, "skills");
  try {
    const stat = await fs.stat(pluginSkillsDir);
    if (!stat.isDirectory()) {
      throw new ScaffoldError(`plugins/${pluginId}/skills がディレクトリではありません`);
    }
  } catch (err) {
    if (isErrnoCode(err, "ENOENT")) {
      throw new ScaffoldError(
        `テンプレート ${template} が要求するプラグインが見つかりません: plugins/${pluginId}/skills`,
      );
    }
    throw err;
  }

  await copyTree({
    src: pluginSkillsDir,
    dst: path.join(targetDir, ".claude", "skills"),
    transformTplFiles: false,
    variables: {},
  });
}

async function assertTemplateExists(
  templateDir: string,
  template: string,
  repoRoot: string,
): Promise<void> {
  try {
    const stat = await fs.stat(templateDir);
    if (stat.isDirectory()) return;
  } catch (err) {
    if (!isErrnoCode(err, "ENOENT")) throw err;
  }
  const available = await listTemplates(repoRoot);
  const hint = available.length > 0 ? `（利用可能: ${available.join(", ")}）` : "";
  throw new ScaffoldError(`テンプレート "${template}" が見つかりません${hint}`);
}

async function listTemplates(repoRoot: string): Promise<string[]> {
  try {
    const entries = await fs.readdir(path.join(repoRoot, "templates"), {
      withFileTypes: true,
    });
    return entries.filter((e) => e.isDirectory()).map((e) => e.name).sort();
  } catch {
    return [];
  }
}

async function assertTargetWritable(targetDir: string): Promise<void> {
  try {
    const stat = await fs.stat(targetDir);
    if (stat.isDirectory()) {
      const entries = await fs.readdir(targetDir);
      if (entries.length > 0) {
        throw new ScaffoldError(
          `ディレクトリ "${targetDir}" は既に存在し空ではありません`,
        );
      }
    } else {
      throw new ScaffoldError(
        `"${targetDir}" は既に存在し、ディレクトリではありません`,
      );
    }
  } catch (err) {
    if (isErrnoCode(err, "ENOENT")) return;
    throw err;
  }
}

async function assertDirExists(dir: string, label: string): Promise<void> {
  try {
    const stat = await fs.stat(dir);
    if (!stat.isDirectory()) {
      throw new ScaffoldError(`${label} がディレクトリではありません: ${dir}`);
    }
  } catch (err) {
    if (isErrnoCode(err, "ENOENT")) {
      throw new ScaffoldError(`${label} が見つかりません: ${dir}`);
    }
    throw err;
  }
}

interface CopyTreeOptions {
  src: string;
  dst: string;
  transformTplFiles: boolean;
  variables: Record<string, string>;
  /** コピー対象から除外するエントリ名（トップレベルのみ）。 */
  exclude?: string[];
}

async function copyTree(opts: CopyTreeOptions): Promise<void> {
  const { src, dst, transformTplFiles, variables } = opts;
  const exclude = opts.exclude ?? [];
  await fs.mkdir(dst, { recursive: true });
  const entries = await fs.readdir(src, { withFileTypes: true });

  for (const entry of entries) {
    if (exclude.includes(entry.name)) continue;
    const srcPath = path.join(src, entry.name);
    let dstName = entry.name;
    let shouldTransform = false;

    if (transformTplFiles && entry.isFile() && entry.name.endsWith(".tpl")) {
      dstName = entry.name.slice(0, -".tpl".length);
      shouldTransform = true;
    }

    const dstPath = path.join(dst, dstName);

    if (entry.isDirectory()) {
      await copyTree({
        src: srcPath,
        dst: dstPath,
        transformTplFiles,
        variables,
      });
      continue;
    }

    if (entry.isSymbolicLink()) {
      const link = await fs.readlink(srcPath);
      await fs.symlink(link, dstPath);
      continue;
    }

    if (shouldTransform) {
      const raw = await fs.readFile(srcPath, "utf8");
      const rendered = renderTemplate(raw, variables);
      await fs.writeFile(dstPath, rendered);
    } else {
      await fs.copyFile(srcPath, dstPath);
    }
  }
}

function renderTemplate(input: string, vars: Record<string, string>): string {
  return input.replace(
    /\{\{\s*([a-zA-Z0-9._-]+)\s*\}\}/g,
    (match, key: string) => {
      if (Object.prototype.hasOwnProperty.call(vars, key)) {
        return vars[key];
      }
      return match;
    },
  );
}

function isErrnoCode(err: unknown, code: string): boolean {
  return (
    typeof err === "object" &&
    err !== null &&
    "code" in err &&
    (err as { code?: string }).code === code
  );
}
