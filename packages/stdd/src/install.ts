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

/** 除外を記録できる配布物の種別。 */
export type ExclusionKind = "skill" | "agent" | "hook";

/** 除外の記録（`.stdd/exclusions.json`）。名前の配列を種別ごとに持つ。 */
export interface Exclusions {
  skills: string[];
  agents: string[];
  hooks: string[];
}

/** 除外の記録の処理結果。 */
export interface ExclusionReport {
  /** 処理後の記録（`kind:name` の配列）。 */
  recorded: string[];
  /** 今回、利用者による削除を検出して記録に足したもの（`kind:name`）。 */
  detected: string[];
  /** 記録ファイルの相対パス。 */
  file: string;
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
  /** 導入するエージェントビュー（省略時は ["claude"]）。 */
  agents?: AgentTarget[];
  /** 除外の記録に足すもの（`skill:<name>` / `agent:<name>` / `hook:<name>`）。 */
  exclude?: string[];
  /** 除外の記録から外して導入し直すもの（書式は exclude と同じ）。 */
  include?: string[];
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
  /** 除外の記録。 */
  exclusions: ExclusionReport;
  /** `.stdd.config.yml` の `models.agents` の反映結果（Claude のみ。設定が無ければ省略）。 */
  models?: ModelOverrideReport;
}

/** agent のモデルの上書きの反映結果。 */
export interface ModelOverrideReport {
  /** 上書きを書いた agent（`<name>: <alias>`）。 */
  applied: string[];
  /** 配布物に無い agent の名前（設定の誤りの疑い）。 */
  unknown: string[];
}

const CLAUDE_DIR = ".claude";
const AGENTS_DIR = ".agents";
const CODEX_DIR = ".codex";
const SETTINGS_FILE = "settings.json";
const CLAUDE_MANIFEST_REL = path.join(".claude", ".stdd", "manifest.json");
const CODEX_MANIFEST_REL = path.join(".stdd", "codex-manifest.json");
const EXCLUSIONS_REL = path.join(".stdd", "exclusions.json");
const EXCLUSION_KINDS: ExclusionKind[] = ["skill", "agent", "hook"];
const EXCLUSION_NAME = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
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
/** agent の model に書けるモデルの別名（packages/core/docs/model-selection.md）。モデルの ID は許さない。 */
export const MODEL_ALIASES = ["inherit", "opus", "sonnet", "haiku", "fable"] as const;

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
  /** settings.json に STDD が登録したフックの名前（Claude のみ）。外された登録の検出に使う。 */
  settingsHooks?: string[];
}

/** 1 ファイル分のマージ指示。rel は manifest に記録する相対パス。 */
interface FileSpec {
  rel: string;
  srcAbs: string;
  dstAbs: string;
  /** 書き込む前に内容を変換する（除外したフックの登録を外すなど）。 */
  transform?: (content: Buffer) => Buffer;
}

/** 除外の判定に使う、作業中の記録。キーは `kind:name`。 */
interface ExclusionState {
  set: Set<string>;
  /** 今回 include したもの。削除の検出の対象から外す。 */
  pinned: Set<string>;
  detected: string[];
}

/** manifest の相対パスから、それが属する skill / agent を返す（`kind:name`）。 */
type ComponentOf = (rel: string) => string | undefined;

const claudeComponentOf: ComponentOf = (rel) => {
  const skill = /^skills\/([^/]+)\//.exec(rel);
  if (skill) return `skill:${skill[1]}`;
  const agent = /^agents\/([^/]+)\.md$/.exec(rel);
  if (agent) return `agent:${agent[1]}`;
  return undefined;
};

