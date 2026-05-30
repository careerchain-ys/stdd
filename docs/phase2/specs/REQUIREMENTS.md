# Phase 2-A: プラグイン分離・公開ドキュメント整備・固有名詞除去 仕様書

---

## 1. 概要

### 解決する問題

stdd リポジトリを OSS として公開できる状態にするためには、(a) core skill と技術スタック固有 skill の物理的分離、(b) GitHub 上で OSS プロジェクトとして体裁を整える公開ドキュメント、(c) 旧プロジェクト名を含む固有名詞の最終クリーンアップが必要である。Phase 2-A はこれら 3 領域の「ファイル移動 / ドキュメント執筆 / 固有名詞除去」までを担当する。CLI 実装・サンプルアプリ実装・タグ付け・公開化は Phase 2-B 以降に委ねる。

### 対象ユーザー

- stdd OSS のメンテナ（リポジトリ整備者）
- stdd を自プロジェクトに導入しようとする外部開発者（公開ドキュメントの読み手）
- プラグイン開発者（plugin ディレクトリ構造の利用者）

### ビジネス目標

- core skill 群（10 個）と技術スタック固有 skill 群（5 個）を**ディレクトリレベルで分離**し、プラグイン化の物理基盤を整える
- リポジトリトップに到達した外部開発者が **README.md → AGENTS.md → CONTRIBUTING.md** を読むだけで stdd の全体像と参加方法を理解できる状態にする
- 旧プロジェクト名（`CareerChain` / `careerchain` / `キャリアチェーン`）を、ライセンス表記・公開 URL を除き完全に除去し、リポジトリ全体を中立な OSS として再パッケージする
- `.stdd.config.yml` の `plugins:` フィールドが `docs/plugin-separation-policy.md` §6 で規定された 2 形式（文字列 / `{ id, options }`）を受け入れることを JSON Schema で保証する

---

## 2. ユーザージャーニー

各 Journey には Priority を付与する。

### プラグイン対象 skill を物理的に分離する

**Priority**: P0 (Critical Path)

#### 手順

1. メンテナが `plugins/nextjs-supabase/skills/` / `plugins/playwright/skills/` / `plugins/worktree/skills/` の 3 ディレクトリを作成する
2. メンテナが `.claude/skills/` 配下の 5 つの skill ディレクトリ（`implementing-ui`, `migrating-supabase`, `e2e-testing`, `run-e2e`, `remove-worktree`）を git 履歴を保持したまま対応するプラグインディレクトリに移動する
3. 各プラグインディレクトリに `plugin.json` を作成し、`id` / `name` / `version` / `skills` を宣言する
4. メンテナが `.claude/skills/` 配下に残った skill が core 10 skill のみであることを ls で確認する

#### 期待結果

- `.claude/skills/` 配下に core 10 skill のみが残る（`documenting-specifications`, `documenting-plans`, `auto-implement`, `verify-consistency`, `reverse-engineering-stdd`, `create-pr`, `review-pr-with-agents`, `kaizen`, `search-first`, `software-architecture`）
- `plugins/<plugin-id>/skills/<skill-id>/` の構造で 5 skill が再配置されている
- 各 skill の git log が `git log --follow` で連続して追える（移動前の履歴が失われない）
- 各プラグインディレクトリ直下に `plugin.json` が存在し、JSON 構文として valid である

---

### 公開リポジトリの入口ドキュメントを整備する

**Priority**: P0 (Critical Path)

#### 手順

