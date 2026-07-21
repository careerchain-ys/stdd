# マルチエージェント対応（Claude / Codex）— 設計メモ

> 本メモは、Claude Code 専用だった stdd を Claude Code と OpenAI Codex CLI の両方で
> 使えるようにするための、あるべき姿（Core + Adapter）と到達ステップを定める設計 SSoT。
> 実装着手前に本メモを REQUIREMENTS / TECH_DESIGN へ昇格させる（§6 参照）。

## 1. 背景と目的

stdd は現状、配布物（skill / agent / hook / settings / mcp）が丸ごと Claude Code 前提で構成されている。
`npx @careerchain/stdd init` は `.claude/` 一式・`.stdd.config.yml`・`.mcp.json` を設置し、
skill 自動起動・subagent 編成・PreToolUse hook といった Claude Code 固有機構に依存する。

一方で stdd の価値本体（STDD 方法論・spec フォーマット・テンプレート・config 駆動オーサリング）は
エージェント非依存であり、Claude 依存は「デリバリの薄皮」に集中している。
本対応の目的は、この価値本体を単一 SSoT に保ちつつ、Claude / Codex 両方のネイティブ形式へ
投影できる構造へ移行することにある。

## 2. 互換性調査の結論

Codex CLI は 2026 年時点で大半のギャップを埋めており、特に stdd 中核の Skills は同一オープン標準
（`SKILL.md`）だった。stdd の依存物ごとの対応は次のとおり。

| stdd の依存物 | Codex の相当 | 対応度 | 移植コスト |
| --- | --- | --- | --- |
| skills 16 本（`SKILL.md`） | Skills（`.agents/skills/` 等・同一 `SKILL.md` 標準・progressive disclosure・自動起動） | ほぼ完全 | 極小 |
| `.stdd.config.yml`（実行時参照） | 変更不要（両者が読む共有 SSoT） | 完全 | ゼロ |
| hooks（`spec-first-check.sh` 等） | Hooks（`.codex/hooks.json` / `config.toml [hooks]`・`PreToolUse` あり） | 機構は完全 | 小 |
| rules（`.claude/rules/*` 自動読込） | AGENTS.md（repo root 既存・nested / override 対応） | 完全 | 小 |
| agents 9 体（`*.md` + `tools:` allowlist） | Subagents（`.codex/agents/*.toml`・`developer_instructions`） | 部分 | 中 |
| `.mcp.json`（JSON） | `[mcp_servers.*]`（`config.toml`・TOML） | 完全 | 小 |
| `settings.json`（`permissions.allow` 等） | `config.toml`（`approval_policy` + `sandbox_mode` + OS sandbox） | 部分 | 小 |
| plugin.json / `.claude/commands` | プラグインは skills 束として吸収 / commands は未使用 | — | ゼロ |

補足事項:

- skill の frontmatter で stdd 独自の `when_to_use` / `allowed-tools` は Codex 側で未知キーとして無害に無視される。
- Codex skills は `.agents/skills/`（cross-tool、`.codex/skills` ではない）から探索する。`agents/openai.yaml` で UI メタを任意付与可能。
- Codex hooks は `type: "command"` ハンドラのみ現状実行される（`prompt` / `agent` 型はパースのみ）。stdd の hook はシェルなので影響なし。
- Codex の project 版 `.codex/config.toml` は `approval_policy` / `sandbox_mode` 等の
  セキュリティ鍵を無視する（`~/.codex/config.toml` でのみ有効）。導入物側でこれらの既定を強制できない点に注意（§4.7）。
- Codex は `codex mcp-server` で自身を MCP サーバ化できる（調査時の不確定点を実測で解消。§7）。

### 2.1 唯一の実質ギャップと解消

Claude agent の `tools:` allowlist に相当する per-agent ツール制限は Codex に無い。
ただし Codex subagent は自身の TOML で `sandbox_mode` を絞れるため、次のように写せる
（OS レベル強制のため、むしろ封じ込めは強い）。

| Claude agent の `tools:` | Codex subagent | 意味 |
| --- | --- | --- |
| `Read, Grep, Glob`（reviewer 系 5 体） | `sandbox_mode = "read-only"` | 書込み不可を OS 強制 |
| `+ Edit, Write, Bash`（implementer 等） | `sandbox_mode = "workspace-write"` | 書込み可 |
| `mcp__playwright`（qa-engineer） | `mcp_servers = ["playwright"]` | MCP 限定 |