const codexComponentOf: ComponentOf = (rel) => {
  const skill = /^\.agents\/skills\/([^/]+)\//.exec(rel);
  if (skill) return `skill:${skill[1]}`;
  const agent = /^\.codex\/agents\/([^/]+)\.toml$/.exec(rel);
  if (agent) return `agent:${agent[1]}`;
  return undefined;
};

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
    exclude = [],
    include = [],
  } = opts;

  const toExclude = exclude.map(parseExclusionKey);
  const toInclude = include.map(parseExclusionKey);
  await assertAssets(assetsRoot, agents);
  await fs.mkdir(targetDir, { recursive: true });

  const exclusionsAbs = path.join(targetDir, EXCLUSIONS_REL);
  const recorded = await readExclusions(exclusionsAbs);
  const state: ExclusionState = {
    set: new Set(exclusionsToKeys(recorded)),
    pinned: new Set(toInclude),
    detected: [],
  };
  for (const key of toInclude) state.set.delete(key);
  for (const key of toExclude) state.set.add(key);

  // 削除の検出は、どのビューも書き換える前に済ませる（記録は両ビューに効くため）。
  const claudeDst = path.join(targetDir, CLAUDE_DIR);
  if (agents.includes("claude")) {
    await detectDeletedComponents(
      path.join(targetDir, CLAUDE_MANIFEST_REL),
      (rel) => path.join(claudeDst, toNative(rel)),
      claudeComponentOf,
      state,
    );
  }
  if (agents.includes("codex")) {
    await detectDeletedComponents(
      path.join(targetDir, CODEX_MANIFEST_REL),
      (rel) => path.join(targetDir, toNative(rel)),
      codexComponentOf,
      state,
    );
  }

  const result: InstallResult = {
    config: "skipped",
    docs: "skipped",
    exclusions: { recorded: [], detected: [], file: toPosix(EXCLUSIONS_REL) },
  };

  const modelOverrides = agents.includes("claude") ? await readModelOverrides(targetDir) : {};

  if (agents.includes("claude")) {
    const merged = await mergeClaude(assetsRoot, targetDir, overwriteClaude, version, state, modelOverrides);
    result.settings = await mergeSettingsFile(assetsRoot, targetDir, state, merged.manifest);
    await writeManifest(merged.manifestAbs, merged.manifest.files, version, merged.manifest.settingsHooks);
    result.claude = merged.summary;
    result.mcp = await installMcp(assetsRoot, targetDir);
    if (Object.keys(modelOverrides).length > 0) result.models = merged.models;
  }

  if (agents.includes("codex")) {
    const merged = await mergeCodex(assetsRoot, targetDir, overwriteClaude, version, state);
    await writeManifest(merged.manifestAbs, merged.manifest.files, version);
    result.codex = merged.summary;
    result.agentsMd = await injectAgentsMd(assetsRoot, targetDir);
    result.codexConfig = await installCodexConfig(assetsRoot, targetDir);
  }

  result.config = await installConfig(assetsRoot, targetDir, projectName);
  result.docs = await ensureDocs(targetDir);

  const next = keysToExclusions(state.set);
  if (exclusionsToKeys(next).length > 0 || (await pathExists(exclusionsAbs))) {
    await writeExclusions(exclusionsAbs, next);
  }
  result.exclusions = {
    recorded: exclusionsToKeys(next),
    detected: [...state.detected].sort(),
    file: toPosix(EXCLUSIONS_REL),
  };

  return result;
}

// ---- 除外の記録 -------------------------------------------------------------

/** `kind:name` を検証して正規化する。書式が誤っていれば InstallError。 */
export function parseExclusionKey(raw: string): string {
  const value = raw.trim();
  const sep = value.indexOf(":");
  const kind = value.slice(0, sep) as ExclusionKind;
  const name = value.slice(sep + 1);
  if (sep <= 0 || !EXCLUSION_KINDS.includes(kind) || !EXCLUSION_NAME.test(name)) {
    throw new InstallError(
      `除外の指定は skill:<名前> / agent:<名前> / hook:<名前> の形で書いてください: "${raw}"`,
    );
  }
  return `${kind}:${name}`;
}

function exclusionsToKeys(ex: Exclusions): string[] {
  return [
    ...ex.skills.map((n) => `skill:${n}`),
    ...ex.agents.map((n) => `agent:${n}`),
    ...ex.hooks.map((n) => `hook:${n}`),
  ].sort();
}

function keysToExclusions(keys: Iterable<string>): Exclusions {
  const out: Exclusions = { skills: [], agents: [], hooks: [] };
  for (const key of keys) {
    const [kind, name] = key.split(":");
    if (kind === "skill") out.skills.push(name);
    else if (kind === "agent") out.agents.push(name);
    else if (kind === "hook") out.hooks.push(name);
  }
  out.skills.sort();
  out.agents.sort();
  out.hooks.sort();
  return out;
}

