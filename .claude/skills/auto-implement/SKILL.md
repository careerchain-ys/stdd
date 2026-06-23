---
name: auto-implement
description: |-
  実装したい課題（GitHub issue / 自由記述の要望 / 既存ドキュメント / URL 等、あらゆる入力）を起点として、まずユーザーへのヒアリングで対象を確定し、Spec 作成（要件→技術設計）→PLAN 作成→実装（STDD）→QA→コードレビュー→Figma 更新→PR 作成までを専門エージェント（Requirements Writer / Tech Specs Writer / Implementer / QA Engineer / Code Reviewer 等）にオーケストレーションして自動実行する。
when_to_use: |-
  「auto implement」「自動実装」「これを実装して」「PR まで作って」「Agent Teams で実装」「issue から実装」「#123 を実装して」など、課題・要望（issue に限らず自由記述やドキュメントでも可）を起点とした包括的な自動実装の依頼があったとき。入力が曖昧でも、最初のヒアリングで対象を具体化してから進める。
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent
---

# 自動実装オーケストレーション

実装したい課題（GitHub issue / 自由記述の要望 / 既存ドキュメント / Slack・Notion などの参照 / URL）を受け取り、ヒアリングで対象を確定したうえで、Spec作成→実装→QA→コードレビュー→PR作成までを自動で実行するオーケストレーションスキル。

**入力は GitHub issue に限らない。** issue 番号があればそれを使うが、無くてもよい。入力が無い / 曖昧な場合は **Step 1 のヒアリング**で対象を具体化してから進める。

## 引数

**形式**: `[<入力>] [--mode <full|spec-only|impl-only|quick>]`

- `<入力>`（任意）: `#<issue番号>` / issue URL / 自由記述のタスク説明 / ドキュメントのパス・URL のいずれでも可。省略可能。
- `--mode`（任意）: 実行モード。

## Step 1: 入力のヒアリングと確定

auto-implement の対象（実装したい issue / 課題 / 要望）を確定するフェーズ。**いきなり実装に進まず、まずここで対象を明確にする。**

1. **初期入力の取り込み**: 引数で入力が与えられていれば、その種別を判定する。
   - `#<番号>` または issue URL → **GitHub issue**（Step 2 で `gh` 取得）
   - 自由記述のテキスト → **タスク記述**としてそのまま扱う
   - ファイルパス / ドキュメント URL → 読み込んで**タスク記述**の素材にする
2. **ヒアリング**: 入力が無い、または上記だけでは auto-implement を始めるのに不十分な場合は、ユーザーに以下を確認する（`AskUserQuestion` 等で簡潔に）:
   - **何を実装したいか**（目的・背景・解決したい課題）
   - **入力ソース**（GitHub issue / 自由記述 / 既存ドキュメント / その他）— issue なら番号を聞く
   - **スコープ・制約**（対象アプリ / 機能、含める・含めないもの、既知の制約）
3. **確定**: 課題内容が「Spec 作成に着手できる程度」に具体化できたら、要点をユーザーに復唱して確認を取る。曖昧なまま先に進まない。

このヒアリングの結果（タスクのタイトル相当・本文相当・スコープ）を、以降のフェーズの**入力（タスク記述）**として扱う。

## Step 2: 入力情報の取得・正規化

Step 1 で確定した入力を、以降のフェーズが扱える**タスク記述**（タイトル相当・本文相当・補足）に正規化する。

- **GitHub issue の場合**: GitHub MCP tools または `gh issue view` で取得する。
  - タイトル / 本文（description） / ラベル / コメント
- **issue 以外の場合**（自由記述・ドキュメント等）: ヒアリング結果や参照ドキュメントから、タイトル相当・本文相当・スコープを構成する。ラベルは無いものとして扱う。

以降のステップで「issue」と記載がある箇所は、issue 以外の入力ではこの正規化済みタスク記述に読み替える。

## Step 3: 実行モード判定

`--mode` が指定されている場合はそのモードを使用。未指定の場合は以下のロジックで自動判定する（issue 以外の入力では「ラベル」条件は対象外。タイトル・本文の内容で判定する）:

| 条件                                                                                        | モード      |
| ------------------------------------------------------------------------------------------- | ----------- |
| （issue の場合）ラベルに `bug` を含む / 不具合の修正が主目的                                 | `impl-only` |
| ラベルに `documentation` を含む、またはタイトルに「Spec」「リバースエンジニアリング」を含む | `spec-only` |
| タイトルに「typo」「修正」を含む、または本文が短い（200文字以下）                           | `quick`     |
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

タスク記述のタイトル（issue タイトル、または Step 1 で確定したサマリ）からブランチ名を生成（`<branch_prefix><kebab-case-summary>`。`branch_prefix` は `.stdd.config.yml` の `workflow.branch_prefix`、既定 `claude/`）。
Worktree作成スクリプトを実行:

```bash
./scripts/create-worktree.sh -b claude/<branch-name> -i <instance-id>
```

devcontainerを起動:

```bash
devcontainer up --workspace-folder ../worktree-<instance-id> --override-config ../worktree-<instance-id>/.devcontainer/devcontainer.override.json
```

以降の作業はすべてworktree内のdevcontainerで実行する。

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

- **対象**: <GitHub issue なら `#<issue番号> <タイトル>`、それ以外はタスクのサマリ>
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