## 3. あるべき姿（Core + Adapter）

コンテンツを一度だけ著述し（Core = 単一 SSoT）、各エージェントのネイティブ形式へ投影する（Adapter）。
メンテナが既に想定していた「`packages/core/`（非依存）＋ アダプタ」構造を実体化するもの。

```
packages/core/            ← 単一 SSoT（エージェント非依存）
  docs/  schema/          ← 既存（方法論・config schema）
  skills/                 ← 16 SKILL.md を集約（両者が読む同一標準）
  agents/                 ← 9 ペルソナを中立正典（MD）で保持
  hooks/                  ← spec-first-check.sh 等（出力形状はターゲットで分岐）
  templates/              ← config / mcp / rule を中立記述

投影（stdd init が生成）:
  --agent claude → .claude/skills, .claude/agents/*.md, .claude/rules/*, settings.json, .mcp.json   （現状維持）
  --agent codex  → .agents/skills, .codex/agents/*.toml, .codex/hooks.json, AGENTS.md(追記), config.toml(mcp)
  --agent both / 自動判定 → 両方
```

共有で無変更となるもの: `.stdd.config.yml`、`docs/` 配下の spec 成果物、STDD 方法論そのもの。
価値本体は 100% 共通で、差分はデリバリの薄皮のみになる。

原則:

- Core は特定エージェントの語彙・機構名を持ち込まない。ツール名・ファイル名は中立記述にする（§4.1 の一般化ルール）。
- Adapter は「Core を各ネイティブ形式へ変換する純粋な投影」に徹する。ロジックや方法論を持たない。
- 既存の config 駆動オーサリング規約（`docs/config-driven-authoring.md`）は Core にそのまま継承する。

## 4. ターゲット別マッピング詳細

### 4.1 skills

- Core の `SKILL.md` をそのまま両ターゲットへコピー配置する。
- Claude → `.claude/skills/<name>/`、Codex → `.agents/skills/<name>/`。
- 本文中の Claude 固有語を一般化する: 「Claude Code」→「AI コーディングエージェント」、
  「`CLAUDE.md`」→「`AGENTS.md` / `CLAUDE.md`」、Agent / Task / Skill ツール名 →「専門エージェントへ委譲 / スキルを起動」等の中立表現。
- 両ディレクトリ必須（Phase 0 で確定・§7）: Claude は `.claude/skills` のみ、Codex は `.agents/skills` のみを discover。単一共有 dir は不可。symlink `.agents/skills → .claude/skills` は Codex がリンクを辿る場合のみ最適化として可（要検証）。

### 4.2 agents / subagents

- 正典は MD（人間可読・現状資産）。Codex 用に TOML を生成する。
- 変換: 本文 → `developer_instructions`、frontmatter `name` / `description` → 同名、
  `model` → `model`、`tools:` → `sandbox_mode`（§2.1 のマッピング）、`mcp__*` → `mcp_servers`。
- オーケストレーション（auto-implement 等 3 skill）の「Team Lead が専門エージェントへ委譲」という記述は
  自然言語ベースで両者に通じる。`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` は Claude 専用 env として Adapter に閉じる。

### 4.3 hooks

- シェル本体（`.stdd.config.yml` パース・パス分類ロジック）は Core で共有。
- 出力形状のみターゲットで分岐する:
  - Claude: `hookSpecificOutput.permissionDecision: "deny"` / `additionalContext`。
  - Codex: block 時 `{"continue": false, "systemMessage": ...}`（または exit 2）、warn 時 `systemMessage` 注入のみ。
- 配線: Claude = `settings.json hooks`、Codex = `.codex/hooks.json`（`matcher` に `Edit|Write` 等の正規表現）。

### 4.4 spec-first ルール

- Claude → `.claude/rules/stdd-spec-first.md`（自動読込）。
- Codex → プロジェクト `AGENTS.md` に stdd ブロックを非破壊マージ（settings 相当のマーカー方式で追記・冪等更新）。

### 4.5 MCP

- Core に中立記述（サーバ名・command・args）を持ち、Claude → `.mcp.json`（JSON）、Codex → `config.toml` の `[mcp_servers.playwright]`（TOML）へ投影。

### 4.6 config

- `.stdd.config.yml` は無変更で両者が実行時参照する共有 SSoT。ここは投影対象外。