async function readExclusions(abs: string): Promise<Exclusions> {
  let raw: string;
  try {
    raw = await fs.readFile(abs, "utf8");
  } catch (err) {
    if (isErrnoCode(err, "ENOENT")) return { skills: [], agents: [], hooks: [] };
    throw err;
  }
  let parsed: Partial<Record<keyof Exclusions, unknown>>;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new InstallError(`除外の記録を JSON として読めません: ${abs}`);
  }
  const pick = (key: keyof Exclusions, kind: ExclusionKind): string[] => {
    const v = parsed[key];
    if (v === undefined) return [];
    if (!Array.isArray(v)) throw new InstallError(`除外の記録の "${key}" は名前の配列にしてください: ${abs}`);
    return v.map((name) => parseExclusionKey(`${kind}:${String(name)}`).slice(kind.length + 1));
  };
  return { skills: pick("skills", "skill"), agents: pick("agents", "agent"), hooks: pick("hooks", "hook") };
}

async function writeExclusions(abs: string, ex: Exclusions): Promise<void> {
  const body = {
    _note:
      "stdd init が復活させない skill / agent / フックの記録。削除を検出すると自動で追記される。戻すときは stdd init --include <kind>:<name>",
    ...ex,
  };
  await writeFileEnsured(abs, Buffer.from(`${JSON.stringify(body, null, 2)}\n`));
}

/**
 * manifest に記録のある skill / agent のうち、記録したファイルがすべて消えているものを
 * 利用者による削除とみなし、除外の記録に足す。
 * 記録したものが 1 つも残っていない（ビューごと消えた）ときは、導入し直しとみなして何もしない。
 */
async function detectDeletedComponents(
  manifestAbs: string,
  relToAbs: (rel: string) => string,
  componentOf: ComponentOf,
  state: ExclusionState,
): Promise<void> {
  const prev = await readManifest(manifestAbs);
  const byComponent = new Map<string, string[]>();
  for (const f of prev.files) {
    const c = componentOf(f.path);
    if (!c) continue;
    byComponent.set(c, [...(byComponent.get(c) ?? []), f.path]);
  }
  if (byComponent.size === 0) return;

  const missing: string[] = [];
  for (const [component, rels] of byComponent) {
    let anyPresent = false;
    for (const rel of rels) {
      if (await pathExists(relToAbs(rel))) {
        anyPresent = true;
        break;
      }
    }
    if (!anyPresent) missing.push(component);
  }
  if (missing.length === byComponent.size) return;

  for (const component of missing) {
    if (state.set.has(component) || state.pinned.has(component)) continue;
    state.set.add(component);
    state.detected.push(component);
  }
}

/** フックの登録 1 件（コマンド）から、STDD のフックの名前（`hooks/<name>.sh`）を取り出す。 */
function hookNameOf(command: unknown): string | undefined {
  if (typeof command !== "string") return undefined;
  const m = /hooks\/([A-Za-z0-9._-]+)\.sh\b/.exec(command);
  return m ? m[1] : undefined;
}

type HookGroup = { hooks?: Array<{ command?: unknown }> } & Record<string, unknown>;
type HooksByEvent = Record<string, HookGroup[]>;

function groupHookNames(group: HookGroup): string[] {
  const names: string[] = [];
  for (const h of Array.isArray(group.hooks) ? group.hooks : []) {
    const n = hookNameOf(h?.command);
    if (n) names.push(n);
  }
  return names;
}

/** 名前が drop に当たる登録を外す。中身が空になったグループは消す。 */
function withoutHooks(byEvent: HooksByEvent, drop: (name: string) => boolean): HooksByEvent {
  const out: HooksByEvent = {};
  for (const [event, groups] of Object.entries(byEvent)) {
    if (!Array.isArray(groups)) {
      out[event] = groups;
      continue;
    }
    const kept: HookGroup[] = [];
    for (const group of groups) {
      if (!isPlainObject(group) || !Array.isArray(group.hooks)) {
        kept.push(group);
        continue;
      }
      const inner = group.hooks.filter((h) => {
        const n = hookNameOf(h?.command);
        return n === undefined || !drop(n);
      });
      if (inner.length === 0) continue;
      kept.push(inner.length === group.hooks.length ? group : { ...group, hooks: inner });
    }
    if (kept.length > 0) out[event] = kept;
  }
  return out;
}

