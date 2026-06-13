<!--
共通 TABLE_DEFINITION.md — STDD テーブル定義ドキュメント (プロジェクト全体)

位置づけ:
  - 全テーブル定義の正典 (SSoT)。各 feature の TECH_DESIGN.md は本書を参照し、テーブル・カラムを再定義しない。
  - 生成された型定義 / マイグレーションを正とし、本書はそれに追従する。

書き換え方:
  - テーブルごとに「カード（見出し＋カラム表）」で表現する。列は カラム名 / データ型 / NULL / 説明 の 4 列。
  - 主キーは 🔑 で示す。ER 図は持たない（リレーションは説明欄に FK → <table>.<column> と記す）。
-->

# [サービス名] テーブル定義

> 全テーブル定義の正典（SSoT）。各機能の `TECH_DESIGN.md` は本書を参照する。
>
> **最終更新**: [yyyy-mm-dd]

## 設計方針

- **主キー**: UUID
- **削除方針**: 論理削除（`deleted_at IS NULL` で有効レコード）
- **時系列**: `created_at` / `updated_at` を保持
- **命名規則**: テーブル・カラムは snake_case

---

## ユーザー系

### users   （PK: user_id ・ 6 カラム）

| カラム名 | データ型 | NULL | 説明 |
| --- | --- | --- | --- |
| 🔑 user_id | UUID | NOT NULL | ユーザー ID（Supabase Auth 連携） |
| email | VARCHAR(255) | 許容 | メールアドレス |
| status | INTEGER | 許容 | 状態区分 |
| created_at | TIMESTAMP | NOT NULL | 登録日時 |
| updated_at | TIMESTAMP | 許容 | 更新日時 |
| deleted_at | TIMESTAMP | 許容 | 論理削除日時（NULL で有効レコード） |

### [次のテーブル]   （PK: [pk] ・ N カラム）

| カラム名 | データ型 | NULL | 説明 |
| --- | --- | --- | --- |
| 🔑 [col] | [type] | NOT NULL | ... |
| [col] | [type] | 許容 | ... |