### 4.7 permissions

- Codex には per-command allowlist が無い（`approval_policy` + `sandbox_mode` + OS sandbox）。
- 導入物では推奨承認モード（例: workspace-write + on-request）をドキュメントで案内するに留める。
  セキュリティ鍵は `.codex/config.toml` では効かないため、`~/.codex/config.toml` 側の設定を利用者に促す。

## 5. 到達ステップ

| Phase | 内容 | 目的 |
| --- | --- | --- |
| 0. 設計確定 + PoC（完了・§7） | ① Claude/Codex の skill discover 経路を実機確認（→ 両配置必須） ② Codex 実機で hooks / multi_agent / plugins が GA・有効と確認、`.agents/skills` と `AGENTS.md` の取り込みを実測 ③ 正典形式を確定（agents=MD 正 / TOML 生成、hook=出力分岐） | リスク潰し |
| 1. コア抽出（中立化） | skills / agents / hooks を `packages/core/` に SSoT 化。本文の Claude 固有語を一般化（§4.1）。`.claude/` はコアからの投影に切替え、既存挙動の回帰確認 | 単一 SSoT 化 |
| 2. Codex アダプタ | codex-view ジェネレータ実装: skills→`.agents/skills`、agents→TOML、hook→`.codex/hooks.json` + 出力アダプタ、mcp→`config.toml`、rule→AGENTS.md 非破壊マージ。ターゲット別 manifest | Codex 対応 |
| 3. CLI 拡張 | `stdd init --agent claude｜codex｜both` + 自動判定、冪等再 install、sync-assets を両ツリー生成へ | 導入 UX |
| 4. 検証・文書 | Codex E2E（skill / subagent / hook / mcp）、README・AGENTS.md・methodology を両対応記述、eval 両系統 | 品質保証 |

## 6. 未解決の設計判断

（`.agents/skills` の discover 可否は Phase 0 で解決 → 両配置必須。§7 参照）

1. subagent 編成の移植方式: Codex の `multi_agent` は GA・有効だが、format は TOML で per-agent tools allowlist が無い。
   auto-implement の 9 体を TOML 変換して移すのを基本とし、限定環境向けに「単一エージェントが各ペルソナの
   `developer_instructions` を順に adopt」する縮退モードを併設するか要判断。
2. skills 共有の最適化: 二重 install を基本としつつ、symlink `.agents/skills → .claude/skills` を
   Codex が辿れるか（辿れれば配布を一元化できる）を Phase 2 で検証する。
3. AGENTS.md のドリフト是正: 既存 `AGENTS.md` に未実現パス参照（`packages/claude-code/` 等）があり、Phase 1 で整える。
4. 本改修自体の spec 化: stdd 流に、Phase 1 の前段で `documenting-requirements` / `documenting-tech-specs` により
   REQUIREMENTS / TECH_DESIGN を作成してから着手する。

## 7. Phase 0 検証結果（2026-07-21・実機実測）

検証環境: OpenAI Codex CLI `0.144.0-alpha.4`（`/Applications/ChatGPT.app/Contents/Resources/codex`。ChatGPT Desktop 同梱・PATH 外）。
Claude Code 側は公式ドキュメント（code.claude.com）で確認。

### 7.1 skill / 指示ファイルの discover 経路

| 項目 | Claude Code | Codex CLI |
| --- | --- | --- |
| skills 探索元 | `.claude/skills/` のみ（+ nested / plugin / `--add-dir`） | `.agents/skills/`（project / repo / `$HOME`）ほか。`.claude/skills` は読まない |
| 相手ディレクトリ | `.agents/skills` は読まない | `.claude/skills` は読まない |
| プロジェクト指示 | `CLAUDE.md`（`@AGENTS.md` import 可・depth 4）／ `.claude/rules/*.md` 起動時自動ロード | `AGENTS.md`（root→cwd chain・override・32 KiB cap） |

結論: skills は `.claude/skills` と `.agents/skills` の両方へ配置が必須（単一共有 dir は不可）。
spec-first ルールは Claude=`.claude/rules/*`、Codex=`AGENTS.md` で届ける。

実測方法: scratch の git プロジェクトに `.agents/skills/*/SKILL.md`・`.claude/skills/*/SKILL.md`・`AGENTS.md`
を印付きで設置し `codex debug prompt-input`（モデル可視プロンプトを JSON 出力・エージェント非実行）を実行。
`.agents/skills` の skill と `AGENTS.md` の印は出力に現れ、`.claude/skills` の印は現れなかった。