1. メンテナがリポジトリルートに `README.md` を新規作成し、stdd の概要・Quick Start（CLI 未実装期のプレースホルダ）・対応 AI エージェント・ライセンス・関連ドキュメントへのリンクを記載する
2. メンテナが `AGENTS.md` を新規作成し、agents.md 標準準拠のエージェント設定情報を記載する
3. メンテナが `CONTRIBUTING.md` を新規作成し、コントリビューションフロー・DCO に関する記述を含める
4. メンテナが `CODE_OF_CONDUCT.md` を新規作成し、Contributor Covenant 2.1 の日本語版を採用する
5. メンテナが `.github/ISSUE_TEMPLATE/` 配下に 4 種類の issue テンプレート（skill-request, bug-report, plugin-proposal, agent-support-request）を配置する
6. メンテナが `.github/pull_request_template.md` を新規作成し、評価結果（eval-result）の添付欄を含める

#### 期待結果

- GitHub 上で新規 issue 作成時に 4 種類のテンプレートが選択肢に表示される
- 新規 PR 作成時に PR テンプレートが自動表示され、評価結果セクションが必須記入欄として認識できる
- 外部開発者が README.md から AGENTS.md / CONTRIBUTING.md / CODE_OF_CONDUCT.md / LICENSE の場所にたどり着ける
- AGENTS.md が agents.md 標準準拠の最低限のセクション（プロジェクト概要 / セットアップ手順 / ビルド・テスト・lint コマンド / コードスタイル / テスト方針 / セキュリティ留意事項 / PR ガイドライン）をすべて含む（詳細は TECH_DESIGN.md §3 を参照）
- すべての公開ドキュメントが日本語で記述されている

---

### 旧プロジェクト名を最終除去する

**Priority**: P0 (Critical Path)

#### 手順

1. メンテナが `SYNC_POLICY.md` を削除する（OSS 単体リポジトリとして独立するため、社内プロジェクトとの同期ポリシーは不要になる）
2. メンテナが `audit/PHASE0_AUDIT_REPORT.md` を削除し、`audit/` ディレクトリが空になればディレクトリごと削除する
3. メンテナが `.claude/agents/*.md` / `.claude/skills/**/*.md`（core 10 skill のみ）/ `.claude/docs/spec-driven-development-guide.md` / `docs/plugin-separation-policy.md` / `docs/phase1/plans/2026-05-17-core.md` の各ファイルに残存する `CareerChain（キャリアチェーン）プラットフォーム` 等の固有名詞を、汎用表現（「対象プロジェクト」または `{{project.name}}`）に置換する
4. メンテナが `careerchain-worktree-` で始まるパス文字列（主に `.claude/skills/auto-implement/SKILL.md`, `.claude/skills/run-e2e/SKILL.md`, `.claude/skills/remove-worktree/SKILL.md` に存在）を、汎用的な `worktree-` プレフィックスまたはプレースホルダ表現に置換する
5. メンテナがリポジトリ全体に対して `grep -rIn -E '(careerchain|CareerChain|キャリアチェーン)' .` を実行し、ヒットが LICENSE / NOTICE および公開 URL 文字列のみであることを確認する

#### 期待結果

- `SYNC_POLICY.md` および `audit/PHASE0_AUDIT_REPORT.md` がリポジトリから消えている
- 旧プロジェクト名が、リポジトリ全体で「ライセンス著作権表記」と「公開 GitHub URL 文字列」以外には残っていない
- skill / agent ドキュメント内のサンプルコマンド・パス例が、特定組織を連想させない一般的表現になっている

---

### プラグイン宣言形式の妥当性を JSON Schema で保証する

**Priority**: P0 (Critical Path)

#### 手順

1. メンテナが `.stdd.config.yml` の `plugins:` フィールドが受け入れるべき 2 形式を確認する
   - 形式 A: 文字列単独（例: `"nextjs-supabase"`）
   - 形式 B: オブジェクト（例: `{ id: "playwright", options: { base_url: "http://localhost:3000" } }`）
2. メンテナが `packages/core/schema/.stdd.config.schema.json` の `plugins` 定義を確認し、両形式を受け入れていることを検証する
3. メンテナが両形式を含む `.stdd.config.yml` サンプルを `ajv-cli validate` で検証する

#### 期待結果