/** Codex の hooks.json から、除外したフックの登録を外す。 */
function codexHooksTransform(state: ExclusionState): (content: Buffer) => Buffer {
  return (content) => {
    let parsed: { hooks?: HooksByEvent } & Record<string, unknown>;
    try {
      parsed = JSON.parse(content.toString("utf8"));
    } catch {
      return content;
    }
    if (!isPlainObject(parsed.hooks)) return content;
    const filtered = withoutHooks(parsed.hooks, (n) => state.set.has(`hook:${n}`));
    if (JSON.stringify(filtered) === JSON.stringify(parsed.hooks)) return content;
    return Buffer.from(`${JSON.stringify({ ...parsed, hooks: filtered }, null, 2)}\n`);
  };
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
  state: ExclusionState,
  modelOverrides: Record<string, string> = {},
): Promise<TreeMergeResult & { models: ModelOverrideReport }> {
  const src = path.join(assetsRoot, CLAUDE_DIR);
  const dst = path.join(targetDir, CLAUDE_DIR);
  const shipped = (await listFilesRel(src)).filter((rel) => rel !== SETTINGS_FILE);
  const models: ModelOverrideReport = { applied: [], unknown: [] };
  const shippedAgents = new Set<string>();
  const specs: FileSpec[] = shipped.map((rel) => {
    const agent = /^agents\/([^/]+)\.md$/.exec(rel)?.[1];
    if (agent) shippedAgents.add(agent);
    const model = agent ? modelOverrides[agent] : undefined;
    if (agent && model) models.applied.push(`${agent}: ${model}`);
    return {
      rel,
      srcAbs: path.join(src, toNative(rel)),
      dstAbs: path.join(dst, toNative(rel)),
      // モデルの上書きは Claude の agent の定義だけに書く（Codex の生成物にはモデルを出さない）。
      transform: model ? (content: Buffer) => Buffer.from(setAgentModel(content.toString("utf8"), model)) : undefined,
    };
  });
  models.unknown = Object.keys(modelOverrides).filter((n) => !shippedAgents.has(n)).sort();
  models.applied.sort();
  const manifestAbs = path.join(targetDir, CLAUDE_MANIFEST_REL);
  const merged = await mergeManagedTree(
    specs,
    manifestAbs,
    (rel) => path.join(dst, toNative(rel)),
    dst,
    overwrite,
    claudeComponentOf,
    state,
  );
  return { ...merged, models };
}

// ---- モデルの上書き（Claude のみ） -------------------------------------------

/** 導入先の `.stdd.config.yml` から `models.agents` を読む。ファイルが無ければ空。 */
async function readModelOverrides(targetDir: string): Promise<Record<string, string>> {
  let text: string;
  try {
    text = await fs.readFile(path.join(targetDir, CONFIG_FILE), "utf8");
  } catch (err) {
    if (isErrnoCode(err, "ENOENT")) return {};
    throw err;
  }
  return parseAgentModelOverrides(text);
}

/**
 * `.stdd.config.yml` の本文から `models.agents` の対応（agent の名前 → モデルの別名）を取り出す。
 * 依存を持たないため、この形（ブロック記法の 2 段の対応）だけを読む軽量の読み取りにとどめる。
 * 値が別名でなければ InstallError（モデルの ID を書いた誤りを導入時に止める）。
 */
