---
name: review-pr-with-agents
description: |-
  作成済み PR を `qa-engineer` と `code-reviewer` の2つの専門エージェントに並列でレビューさせ、結果を統合報告する。マージ前の最終チェックを2観点（QA観点＝整合性・テスト・論理バグ／コードレビュー観点＝規約・品質・セキュリティ・レスポンシブ）から同時に行う。PR の新規作成は `create-pr` が担い、本スキルは作成済み PR へのレビュー適用に特化する。
when_to_use: |-
  「PRをqa-engineerとcode-reviewerにレビューさせて」「let qa-engineer and code-reviewer handle this pr」「専門エージェントにPRをレビューさせて」「PRをチームレビューに回して」「PRにマルチレビューかけて」「review PR with agents」「PR #123をレビューさせて」「マージ前チェック」「PR最終確認」など、既存の PR を専門エージェントにレビュー依頼するとき。
allowed-tools: Bash, Read, Grep, Glob, Agent
---

# Pull Request マルチエージェントレビュー

作成済みのPRを `qa-engineer` と `code-reviewer` の2エージェントに**並列**でレビューさせ、結果を統合してユーザーに報告する。

## 位置付け

- `create-pr`: PRを新規作成する
- `review-pr-with-agents`（本スキル）: **既にあるPR**を専門エージェントに投げてレビューしてもらう
- `auto-implement` の Phase 3/4 と観点は重なるが、本スキルはパイプライン全体ではなく「レビュー適用のみ」に切り出した単発操作

## 1. PR番号の特定

引数で明示的にPR番号（`#1198` / `1198`）が指定されていればそれを使う。無ければ現在のブランチに紐づくPRを特定する。

```bash
# 現在のブランチに紐づくPR番号を取得
gh pr view --json number,title,headRefName,baseRefName,url
```

該当PRが存在しない場合はその旨をユーザーに伝えて停止（create-pr を案内）。

## 2. PR情報の収集

次をまとめて把握する：

```bash
gh pr view <PR番号> --json number,title,body,headRefName,baseRefName,url,commits,files
git fetch origin <baseRef>
git log --oneline origin/<baseRef>...HEAD
```

集める情報：

- PR番号・タイトル・概要（body）
- base ブランチ（`.stdd.config.yml` の `project.primary_branch`）
- 対象コミット一覧（`origin/<base>...HEAD`）
- 主要な変更ファイル

## 3. worktree / devcontainer の確定

レビュー対象の作業が走っている worktree を確定する。

```bash
git worktree list
```

該当ブランチの worktree パスを控え、対応する devcontainer コマンドのテンプレを用意する：

```
devcontainer exec --workspace-folder <WORKTREE_PATH> --override-config <WORKTREE_PATH>/.devcontainer/devcontainer.override.json bash -c "<COMMAND>"
```

**重要**: devcontainer コマンドは必ず `devcontainer exec` から始める（変数代入を先頭に置かない）。プロジェクトの CLAUDE.md / memory「devcontainerコマンドパターン」を参照。

## 4. 2エージェントを並列起動

`qa-engineer` と `code-reviewer` を**同一メッセージ内の2つの `Agent` 呼び出し**として同時に起動する。片方を待ってから次を投げてはいけない（並列で効率化する意図）。片方をバックグラウンドにしたい場合は `run_in_background: true` を併用してよい。

### 4.1 qa-engineer へのプロンプト雛形

```
PR #<番号> (ブランチ `<headRef>`) のQAレビューを実施してください。

## PR概要
<タイトル>
<body のサマリ>

## 対象コミット（origin/<base> からの N コミット）
<git log --oneline の結果を貼り付け>

## 作業場所
- worktree: <WORKTREE_PATH>
- devcontainer コマンドテンプレ:
  devcontainer exec --workspace-folder <WORKTREE_PATH> --override-config <WORKTREE_PATH>/.devcontainer/devcontainer.override.json bash -c "cd /workspace/<app> && npm test -- --no-cache 2>&1 | tail -80"

## レビュー観点
1. Spec ⇔ テスト ⇔ 実装 の整合性（REQUIREMENTS.md / TECH_DESIGN.md ↔ *.test.* ↔ 実装ファイル）
2. 影響する app のユニットテスト全体 pass/fail（--no-cache で実行）
3. 論理的なバグ・エッジケース
4. seed/マイグレーション変更時は既存データとの整合

## 報告形式
Critical / Major / Minor で分類し、ファイル:行で指摘。テスト結果サマリ含め <文字数制限> 字以内で。
```

### 4.2 code-reviewer へのプロンプト雛形

```
PR #<番号> (ブランチ `<headRef>`, worktree `<WORKTREE_PATH>`) のコードレビューを実施してください。

## PR概要
<タイトル>

## 対象コミット（origin/<base> からの N コミット）
<git log --oneline の結果>

## レビュー観点
1. CLAUDE.md 規約準拠（Domain層構造・命名・コメント方針・npm workspaces 依存ルール）
2. 品質（YAGNI・Rule of Three・過剰設計の排除）
3. セキュリティ（IDOR・XSS・SQLi・認可漏れ・URLパラメータ信頼）
4. レスポンシブ / アクセシビリティ
5. STDD 整合性（Spec → Test → 実装のフロー痕跡）

## 主な変更ファイル
<gh pr view の files 結果を貼り付け>

## 報告形式
Critical / Major / Minor で分類し、ファイル:行で指摘。マージ可否判定と総括を <文字数制限> 字以内で。
```

### 4.3 並列起動時の工夫

- 両エージェントは独立作業のため、どちらかを `run_in_background: true` にして、もう一方が完了してから結果を束ねてもよい
- ただし**片方ずつ起動するのは禁止**（並列化のメリットが消える）。1回のメッセージで2つの Agent tool use を含めること

## 5. 結果の統合・報告

両エージェントのレポートを受け取ったら、重複や類似の指摘をまとめ、以下の形式でユーザーに報告する：

```
## PR #<番号> マルチレビュー結果

### テスト結果（qa-engineer）
- <app名>: X passed / Y skipped / Z failed

### Critical（両エージェント合算）
- （無ければ「なし」）

### Major
- [QA] <指摘内容>（<ファイル:行>）
- [CR] <指摘内容>（<ファイル:行>）

### Minor（概要のみ）
- QA: N件（詳細はエージェント返答参照）
- CR: N件

### 総合判定
- <PASS / 要修正 / ブロッカーあり> の判断を明示
- マージ前に必ず対処すべきもののチェックリスト
```

Critical / Major が残っている場合は「マージ前に対処が必要」と明確に伝え、Minor のみであれば「マージ可能（後続対応可）」の判断を明示する。判断はユーザーの最終決定に委ねるが、推奨は伝える。

## 注意事項

- **独自の判定ロジックは書かない**: 本スキルは `qa-engineer` / `code-reviewer` エージェントへのラッパーであり、評価は各エージェントに委ねる
- **並列起動を徹底**: 同一メッセージで2つ起動しないと時間を無駄にする
- **devcontainer コマンドは先頭から**: `devcontainer exec ...` で始めること。変数代入を先頭に置くとパーミッション承認を都度求められる
- **複合コマンド禁止**: `&&` や `;` を使った複合 Bash コマンドは避ける（プロジェクトの pre-bash-check.sh でブロックされる）
- 既存PRがない状態で呼ばれたら `create-pr` スキルを案内して停止する