- 文字列形式・オブジェクト形式の両方を含む `.stdd.config.yml` が schema 検証を通過する
- `options` を伴わない最小オブジェクト形式（`{ id: "..." }`）も検証を通過する
- 不正形式（例: `id` を欠いたオブジェクト、空文字列）は検証で reject される

---

### 公開後に外部開発者が初めてリポジトリを訪れる

**Priority**: P1 (Important)

#### 手順

1. 外部開発者が GitHub 上で stdd リポジトリのトップページを開く
2. README.md の冒頭で「STDD とは何か」「現時点で対応している AI エージェント（Claude Code）」「v0.1.0 では CLI が未実装でテンプレートを手動コピーする方式」を確認する
3. AGENTS.md でエージェント設定の概要を確認する
4. 興味を持った場合、CONTRIBUTING.md を開いて貢献方法を確認する
5. issue を作成しようとした場合、4 種類のテンプレートから適切なものを選択する

#### 期待結果

- README 冒頭 3 段落以内で「STDD は何で、何のためのものか」が伝わる
- CLI 未実装期の利用方法（テンプレート手動コピー）が明示されており、外部開発者が誤って `npx create-stdd-project` を打つ前に「CLI は Phase 2-B で提供予定」と認識できる
- issue / PR テンプレートが日本語で記述されており、コントリビュータが何を書けばよいか迷わない

---

### プラグイン skill 移動が core skill の参照を破壊しないことを確認する

**Priority**: P1 (Important)

#### 手順

1. メンテナが core 10 skill 内に、移動した 5 skill への内部リンク（例: `.claude/skills/implementing-ui/...` への相対パス参照）が残っていないか grep で確認する
2. 残存していた場合、リンクを汎用化された表現（「UI 実装プラグインの該当 skill を参照」等）に書き換える

#### 期待結果

- core skill 内に `.claude/skills/{implementing-ui,migrating-supabase,e2e-testing,run-e2e,remove-worktree}` への直接パス参照が 0 件である
- リンク切れによる skill 実行時のエラーが発生しない

---

### 外部開発者が `careerchain-ys/stdd` という URL を見て混乱する

**Priority**: P2 (Nice to Have)

#### 手順

1. 外部開発者が `packages/core/README.md` または JSON Schema の `$id` フィールドで `https://raw.githubusercontent.com/careerchain-ys/stdd/...` という URL を発見する
2. 「careerchain」という組織名が何を意味するのか疑問に思う

#### 期待結果

- TECH_DESIGN.md および `packages/core/README.md` 内に「この組織名は公開リポジトリのホスト組織名であり、stdd の利用に CareerChain 固有の依存はない」旨の説明が存在する
- 外部開発者が URL 上の組織名を見ても、stdd の中立性に対する誤解を抱かない

---

## 3. UI / UX デザイン

Phase 2-A は CLI / GUI を含まず、リポジトリ構造とドキュメントのみが成果物のため、画面のワイヤーフレームは持たない。代わりに**Phase 2-A 完了時点のリポジトリ構造**を示す。

### Phase 2-A 完了時のリポジトリツリー（抜粋）

