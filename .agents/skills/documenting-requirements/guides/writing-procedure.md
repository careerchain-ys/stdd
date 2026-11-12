# REQUIREMENTS.md を書く前の確認

REQUIREMENTS.md の作成・更新を始める前に行う確認。章立て・EARS・SSOT 原則は [SKILL.md](../SKILL.md) に従う。

## 1. 読むもの

- 対象機能と類似機能の `docs/` 配下の Spec、common 階層の REQUIREMENTS.md
- ユーザーから見える挙動を把握するための、関連する既存コード
- `AGENTS.md` / `CLAUDE.md` / `.claude/docs/coding-conventions.md`（存在する場合）

## 2. 追記か新規作成か

配置（`.stdd.config.yml` の `docs.layout.requirements`）に REQUIREMENTS.md が既にあるかを確かめ、あれば読んでから決める。

| 判断 | 条件 | 書き方 |
| --- | --- | --- |
| 追記 | 既存と同じ機能・ページの拡張・変更 | 既存のユースケースと同列に並べ、構成・見出しの形式を合わせる |
| 新規作成 | まったく新しい機能・ページ | [テンプレート](../templates/requirements.md) から作る |
| 迷う | どちらとも取れる | ユーザーに確かめる |

## 3. 書かないもの

- 技術的な詳細（テーブル名、実装ファイル、画面項目定義）とテスト戦略。技術設計（documenting-tech-specs）で書く。
- ファイル構成・実装の順序。PLAN（documenting-plans）で書く。
- 入力の issue の番号・対応の経緯。issue を入力にしても、Spec には現在の仕様だけを書く（SSOT 原則）。

## 4. 書き終えたら

- SKILL.md の Self-check とチェックリストを通す。
- auto-implement から使っているときは、`requirements-reviewer` のレビューに進む（[phases.md](../../auto-implement/references/phases.md) Phase 1a）。
