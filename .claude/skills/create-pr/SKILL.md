---
name: create-pr
description: |-
  現在のブランチからdevelopへのPull Requestを作成するスキル。差分情報の収集→変更内容の分析→PR descriptionの自動生成→`gh pr create`実行までを一括で行う。「PR作成」「プルリクエスト」「pull request」「PR出して」「developにPR」「create PR」「マージリクエスト」など、ブランチをdevelopにマージするためのPR作成依頼があった際は必ずこのスキルを使用する。
allowed-tools: Bash, Read, Grep
---

# PR作成スキル

現在のブランチからdevelopへのPRを作成する。差分を分析し、適切なtitle/descriptionを自動生成する。

## 1. 差分情報の収集

```bash
git fetch origin develop
```

以下を並列で実行:

```bash
git log --oneline origin/develop...HEAD
git diff origin/develop...HEAD --name-only
git diff origin/develop...HEAD --stat
git branch --show-current
```

必要に応じて変更内容の詳細も確認:

```bash
git diff origin/develop...HEAD
```

## 2. 変更内容の分析

1. **変更の種類を特定**: feat / fix / refactor / docs / test / style / perf / chore
2. **影響範囲を特定**: user_app / admin_app / supabase / e2e / docs
3. **主要な変更点を抽出**: 新規ファイル、削除ファイル、大幅変更ファイル

## 3. Issue情報の確認

引数やコミットメッセージからissue番号（`#123`形式）を検出した場合:

- PR descriptionの末尾に `Closes #123` を追記してissueを自動クローズする
- 複数ある場合は `Closes #123, Closes #456` のように列挙する

## 4. PRの作成

`gh pr create` を使ってPRを作成する。

### タイトル

- 70文字以内
- 変更の種類をprefixに付ける（例: `feat: ユーザー一覧のフィルター機能を追加`）

### Description テンプレート

```markdown
## 概要

[変更の目的・背景を1-2文で説明]

## 変更内容

- [変更点1]
- [変更点2]
- [変更点3]

## 影響範囲

- [ ] user_app
- [ ] admin_app
- [ ] supabase
- [ ] e2e
- [ ] docs

## 確認手順

1. [確認手順1]
2. [確認手順2]

## 備考

[レビュアーへの補足事項があれば記載。なければセクションごと削除]

Closes #[issue番号]
```

### 作成コマンド

bodyは一時ファイル経由で渡す（ヒアドキュメントは避ける）:

```bash
gh pr create --base develop --title "タイトル" --body-file /tmp/pr-body.md
```

## 5. 完了

作成したPRのURLを表示する。

## 注意事項

- 「何が変わったか」「なぜ変わったか」を日本語で端的に記述する
- 技術的な詳細より変更の目的を重視する
- 影響範囲のチェックボックスは該当するもののみチェックを入れる
- 確認手順には実際にレビュアーが確認すべき操作を具体的に記載する
- 機密情報（APIキー、パスワードなど）が含まれていないか確認する
- リモートにpushされていない場合は先にpushする
