---
name: プラグイン提案
about: 新規プラグインの追加（新しい技術スタック対応）を提案する
title: "[plugin] "
labels: ["plugin-proposal", "triage"]
---

## プラグイン概要

提案するプラグインの目的・対象とする技術スタックを記述してください。

- プラグイン ID（kebab-case、`@stdd/plugin-<id>` の `<id>` 部分）:
- 対象技術スタック（例: Remix + Prisma, Vue + Pinia 等）:

## 提供する skill

このプラグインが提供する skill の一覧を記述してください。各 skill について、想定される責務を簡潔に記述してください。

| skill ID | 責務 |
| -------- | ---- |
|          |      |
|          |      |

## 既存プラグインとの関係

- 重複する skill がないか:
- 既存プラグイン（`nextjs-supabase`, `playwright`, `worktree`）への依存があるか:

## 利用シーン

- どのようなプロジェクトでこのプラグインが有用か:
- 既に同種の機能を実装している外部 OSS があれば参考リンク:

## 設定オプション

`.stdd.config.yml` の `plugins` フィールドで受け取る `options` の例があれば記述してください。

```yaml
plugins:
  - id: <plugin-id>
    options:
      key: value
```

## 実装担当

- 提案者自身が実装するか / 他のコントリビュータを募るか:

## その他

- 関連 issue / PR:
- 参考リンク:
