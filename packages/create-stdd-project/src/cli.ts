#!/usr/bin/env node

import { fileURLToPath } from "node:url";
import path from "node:path";
import process from "node:process";
import prompts from "prompts";
import { scaffold, ScaffoldError } from "./scaffold.js";

const PROJECT_NAME_PATTERN = /^[a-z0-9][a-z0-9._-]*$/i;

interface ParsedArgs {
  projectName: string | undefined;
  ignoredFlags: string[];
}

function parseArgs(argv: string[]): ParsedArgs {
  const args = argv.slice(2);
  const ignoredFlags: string[] = [];
  let projectName: string | undefined;

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--template") {
      ignoredFlags.push("--template");
      i++;
      continue;
    }
    if (arg.startsWith("--")) {
      ignoredFlags.push(arg);
      continue;
    }
    if (projectName === undefined) {
      projectName = arg;
    }
  }

  return { projectName, ignoredFlags };
}

function isValidProjectName(name: string): boolean {
  if (!PROJECT_NAME_PATTERN.test(name)) return false;
  if (name === "." || name === "..") return false;
  if (name.includes("/") || name.includes("\\")) return false;
  return true;
}

async function main(): Promise<void> {
  const { projectName: argProjectName, ignoredFlags } = parseArgs(process.argv);

  console.log("");
  console.log("  stdd v0.1.0  STDD ベースのプロジェクトを作成します");
  console.log("");

  if (ignoredFlags.length > 0) {
    console.warn(
      `  注意: 次のフラグは v0.1.0 では未対応のため無視されます: ${ignoredFlags.join(", ")}`,
    );
    console.warn("        (v0.2.0 以降で対応予定)");
    console.warn("");
  }

  let projectName = argProjectName;

  if (!projectName) {
    const response = await prompts({
      type: "text",
      name: "projectName",
      message: "プロジェクト名:",
      validate: (value: string) =>
        isValidProjectName(value)
          ? true
          : "英数字・ハイフン・ドット・アンダースコアのみ使用可能です",
    });
    projectName = response.projectName as string | undefined;
  } else if (!isValidProjectName(projectName)) {
    console.error(
      `  エラー: プロジェクト名 "${projectName}" に使用不可な文字が含まれています`,
    );
    console.error(
      "         (英数字・ハイフン・ドット・アンダースコアのみ使用可能)",
    );
    process.exit(1);
  }

  if (!projectName) {
    console.error("  エラー: プロジェクト名が指定されていません");
    process.exit(1);
  }

  const cwd = process.cwd();
  const targetDir = path.resolve(cwd, projectName);

  const repoRoot = path.resolve(
    path.dirname(fileURLToPath(import.meta.url)),
    "..",
    "..",
    "..",
  );

  try {
    await scaffold({
      projectName,
      targetDir,
      repoRoot,
    });
  } catch (err) {
    if (err instanceof ScaffoldError) {
      console.error(`  エラー: ${err.message}`);
      process.exit(1);
    }
    throw err;
  }

  console.log("");
  console.log(`  ✔ ${projectName}/ を作成しました`);
  console.log("");
  console.log("  次の手順:");
  console.log(`    cd ${projectName}`);
  console.log(
    '    git init && git add -A && git commit -m "chore: bootstrap with stdd"',
  );
  console.log("    claude          # Claude Code を起動");
  console.log("");
  console.log("  ドキュメント: https://github.com/careerchain-ys/stdd");
  console.log("");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
