// STDD adapters generator.
// SSoT は packages/core/{skills,agents,hooks,rules}（エージェント非依存の中立コンテンツ）。
// 本スクリプトは core を各エージェントのネイティブ配置へ「投影（生成）」する。
// 生成物はコミットする（案 X）。編集は core 側で行い、生成物を直接編集しない。
//
// 生成するビュー:
//   Claude: repo-root .claude/{skills,agents,hooks,rules}（.claude/settings.json は authored 据え置き）
//   Codex : repo-root .agents/skills（同一 SKILL.md 標準）, .codex/agents/*.toml（MD→TOML 変換）
//           ※ .codex/hooks.json / config.toml(MCP) / AGENTS.md 注入は後続増分（2c/2d）で追加
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

// ---- ビュー定義 ------------------------------------------------------------
// outputs: 生成物 1 ファイル分 { abs, content(Buffer), mode }
// managedDirs: 生成物が占有するディレクトリ（orphan 掃除の対象）

async function planClaudeView() {
  const outputs = [];
  const managedDirs = [];
  for (const d of ["skills", "agents", "hooks", "rules"]) {
    const src = path.join(coreRoot, d);
    const dst = path.join(repoRoot, ".claude", d);
    managedDirs.push(dst);
    for (const rel of await listFilesRel(src)) {
      const s = path.join(src, rel);
      outputs.push({ abs: path.join(dst, rel), content: await fs.readFile(s), mode: await modeOf(s) });
    }
  }
  return { outputs, managedDirs };
}

async function planCodexView() {
  const outputs = [];
  const managedDirs = [];

  // 2a: skills は同一 SKILL.md 標準 → .agents/skills へそのままコピー
  const skillsSrc = path.join(coreRoot, "skills");
  const skillsDst = path.join(repoRoot, ".agents", "skills");
  managedDirs.push(skillsDst);
  for (const rel of await listFilesRel(skillsSrc)) {
    const s = path.join(skillsSrc, rel);
    outputs.push({ abs: path.join(skillsDst, rel), content: await fs.readFile(s), mode: await modeOf(s) });
  }

  // 2b: agents は MD(frontmatter+body) → Codex subagent TOML へ変換
  const agentsSrc = path.join(coreRoot, "agents");
  const agentsDst = path.join(repoRoot, ".codex", "agents");
  managedDirs.push(agentsDst);
  for (const rel of await listFilesRel(agentsSrc)) {
    if (!rel.endsWith(".md")) continue;
    const md = await fs.readFile(path.join(agentsSrc, rel), "utf8");
    const toml = agentMdToToml(md, rel);
    outputs.push({ abs: path.join(agentsDst, rel.replace(/\.md$/, ".toml")), content: Buffer.from(toml), mode: 0o644 });
  }

  // 2d: MCP → .codex/config.toml [mcp_servers.*]（Claude の .mcp.json と同一定義から）
  const mcpJson = JSON.parse(await fs.readFile(path.join(repoRoot, "templates", "minimal", ".mcp.json"), "utf8"));
  outputs.push({
    abs: path.join(repoRoot, ".codex", "config.toml"),
    content: Buffer.from(mcpJsonToCodexToml(mcpJson)),
    mode: 0o644,
  });

  return { outputs, managedDirs };
}

/** Claude の .mcp.json（{mcpServers:{name:{command,args,env,url}}}）を Codex config.toml の [mcp_servers.*] へ。 */
function mcpJsonToCodexToml(mcpJson) {
  const lines = ["# 生成物: templates/minimal/.mcp.json から build-adapters が生成。直接編集しない（編集は元定義へ）。", ""];
  for (const [name, cfg] of Object.entries(mcpJson.mcpServers ?? {})) {
    lines.push(`[mcp_servers.${name}]`);
    if (cfg.command) lines.push(`command = "${escapeTomlBasic(cfg.command)}"`);
    if (Array.isArray(cfg.args)) lines.push(`args = [${cfg.args.map((a) => `"${escapeTomlBasic(a)}"`).join(", ")}]`);
    if (cfg.url) lines.push(`url = "${escapeTomlBasic(cfg.url)}"`);
    if (cfg.env && typeof cfg.env === "object") {
      lines.push(`[mcp_servers.${name}.env]`);
      for (const [k, v] of Object.entries(cfg.env)) lines.push(`${k} = "${escapeTomlBasic(String(v))}"`);
    }
    lines.push("");
  }
  return lines.join("\n");
}

// ---- MD → Codex subagent TOML ----------------------------------------------