```
stdd/
├── README.md                              (新規)
├── AGENTS.md                              (新規)
├── CONTRIBUTING.md                        (新規)
├── CODE_OF_CONDUCT.md                     (新規)
├── LICENSE                                (現状維持)
├── NOTICE                                 (現状維持)
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── skill-request.md               (新規)
│   │   ├── bug-report.md                  (新規)
│   │   ├── plugin-proposal.md             (新規)
│   │   └── agent-support-request.md       (新規)
│   └── pull_request_template.md           (新規)
├── .claude/
│   ├── agents/                            (固有名詞除去のみ、構造維持)
│   ├── docs/
│   │   └── spec-driven-development-guide.md  (固有名詞除去のみ)
│   └── skills/                            (core 10 skill のみが残る)
│       ├── documenting-specifications/
│       ├── documenting-plans/
│       ├── auto-implement/
│       ├── verify-consistency/
│       ├── reverse-engineering-stdd/
│       ├── create-pr/
│       ├── review-pr-with-agents/
│       ├── kaizen/
│       ├── search-first/
│       └── software-architecture/
├── plugins/                               (新規ディレクトリ)
│   ├── nextjs-supabase/
│   │   ├── plugin.json                    (新規)
│   │   └── skills/
│   │       ├── implementing-ui/           (移動)
│   │       └── migrating-supabase/        (移動)
│   ├── playwright/
│   │   ├── plugin.json                    (新規)
│   │   └── skills/
│   │       ├── e2e-testing/               (移動)
│   │       └── run-e2e/                   (移動)
│   └── worktree/
│       ├── plugin.json                    (新規)
│       └── skills/
│           └── remove-worktree/           (移動)
├── packages/core/
│   └── schema/.stdd.config.schema.json    (plugins 定義を確認・必要なら更新)
└── docs/
    ├── plugin-separation-policy.md        (固有名詞除去のみ)
    ├── phase1/plans/2026-05-17-core.md    (固有名詞除去のみ)
    └── phase2/specs/                      (本 PR で新規)
        ├── REQUIREMENTS.md
        └── TECH_DESIGN.md
```

削除されるファイル / ディレクトリ:

- `SYNC_POLICY.md`
- `audit/PHASE0_AUDIT_REPORT.md`（および `audit/` ディレクトリ自体）

### 表示要素（README.md 構成）

| 要素                  | 説明                                                                       |
| --------------------- | -------------------------------------------------------------------------- |
| プロジェクト概要      | STDD とは / なぜ TDD でなく STDD か（2-3 段落）                            |
| 対応 AI エージェント  | v0.1.0 時点で Claude Code のみ。他エージェントの対応見通しに言及          |
| Quick Start           | CLI 未実装期はテンプレート手動コピー手順。CLI 提供時期（Phase 2-B）に言及 |
| ディレクトリ構成      | 主要ディレクトリ（`packages/core/` / `plugins/` / `.claude/`）の説明      |
| 関連ドキュメント      | AGENTS.md / CONTRIBUTING.md / CODE_OF_CONDUCT.md / LICENSE へのリンク     |
| ライセンス            | Apache License 2.0                                                         |

### 表示要素（PR テンプレート構成）

| 要素                    | 説明                                                                              |
| ----------------------- | --------------------------------------------------------------------------------- |
| 変更概要                | 何を変更するか                                                                    |
| 関連 issue              | 関連 issue 番号（PR 本文記法で issue を自動クローズできる形式）                   |
| テスト結果              | 実行したテスト・結果の貼り付け                                                    |
| 評価結果 (eval-result)  | skill / agent 変更時の評価スコア。Phase 2-C で QA gate と連動する想定の事前項目  |
| チェックリスト          | DCO sign-off / docs 更新 / 破壊的変更の有無                                       |

---

## 4. エッジケース

### git mv の代わりに rm + add がなされてしまう

- skill ディレクトリを移動する際に `git mv` ではなく削除 → 追加で扱われると、git の rename 検出閾値を下回り `git log --follow` で履歴が追えなくなる
- 対策: 移動コマンドを `git mv <src> <dst>` で明示的に実施し、コミット後に `git log --follow plugins/.../SKILL.md` で過去履歴が見えることを確認する

### `careerchain-worktree-N` という命名が複数 skill にまたがって登場する

- `auto-implement` / `run-e2e` / `remove-worktree` で同じ命名パターンが個別に書かれている
- 対策: 各ファイルで個別に置換する。一括 sed で全リポジトリを書き換えると `LICENSE` 等を破壊する恐れがあるため、対象ファイルを明示してから置換する

### `.claude/skills/` 内の core skill が依然として `CareerChain` を含んでいる

