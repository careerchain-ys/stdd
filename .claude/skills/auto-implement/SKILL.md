---
name: auto-implement
description: |-
  GitHub issue を起点として、Spec 作成（要件→技術設計）→PLAN 作成→実装（STDD）→QA→コードレビュー→Figma 更新→PR 作成までを専門エージェント（Requirements Writer / Tech Specs Writer / Implementer / QA Engineer / Code Reviewer 等）にオーケストレーションして自動実行する。
when_to_use: |-
  「auto implement」「自動実装」「issue から実装」「issue 番号を指定して実装」「Agent Teams で実装」「issue を元に PR まで」「#123 を実装して」など、GitHub issue を起点とした包括的な自動実装の依頼があったとき。
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent
---

# issue 起点の自動実装オーケストレーション

GitHub issueを受け取り、Spec作成→実装→QA→コードレビュー→PR作成までを自動で実行するオーケストレーションスキル。

## 引数

**形式**: `#<issue番号> [--mode <full|spec-only|impl-only|quick>]`

## Step 1: 引数パース

引数から以下を抽出:

- **issue番号**: `#123` 形式（必須）
- **実行モード**: `--mode` オプション（任意）

issue番号が指定されていない場合はエラーメッセージを表示して終了。

## Step 2: issue情報の取得

GitHub MCP toolsまたは `gh issue view` を使ってissue情報を取得する。

取得する情報:

- タイトル
- 本文（description）
- ラベル
- コメント

## Step 3: 実行モード判定

`--mode` が指定されている場合はそのモードを使用。未指定の場合は以下のロジックで自動判定:

| 条件                                                                                        | モード      |
| ------------------------------------------------------------------------------------------- | ----------- |
| ラベルに `bug` を含む                                                                       | `impl-only` |
| ラベルに `documentation` を含む、またはタイトルに「Spec」「リバースエンジニアリング」を含む | `spec-only` |
| タイトルに「typo」「修正」を含む、またはissue本文が短い（200文字以下）                      | `quick`     |
| 上記いずれにも該当しない                                                                    | `full`      |

判定結果を表示し、**`--mode` が未指定の場合はユーザーに確認を求める**:

```
実行モード: <mode>（自動判定理由: <reason>）

このモードで実行してよろしいですか？（y/n、または別のモードを指定: full / spec-only / impl-only / quick）
```

承認されるまで次のステップに進まないこと。

## Step 4: ブランチ作成・Worktree準備

`.stdd.config.yml` の `project.primary_branch` を統合先ブランチとして読み取る。

```bash
# <primary_branch> は .stdd.config.yml の project.primary_branch
git fetch origin <primary_branch>
```

issueタイトルからブランチ名を生成（`<branch_prefix><kebab-case-summary>`。`branch_prefix` は `.stdd.config.yml` の `workflow.branch_prefix`、既定 `claude/`）。
Worktree作成スクリプトを実行:

```bash
./scripts/create-worktree.sh -b claude/<branch-name> -i <instance-id>
```

devcontainerを起動:

```bash
devcontainer up --workspace-folder ../worktree-<instance-id> --override-config ../worktree-<instance-id>/.devcontainer/devcontainer.override.json
```

以降の作業はすべてworktree内のdevcontainerで実行する。

## Step 4.5: issueをIn Progressに移動

GitHub Projectのステータス更新の手順は [references/github-project.md](references/github-project.md) を参照。
`project` スコープが必要。トークンにスコープがない場合はスキップしてStep 5に進む。

## Step 5: フェーズ実行

このスキルは **Team Lead（オーケストレーター）** として動作し、専門エージェントにタスクを依頼しながら開発フロー全体を統括する。

### チーム編成