### 7.2 機構の対応状況（Codex feature flags・実機）

| 機構 | flag | stage / state |
| --- | --- | --- |
| hooks | `hooks` | stable / 有効 |
| subagents | `multi_agent` | stable / 有効（`multi_agent_v2` は開発中） |
| plugins | `plugins` | stable / 有効 |
| skill の MCP 依存導入 | `skill_mcp_dependency_install` | stable / 有効 |

移植の難所だった 3 機構（skill 自動起動・subagent・hook）はいずれも GA・有効であることを実機で確認。

### 7.3 その他の確定事項

- Codex の SKILL.md frontmatter は `name` / `description` / 任意 `metadata`。stdd の `when_to_use` / `allowed-tools` は無害に無視される（実機の bundled skill で確認）。
- `codex exec` は `--sandbox read-only｜workspace-write｜danger-full-access` を持ち、§2.1 の agent sandbox マッピングに直結。
- `codex mcp-server` サブコマンドが存在（Codex を MCP サーバとして起動可能）。
- ライブのエージェント起動（skill 自動選択の実挙動観察）は未実施。クレジット消費・自律実行を伴うため、必要なら別途ユーザー承認のうえ `codex exec --sandbox read-only` で実施する。

## 8. 実装進捗（Phase 1–2）

作業ブランチ: `worktree-codex-support-phase1`（worktree）。

### 8.1 完了: 1a コンテンツ中立化（in place・回帰緑）

skill / agent 本文の Claude 固有語を、Claude 互換を保ったまま中立化した。install/hook 両テスト緑（9/9・15/15）。

- `CLAUDE.md` → `AGENTS.md / CLAUDE.md`（15 ファイル。プロジェクト規約ファイルの参照を両エージェント対応に）
- 裸 `Claude` → `エージェント`（`introducing-stdd` / `starting-new-with-stdd` / `tailoring-spec-format` / `documenting-plans` の駆動主体表現）
- `auto-implement`: subagent 有効化 env 注記を両対応化（Claude Code: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` / Codex: `multi_agent`）

### 8.2 Phase 2 へ意図的に繰延

- subagent 委譲イディオムの中立化（`auto-implement` / `review-pr-with-agents` の「1 メッセージ内に複数 Agent 呼び出し」等）: 委譲機構は subagent アダプタ設計と不可分のため Phase 2 で扱う。
- `.claude/docs/coding-conventions.md` 等の `.claude/` パス参照（約 10 ファイル）: 規約ドキュメントの Codex 側配置を決めてから一般化する（存在時のみ読む安全な参照・`.claude/` は許容例外）。

### 8.3 1b 構造抽出 — TECH_DESIGN（dogfooding 決定 = 案 X 採用）

方針: SSoT を `packages/core/` に置き、各エージェント向けディレクトリは core からの生成物としてコミットする（案 X）。既存の sync-assets / install / テスト / dogfooding を壊さないことを最優先とする。

目標構造:

```
packages/core/                 ← neutral SSoT（authored）
  skills/ agents/ hooks/ rules/   ← .claude から複製した中立コンテンツ
  templates/ docs/ schema/        ← 既存
packages/core/adapters/
  claude/  ← Claude 固有: settings.json 等（Phase 1 は現状の .claude/settings.json を据え置き）
  codex/   ← Codex 固有（Phase 2）: config.toml 断片 / hooks.json / agent TOML 変換設定
