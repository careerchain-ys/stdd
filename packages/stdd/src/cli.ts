#!/usr/bin/env node

import { fileURLToPath } from "node:url";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import prompts from "prompts";
import { install, InstallError, type FileAction } from "./install.js";

const packageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const assetsRoot = path.join(packageRoot, "assets");
const VERSION = readVersion();

interface InitFlags {
  force: boolean;
  yes: boolean;
  name: string | undefined;
}

function readVersion(): string {
  try {
    const raw = fs.readFileSync(path.join(packageRoot, "package.json"), "utf8");
    return (JSON.parse(raw).version as string) ?? "0.0.0";
  } catch {
    return "0.0.0";
  }
}

function printHelp(): void {
  console.log(`
  stdd v${VERSION}  STDD (Spec and Test Driven Development) インストーラ

  使い方:
    npx @careerchain/stdd init [options]    現在のディレクトリに STDD を導入する（新規・既存どちらも可）

  options:
    --name <name>   .stdd.config.yml の project.name（既定: ディレクトリ名）
    --force         確認なしで既存の .claude/ を上書きする
    --yes, -y       対話プロンプトをスキップし既定値で進める
    --help, -h      このヘルプを表示
    --version, -v   バージョンを表示

  導入後の流れ:
    1. claude を起動
    2. 「STDD を導入して」と伝える
       → 新規 / 既存を自動判定し、適切なスキルが起動します
`);
}

function parseInitFlags(args: string[]): InitFlags {
  const flags: InitFlags = { force: false, yes: false, name: undefined };
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--force") flags.force = true;
    else if (arg === "--yes" || arg === "-y") flags.yes = true;
    else if (arg === "--name") flags.name = args[++i];
    else if (arg.startsWith("--name=")) flags.name = arg.slice("--name=".length);
    else console.warn(`  注意: 未対応のオプションを無視します: ${arg}`);
  }
  return flags;
}

function deriveProjectName(cwd: string, override: string | undefined): string {
  const raw = (override ?? path.basename(cwd)).trim();
  // YAML のダブルクォート文字列に埋めるため、安全でない文字は除去する。
  const cleaned = raw.replace(/["\\]/g, "");
  return cleaned.length > 0 ? cleaned : "my-stdd-project";
}

const ACTION_LABEL: Record<FileAction, string> = {
  created: "作成",
  overwritten: "更新",
  kept: "維持（既存を保持）",
  skipped: "スキップ（既存を保持）",
};

async function runInit(args: string[]): Promise<void> {
  const flags = parseInitFlags(args);
  const cwd = process.cwd();
  const projectName = deriveProjectName(cwd, flags.name);

  console.log("");
  console.log(`  stdd v${VERSION}  現在のディレクトリに STDD を導入します`);
  console.log(`  対象: ${cwd}`);
  console.log("");

  // 既存の .claude/ がある場合の上書き可否を決める
  let overwriteClaude = flags.force;
  const claudeExists = fs.existsSync(path.join(cwd, ".claude"));
  if (claudeExists && !flags.force) {
    if (flags.yes || !process.stdout.isTTY) {
      // 非対話時は安全側（既存を保持）に倒す
      overwriteClaude = false;
      console.log("  既存の .claude/ を検出しました → 保持します（上書きするには --force）");
    } else {
      const res = await prompts({
        type: "confirm",
        name: "overwrite",
        message: "既存の .claude/ を最新の STDD スキル一式で上書きしますか？",
        initial: true,
      });
      overwriteClaude = res.overwrite === true;
    }
  }

  let result;
  try {
    result = await install({ targetDir: cwd, assetsRoot, projectName, overwriteClaude });
  } catch (err) {
    if (err instanceof InstallError) {
      console.error(`\n  エラー: ${err.message}\n`);
      process.exit(1);
    }
    throw err;
  }

  console.log("");
  console.log("  ✔ STDD を導入しました");
  console.log(`    .claude/           : ${ACTION_LABEL[result.claude]}`);
  console.log(`    .stdd.config.yml   : ${ACTION_LABEL[result.config]}`);
  console.log(`    .mcp.json          : ${ACTION_LABEL[result.mcp]}  # Playwright MCP（ブラウザ動作確認）`);
  console.log(`    docs/              : ${ACTION_LABEL[result.docs]}`);
  console.log("");
  console.log("  次の手順:");
  const steps: string[] = [];
  if (result.config === "created") {
    steps.push(".stdd.config.yml の apps[].path / commands.* を実環境に合わせて調整");
  }
  steps.push("claude を起動");
  steps.push("「STDD を導入して」と伝える  # 新規/既存を自動判定して進めます");
  steps.forEach((s, i) => console.log(`    ${i + 1}. ${s}`));
  console.log("");
  console.log("  ドキュメント: https://github.com/careerchain-ys/stdd");
  console.log("");
}

async function main(): Promise<void> {
  const argv = process.argv.slice(2);
  const [command, ...rest] = argv;

  if (command === "--version" || command === "-v") {
    console.log(VERSION);
    return;
  }
  if (command === undefined || command === "--help" || command === "-h" || command === "help") {
    printHelp();
    return;
  }
  if (command === "init") {
    await runInit(rest);
    return;
  }

  console.error(`  エラー: 不明なコマンド "${command}"`);
  printHelp();
  process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
