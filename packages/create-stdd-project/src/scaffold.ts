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
}

export async function scaffold(opts: ScaffoldOptions): Promise<void> {
  const { projectName, targetDir, repoRoot } = opts;

  await assertTargetWritable(targetDir);

  const templateDir = path.join(repoRoot, "templates", "minimal");
  const claudeDir = path.join(repoRoot, ".claude");

  await assertDirExists(templateDir, "templates/minimal");
  await assertDirExists(claudeDir, ".claude");

  await fs.mkdir(targetDir, { recursive: true });

  await copyTree({
    src: templateDir,
    dst: targetDir,
    transformTplFiles: true,
    variables: { "project.name": projectName },
  });

  await copyTree({
    src: claudeDir,
    dst: path.join(targetDir, ".claude"),
    transformTplFiles: false,
    variables: {},
  });
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
}

async function copyTree(opts: CopyTreeOptions): Promise<void> {
  const { src, dst, transformTplFiles, variables } = opts;
  await fs.mkdir(dst, { recursive: true });
  const entries = await fs.readdir(src, { withFileTypes: true });

  for (const entry of entries) {
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