export function parseAgentModelOverrides(yaml: string): Record<string, string> {
  const out: Record<string, string> = {};
  const lines = yaml.split(/\r?\n/);
  const indentOf = (line: string) => line.length - line.trimStart().length;
  const strip = (v: string) => v.replace(/\s+#.*$/, "").trim().replace(/^(["'])(.*)\1$/, "$2");
  const isBlank = (line: string) => line.trim() === "" || line.trimStart().startsWith("#");

  let i = lines.findIndex((l) => /^models:\s*(#.*)?$/.test(l));
  if (i === -1) return out;
  let agentsIndent = -1;
  for (i += 1; i < lines.length; i++) {
    const line = lines[i];
    if (isBlank(line)) continue;
    const indent = indentOf(line);
    if (indent === 0) break; // models の外に出た
    if (agentsIndent === -1) {
      if (/^\s*agents:\s*(#.*)?$/.test(line)) agentsIndent = indent;
      continue;
    }
    if (indent <= agentsIndent) {
      agentsIndent = -1;
      if (/^\s*agents:\s*(#.*)?$/.test(line)) agentsIndent = indent;
      continue;
    }
    const m = /^\s*([^:#\s][^:]*):\s*(.*)$/.exec(line);
    if (!m) continue;
    const name = strip(m[1]);
    const value = strip(m[2]);
    if (!EXCLUSION_NAME.test(name)) {
      throw new InstallError(`${CONFIG_FILE} の models.agents の名前が不正です: ${name}`);
    }
    if (!(MODEL_ALIASES as readonly string[]).includes(value)) {
      throw new InstallError(
        `${CONFIG_FILE} の models.agents.${name} はモデルの別名（${MODEL_ALIASES.join(" / ")}）で書いてください: ${value}`,
      );
    }
    out[name] = value;
  }
  return out;
}

/** agent の定義（frontmatter + 本文）の `model` の行を書き換える。行が無ければ frontmatter の末尾に足す。 */
export function setAgentModel(md: string, model: string): string {
  const m = /^---\r?\n([\s\S]*?)\r?\n---/.exec(md);
  if (!m) return md;
  const block = m[1];
  const next = /^model:.*$/m.test(block) ? block.replace(/^model:.*$/m, `model: ${model}`) : `${block}\nmodel: ${model}`;
  return md.slice(0, m.index) + m[0].replace(block, () => next) + md.slice(m.index + m[0].length);
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
  state: ExclusionState,
): Promise<TreeMergeResult> {
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
      transform: rel === "hooks.json" ? codexHooksTransform(state) : undefined,
    });
  }

  const manifestAbs = path.join(targetDir, CODEX_MANIFEST_REL);
  return mergeManagedTree(
    specs,
    manifestAbs,
    (rel) => path.join(targetDir, toNative(rel)),
    targetDir,
    overwrite,
    codexComponentOf,
    state,
  );
}

interface TreeMergeResult {
  summary: MergeSummary;
  /** 書き出す前の manifest（settings.json の処理で settingsHooks を足してから書く）。 */
  manifest: Manifest;
  manifestAbs: string;
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
  componentOf: ComponentOf,
  state: ExclusionState,
): Promise<TreeMergeResult> {
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

  for (const { rel, srcAbs, dstAbs, transform } of specs) {
    const raw = await fs.readFile(srcAbs);
    const content = transform ? transform(raw) : raw;
    const newHash = sha256(content);
    const recorded = prevByPath.get(rel);

    const component = componentOf(rel);
    if (component && state.set.has(component)) {
      // 除外した skill / agent: 作らない。未編集の実体は消し、編集済みは残して報告する。
      if (!(await pathExists(dstAbs))) continue;
      if (!recorded) continue; // 利用者のファイル（記録なし）には触らない
      const currentHash = sha256(await fs.readFile(dstAbs));
      if (currentHash === recorded.sha256 || currentHash === newHash) {
        await fs.rm(dstAbs, { force: true });
        await pruneEmptyDirs(path.dirname(dstAbs), pruneRoot);
        summary.removed.push(rel);
      } else {
        summary.skippedModified.push(rel);
        nextFiles.push(recorded);
      }
      continue;
    }

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

  return {
    summary,
    manifest: { ...prev, files: nextFiles },
    manifestAbs,
  };
}

/**
 * settings.json を deep-merge して書き出す。
 * 既存が無ければ STDD 版をそのまま作成、あればマージして更新。
 */
async function mergeSettingsFile(
  assetsRoot: string,
  targetDir: string,
  state: ExclusionState,
  manifest: Manifest,
): Promise<FileAction> {
  const srcAbs = path.join(assetsRoot, CLAUDE_DIR, SETTINGS_FILE);
  if (!(await isFile(srcAbs))) return "skipped";
  const { hooks: rawIncomingHooks, ...incoming } = JSON.parse(
    await fs.readFile(srcAbs, "utf8"),
  ) as Record<string, unknown>;
  const incomingHooks: HooksByEvent = isPlainObject(rawIncomingHooks)
    ? (rawIncomingHooks as HooksByEvent)
    : {};

  const dstAbs = path.join(targetDir, CLAUDE_DIR, SETTINGS_FILE);
  if (!(await pathExists(dstAbs))) {
    const hooks = withoutHooks(incomingHooks, (n) => state.set.has(`hook:${n}`));
    manifest.settingsHooks = registeredHookNames(hooks);
    const out = Object.keys(hooks).length > 0 ? { ...incoming, hooks } : incoming;
    await writeFileEnsured(dstAbs, Buffer.from(`${JSON.stringify(out, null, 2)}\n`));
    return "created";
  }

  const existing = JSON.parse(await fs.readFile(dstAbs, "utf8")) as Record<string, unknown>;
  const { hooks: rawExistingHooks, ...existingRest } = existing;
  const merged = mergeSettings(existingRest, incoming);
  const existingHooks: HooksByEvent = isPlainObject(rawExistingHooks)
    ? (rawExistingHooks as HooksByEvent)
    : {};
  const { hooks, registered } = mergeHooks(existingHooks, incomingHooks, manifest.settingsHooks, state);
  manifest.settingsHooks = registered;
  const out =
    Object.keys(hooks).length > 0 || rawExistingHooks !== undefined ? { ...merged, hooks } : merged;
  await fs.writeFile(dstAbs, `${JSON.stringify(out, null, 2)}\n`);
  return "merged";
}

function registeredHookNames(byEvent: HooksByEvent): string[] {
  const names = new Set<string>();
  for (const groups of Object.values(byEvent)) {
    if (!Array.isArray(groups)) continue;
    for (const g of groups) if (isPlainObject(g)) groupHookNames(g).forEach((n) => names.add(n));
  }
  return [...names].sort();
}

/**
 * settings.json のフックの登録を、名前（`hooks/<name>.sh`）単位で合わせる。
 * - 除外したフック: 登録を外す
 * - 前回 STDD が登録し、今は登録が無いフック: 利用者が外したとみなして除外の記録に足す（戻さない）
 * - 利用者が登録を書き換えたフック（同じイベントに同じ名前の登録がある）: 利用者の登録を残し、足さない
 * - 配布から外れたフック（前回登録し、今回は配らない）: 登録を外す
 */
function mergeHooks(
  existing: HooksByEvent,
  incoming: HooksByEvent,
  prevRegistered: string[] | undefined,
  state: ExclusionState,
): { hooks: HooksByEvent; registered: string[] } {
  const prev = new Set(prevRegistered ?? []);
  const present = new Set(registeredHookNames(existing));
  const shipped = new Set(registeredHookNames(incoming));

  for (const name of prev) {
    const key = `hook:${name}`;
    if (shipped.has(name) && !present.has(name) && !state.set.has(key) && !state.pinned.has(key)) {
      state.set.add(key);
      state.detected.push(key);
    }
  }
  const excluded = (n: string) => state.set.has(`hook:${n}`);
  const retired = (n: string) => prev.has(n) && !shipped.has(n);
  const out = withoutHooks(existing, (n) => excluded(n) || retired(n));

  for (const [event, groups] of Object.entries(incoming)) {
    if (!Array.isArray(groups)) continue;
    for (const group of groups) {
      if (!isPlainObject(group)) continue;
      const names = groupHookNames(group);
      if (names.some(excluded)) continue;
      const current = Array.isArray(out[event]) ? out[event] : [];
      const sameName = current.some((g) => isPlainObject(g) && groupHookNames(g).some((n) => names.includes(n)));
      const sameGroup = current.some((g) => stableKey(g) === stableKey(group));
      if (sameName || sameGroup) continue;
      out[event] = [...current, group];
    }
  }

  const registered = [...shipped].filter((n) => !excluded(n) && registeredHookNames(out).includes(n));
  return { hooks: out, registered: registered.sort() };
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
    `<!-- このブロックは STDD が管理します。手動編集は次回 stdd init で上書きされます。 -->\n\n` +
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
      settingsHooks: Array.isArray(parsed.settingsHooks) ? parsed.settingsHooks : undefined,
    };
  } catch {
    return { version: "0.0.0", installedAt: "", files: [] };
  }
}

async function writeManifest(
  manifestAbs: string,
  files: ManifestEntry[],
  version: string,
  settingsHooks?: string[],
): Promise<void> {
  const sorted = dedupeByPath([...files].sort((a, b) => a.path.localeCompare(b.path)));
  const manifest: Manifest = {
    version,
    installedAt: new Date().toISOString(),
    files: sorted,
    ...(settingsHooks ? { settingsHooks } : {}),
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