/** Claude の書込み系ツール。1 つでも含めば workspace-write、無ければ read-only。 */
const WRITE_TOOLS = new Set(["Edit", "Write", "MultiEdit", "NotebookEdit", "Bash"]);

function agentMdToToml(md, rel) {
  const { data, body } = parseFrontmatter(md);
  const name = data.name;
  if (!name) throw new Error(`agent frontmatter に name がありません: ${rel}`);
  const tools = (data.tools ?? "").split(",").map((t) => t.trim()).filter(Boolean);

  // tools → sandbox_mode（§2.1）。Claude の per-tool allowlist を OS 強制の sandbox に写す。
  const sandbox = tools.some((t) => WRITE_TOOLS.has(t)) ? "workspace-write" : "read-only";
  // mcp__<server>__* → mcp_servers
  const mcpServers = [...new Set(tools.map((t) => (t.match(/^mcp__([a-z0-9_-]+)/i) || [])[1]).filter(Boolean))];

  // developer_instructions は body（本文＝system prompt）。TOML リテラル複数行で無加工に埋める。
  const instr = body.replace(/^\n+/, "");
  if (instr.includes("'''")) throw new Error(`body に ''' を含むため TOML リテラル化できません: ${rel}`);

  const lines = [
    "# 生成物: packages/core/agents/" + rel + " から build-adapters が生成。直接編集しない（編集は core へ）。",
    `name = "${escapeTomlBasic(name)}"`,
    `description = "${escapeTomlBasic((data.description ?? "").trim())}"`,
    `sandbox_mode = "${sandbox}"`,
  ];
  if (mcpServers.length > 0) lines.push(`mcp_servers = [${mcpServers.map((s) => `"${s}"`).join(", ")}]`);
  // model は Claude 固有名（opus 等）で Codex のモデル ID ではないため意図的に出力しない（session 既定を継承）。
  lines.push("developer_instructions = '''", instr.replace(/\n$/, ""), "'''", "");
  return lines.join("\n");
}

function escapeTomlBasic(s) {
  return s.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

/** 先頭 frontmatter を { data, body } に分解。value は単一行前提の軽量パーサ。 */
function parseFrontmatter(md) {
  if (!md.startsWith("---\n")) return { data: {}, body: md };
  const end = md.indexOf("\n---", 3);
  if (end === -1) return { data: {}, body: md };
  const block = md.slice(4, end);
  const data = {};
  for (const line of block.split("\n")) {
    const m = line.match(/^([A-Za-z0-9_-]+):\s?(.*)$/);
    if (m) data[m[1]] = m[2];
  }
  return { data, body: md.slice(end + 4) };
}

// ---- 共通 fs ヘルパ --------------------------------------------------------

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
  return (await fs.stat(p)).mode & 0o777;
}

async function safeMode(p) {
  try {
    return await modeOf(p);
  } catch {
    return -1;
  }
}

// ---- 適用 / 検査 -----------------------------------------------------------

async function run() {
  const plans = [await planClaudeView(), await planCodexView()];
  const outputs = plans.flatMap((p) => p.outputs);
  const managedDirs = plans.flatMap((p) => p.managedDirs);
  const wanted = new Set(outputs.map((o) => o.abs));
  const drift = [];

  for (const o of outputs) {
    const cur = await readIfExists(o.abs);
    const same = cur !== null && cur.equals(o.content) && (await safeMode(o.abs)) === o.mode;
    if (!same) {
      drift.push(`${cur === null ? "create" : "update"} ${rel(o.abs)}`);
      if (!CHECK) {
        await fs.mkdir(path.dirname(o.abs), { recursive: true });
        await fs.writeFile(o.abs, o.content);
        await fs.chmod(o.abs, o.mode);
      }
    }
  }

  // orphan: 管理ディレクトリ配下で今回生成しないファイル
  for (const dir of managedDirs) {
    for (const f of await listFilesRel(dir)) {
      const abs = path.join(dir, f);
      if (wanted.has(abs)) continue;
      drift.push(`remove ${rel(abs)}`);
      if (!CHECK) await fs.rm(abs, { force: true });
    }
  }
  return drift;
}

function rel(abs) {
  return path.relative(repoRoot, abs).split(path.sep).join("/");
}

async function main() {
  const drift = await run();
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
      : `[build-adapters] 再生成しました（${drift.length} 件更新）。`,
  );
}

main().catch((err) => {
  console.error(`[build-adapters] 失敗: ${err.message}`);
  process.exit(1);
});