- `software-architecture` / `migrating-supabase` / `implementing-ui` の SKILL.md 冒頭に「CareerChainプロジェクトにおける〜」という記述がある
- このうち `migrating-supabase` / `implementing-ui` はプラグイン側に移動するため、移動先で書き換えを行う（core 残留 skill では `software-architecture` のみが対象）
- 対策: 移動と書き換えの順序を「移動 → 書き換え」とし、移動後のパスを基準に書き換える

### Contributor Covenant 2.1 の日本語訳が複数バージョン存在する

- 公式翻訳 / コミュニティ翻訳が混在しており、どれを採用するか曖昧になる
- 対策: 公式サイト（`https://www.contributor-covenant.org/ja/version/2/1/code_of_conduct/`）の翻訳をそのまま貼り付け、出典 URL を末尾に明記する

### Phase 1-A の PLAN ドキュメント内の URL 参照

- `docs/phase1/plans/2026-05-17-core.md` 内に `github.com/careerchain-ys/careerchain/issues/1292` という URL がある
- これは社内プロジェクトの issue 番号であり、公開リポジトリでは到達不能になる
- 対策: 該当箇所を「Phase 1-A」「Phase 0」のような Phase 表記に置換し、社内 issue 番号は削除する

---

## 5. 成功基準

- [ ] `.claude/skills/` 配下に core 10 skill のみが存在し、移動対象 5 skill が `plugins/<plugin-id>/skills/` 配下に再配置されている
- [ ] 3 つのプラグインディレクトリそれぞれに `plugin.json` が存在し、JSON 構文として valid である
- [ ] リポジトリルートに README.md / AGENTS.md / CONTRIBUTING.md / CODE_OF_CONDUCT.md が存在し、すべて日本語で記述されている
- [ ] `.github/ISSUE_TEMPLATE/` に 4 種類のテンプレートが配置され、`.github/pull_request_template.md` に評価結果セクションが含まれている
- [ ] `SYNC_POLICY.md` および `audit/` ディレクトリ（および配下の `PHASE0_AUDIT_REPORT.md`）が削除されている
- [ ] `grep -rIn -E '(careerchain|CareerChain|キャリアチェーン)' .` のヒットが LICENSE / NOTICE / 公開 URL 文字列のみである
- [ ] `packages/core/schema/.stdd.config.schema.json` の `plugins` 定義が、文字列形式・`{ id, options }` オブジェクト形式の両方を受け入れる
- [ ] core skill 内に移動した 5 skill への直接パス参照が残っていない
- [ ] git の `--follow` オプションで移動後の skill の過去履歴が連続して追える

---

## 6. スコープ外

- **CLI `create-stdd-project` の実装**: Phase 2-B で実施
- **`examples/nextjs-supabase-todo/` のサンプルアプリ実装**: Phase 2-C で実施
- **v0.1.0 タグ付け・リポジトリ公開化**: Phase 2-F で実施（ユーザー操作が必要）
- **auto-implement quick success rate ≥80% N=5 の達成**: Phase 2-C の QA gate で実施
- **プラグイン npm パッケージ化**: `@stdd/plugin-*` としての配布は将来の別 Phase で実施。Phase 2-A はディレクトリ構造の整備までを対象とする
- **プラグインの動作確認**: Phase 2-A は物理的な移動とディレクトリ宣言までを対象とし、実際に skill が読み込まれるかの統合テストは行わない
- **英訳ドキュメント**: 日本語のみで進める
- **`packages/core/templates/` の修正**: 固有名詞除去済みのため対象外
- **GitHub Actions / CI ワークフロー**: Phase 2-A ではテンプレートのみ追加し、自動化ワークフローは別途
- **SECURITY.md**: パブリックリリース直前（Phase 2-B 〜 Phase 2-C）に追加する。脆弱性報告窓口（メール / Issue policy）の整備とセットで対応する必要があり、Phase 2-A の範囲では文書のみ先行させず、報告フロー設計と同時に提供する方針とする