scripts/build-adapters.mjs     ← core(+adapter) → 各ビュー生成器
```

生成器 `scripts/build-adapters.mjs`:

- Claude ビュー: `packages/core/{skills,agents,hooks,rules}` → repo-root `.claude/{…}` をミラー（実行ビット保持・orphan 掃除）。`.claude/settings.json` は Phase 1 では触らない（authored 据え置き）。
- `--check` モード: 生成結果が現状の `.claude/` と一致しなければ非ゼロ終了（CI ドリフト検査用）。
- Codex ビュー生成は Phase 2 で追加（`.agents/skills` / `.codex/agents/*.toml` / `.codex/hooks.json` / `config.toml` / `AGENTS.md`）。

ビルド連鎖 / 消費:

- repo-root `.claude/` は core から生成してコミットする committed artifact。`.claude/skills` 等を直接編集しない（編集は core へ。CI の `--check` で強制）。
- `packages/stdd` の sync-assets は当面 repo-root `.claude/` を source にしたまま（`.claude/` が core 生成物なので不変で動く）。将来 core 直接投影へ寄せるのは follow-up。

Phase 1 の緑維持: core は `.claude/` の複製なので、生成器の出力は既存 `.claude/` とバイト一致 → install/hook テストは不変で緑。SSoT の実効化（以後の編集は core へ）と Codex ビューは後続で実現。

繰延（この 1b では対象外）: sync-assets の core 直接投影化 / `.claude/settings.json` の adapter 化 / symlink による重複排除（§6-2）。

### 8.4 完了: 1b 実装（回帰緑）

- `packages/core/{skills,agents,hooks,rules}` を SSoT として新設（.claude から複製・実行ビット保持・計 52 ファイル）。rules / hooks に Claude 固有の語句は無し（hook の出力形状は Phase 2 で両対応化）。
- `scripts/build-adapters.mjs` を追加（core → `.claude/` ミラー生成 + `--check` ドリフト検査 + orphan 掃除）。root `package.json` に `build:adapters` / `check:adapters` を配線し `build` の先頭へ組込み。
- 検証: `--check` OK（core == `.claude`）、意図的破壊で `--check` が exit 1 → 再生成で復元、install/hook テスト緑（9/9・15/15）。
- 以後の編集は `packages/core` へ。`.claude/` は生成物（案 X・committed）。CI で `check:adapters` を回しドリフトを防ぐ（CI 配線自体は follow-up）。

### 8.5 Phase 2 進捗: Codex ビュー生成

`build-adapters.mjs` を Claude/Codex 両ビュー生成へ再構成（outputs+managedDirs モデルで両ビューを一括 `--check`）。Claude ビューはバイト不変。

### 8.5.1 完了・実機検証済み

- 2a `.agents/skills/` ← core/skills をコピー（同一 `SKILL.md` 標準）。実機 Codex（`codex debug prompt-input`）が repo-root `.agents/skills` を discover することを確認（auto-implement / documenting-requirements 等がモデルプロンプトに出現）。
- 2b `.codex/agents/*.toml` ← core/agents/*.md を変換。frontmatter `name`/`description` → 同名、body → `developer_instructions`（TOML リテラル複数行）、`tools` → `sandbox_mode`（write 系含む=workspace-write / それ以外=read-only）、`mcp__<server>__*` → `mcp_servers`。生成 9 本すべて tomllib で妥当パース＋必須フィールド充足。分布: read-only 4（reviewer 系）/ workspace-write 5。
- 設計精緻化: `model: opus` は Codex のモデル ID ではないため TOML では出力しない（session 既定を継承。将来 `model_reasoning_effort` へのマッピングは検討事項）。

### 8.5.2 残: 2c / 2d

- 2c hooks: core の `spec-first-check.sh` に `STDD_HOOK_TARGET` 分岐を足し、Codex 形状（block=`{"continue":false,"systemMessage":…}` / warn=`systemMessage`）を出力。`.codex/hooks.json` を生成。※ Codex の hooks.json 正確なスキーマは実機/docs で確認してから配線する（未確定のまま生成しない）。
- 2d MCP: `.codex/config.toml` に `[mcp_servers.playwright]` を生成（templates の `.mcp.json` から）。
- 方針変更: rule → `AGENTS.md` 非破壊マージは、既存の project-authored ファイルへの差込みのため**インストーラ（Phase 3）側**へ再配置する（dogfooding 生成器は自リポの AGENTS.md を触らない）。

## 9. 改訂履歴

- 2026-07-21 初版（Claude / Codex 互換調査を踏まえた Core + Adapter 設計として作成）
- 2026-07-21 Phase 0 検証結果（§7）を追記。open question の #1（skills discover）を解決（両配置必須）
- 2026-07-21 Phase 1a（中立化）完了・回帰緑を §8 に記録。1b の dogfooding 決定を提示
- 2026-07-21 Phase 1b（core 抽出 + 生成器 build-adapters）完了・回帰緑。SSoT を packages/core へ（案 X）
- 2026-07-21 Phase 2a/2b（Codex ビュー: .agents/skills + .codex/agents TOML）完了・実機検証。build-adapters を両ビュー化