```
Team Lead（オーケストレーター）      ← このスキル自身
 ├→ Requirements Writer   : REQUIREMENTS.md 作成（要件: What & Why）
 ├→ Requirements Reviewer : REQUIREMENTS.md の品質・網羅性・SSOT をレビュー
 ├→ Tech Specs Writer    : TECH_DESIGN.md + TEST_PLAN.md 作成（技術設計: How / common 技術階層も担当）
 ├→ Tech Specs Reviewer  : 技術設計・テスト戦略の品質・整合性・SSOT をレビュー
 ├→ Plan Writer          : タスク分解・実装計画（PLANドキュメント）を作成
 ├→ Implementer          : テスト作成 → 実装（STDDフロー）
 ├→ Test Reviewer        : テスト戦略準拠・形骸的テスト検出・テストコード品質レビュー
 ├→ Build Error Resolver : ビルド・型エラーの段階的修正（エラー発生時に自動起動）
 ├→ QA Engineer          : Playwright MCP動作確認・テスト実行・整合性チェック・simplify
 ├→ Code Reviewer        : PRレビュー・コード品質・セキュリティチェック
 ├→ Penetration Tester   : 攻撃者視点での脆弱性検証・エクスプロイト試行
 └→ Figma Updater        : UIキャプチャ→Figmaファイル更新（Team Leadが直接実行）
```

**Team Leadの役割**:

- 各フェーズで対応するエージェントに作業を依頼する
- エージェントの成果物を受け取り、次のフェーズに引き渡す
- 問題が発生した場合は適切なエージェントに修正を依頼し、最大3回の修正ループを管理する
- **人間レビューゲートを尊重する**: Phase 1a（要件）と Phase 1b（技術設計）はエージェントレビュー承認後に**ユーザー（人間）のレビュー**を仰ぐ。ユーザーの承認を得るまで次フェーズに進まない（詳細は phases.md）
- 全フェーズの完了後にPRを作成し、ユーザーに報告する

各フェーズの詳細な手順は [references/phases.md](references/phases.md) を参照。
モードに応じて以下のフェーズを順次実行する:

| Phase      | 名称                          | full | spec-only | impl-only | quick |
| ---------- | ----------------------------- | ---- | --------- | --------- | ----- |
| Phase 1a   | 要件作成 → 人間レビューゲート①  | ✓    | ✓         |           |       |
| Phase 1b   | 技術設計作成 → 人間レビューゲート② | ✓    | ✓         |           |       |
| Phase 1.5  | PLAN作成                      | ✓    |           | ✓         |       |
| Phase 2   | 実装                   | ✓    |           | ✓         | ✓     |
| Phase 2.5 | テストレビュー         | ✓    |           | ✓         |       |
| Phase 3   | QA                     | ✓    |           | ✓         |       |
| Phase 4   | コードレビュー         | ✓    |           | ✓         |       |
| Phase 4.3 | ペネトレーションテスト | ✓    |           | ✓         |       |
| Phase 4.5 | Figma更新              | ✓    |           | ✓         |       |
| Phase 5   | PR作成                 | ✓    | ✓         | ✓         | ✓     |

## Step 6: 完了報告

以下の形式で結果を報告:

```
## 実行完了

- **Issue**: #<issue番号> <タイトル>
- **モード**: <mode>
- **ブランチ**: <branch-name>
- **PR**: <PR URL>

### フェーズ実行結果
| フェーズ | 状態 | 備考 |
|---------|------|------|
| 要件作成（REQUIREMENTS） | OK / SKIP | |
| 要件レビュー | OK / SKIP | |
| 人間レビューゲート①（要件） | OK / SKIP | |
| 技術設計作成（TECH_DESIGN+TEST_PLAN） | OK / SKIP | |
| 技術設計レビュー | OK / SKIP | |
| 人間レビューゲート②（技術設計） | OK / SKIP | |
| PLAN作成 | OK / SKIP | |
| テスト作成 | OK / SKIP | |
| テストレビュー | OK / SKIP | |
| 実装 | OK / SKIP | |
| QA | OK / SKIP | |
| コードレビュー | OK / SKIP | |
| ペネトレーションテスト | OK / SKIP | |
| Figma更新 | OK / SKIP | |
| PR作成 | OK | |
```

## エラーハンドリング

- 各フェーズで3回の修正ループを超えた場合、そのフェーズで停止し、現状をコミット・pushしてdraft PRを作成する
- PR descriptionに未解決の問題を記載し、手動対応を依頼する

## 注意事項

- Agent Teamsの実験的機能を使用（`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`）
- コスト管理のため、各Teammateは該当フェーズでのみ起動する
- Worktreeベースの開発フローに従う
- CLAUDE.mdのすべてのルールを遵守する
