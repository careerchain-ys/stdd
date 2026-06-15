# TABLE_DEFINITION.md テンプレート（common）

**目的**: プロジェクトの全テーブル定義を集約する SSoT（実装・DB 設計・QA が参照する）。各 feature の `TECH_DESIGN.md` は本書を**参照**し、テーブル・カラムを再定義しない。

**配置**: `docs/common/TABLE_DEFINITION.md`（`.stdd.config.yml` の `docs.layout.common_table_definition` に従う）

## 章立ての骨格

- テーブルごとに「カード（見出し＋カラム表）」で表現する。
- 列は **`カラム名 / データ型 / NULL / 説明`** の 4 列。主キーは `🔑` で示す。
- **ER 図は持たない**（リレーションが必要な場合は各カラムの説明に「FK → <table>.<column>」と記す）。
- テーブルが多い場合はドメイングループ見出し（`# ユーザー系` 等）で束ねる。

**含めない**:

- インデックス / RLS / トリガ等の DB メタデータ詳細 → 必要なら各 feature の `TECH_DESIGN.md`（ロジック設計 / 非機能要件）
- 集計・変換などのロジック設計 → 各 feature の `TECH_DESIGN.md`（ロジック設計）
- 実装の進捗・履歴（SSoT として常に最新のスキーマのみ保持する）

## 確度マーカーの運用

- 確信が持てないカラム・型は、説明欄に **要確認マーカー** を仮説とセットで置く（`⚠️要確認(仮説: … / 確認: …)`）。ユーザーが是非を確定したら除去する。構文の SSoT は [documenting-specifications SKILL「要確認マーカー」](../SKILL.md) を参照。

## テンプレート構造

````markdown
# [サービス名] テーブル定義

> 全テーブル定義の SSoT。各機能の `TECH_DESIGN.md` は本書を参照する。
> 生成された型定義 / マイグレーションを正とし、本書はそれに追従する。
>
> **最終更新**: [yyyy-mm-dd]

## 設計方針

- **主キー**: [UUID / 連番 等]
- **削除方針**: [論理削除 / 物理削除・判定カラム（例: `deleted_at IS NULL` で有効）]
- **時系列**: [`created_at` / `updated_at` の方針]
- **命名規則**: [テーブル / カラムの命名規則]

---

## [ドメイングループ名（例: ユーザー系）]

### users   （PK: user_id ・ N カラム）

| カラム名 | データ型 | NULL | 説明 |
| --- | --- | --- | --- |
| 🔑 user_id | UUID | NOT NULL | ユーザー ID |
| email | VARCHAR(255) | 許容 | メールアドレス |
| referred_by | UUID | 許容 | 紹介元ユーザー ID（FK → users.user_id） |
| status | INTEGER | 許容 | 状態区分 |
| last_login_at | TIMESTAMP | 許容 | 最終ログイン日時（最新のみ・履歴なし） |
| created_at | TIMESTAMP | NOT NULL | 登録日時 |
| updated_at | TIMESTAMP | 許容 | 更新日時 |
| deleted_at | TIMESTAMP | 許容 | 論理削除日時（NULL で有効レコード） |

### [次のテーブル]   （PK: [pk] ・ N カラム）

| カラム名 | データ型 | NULL | 説明 |
| --- | --- | --- | --- |
| 🔑 [col] | [type] | NOT NULL | ... |
| [col] | [type] | 許容 | ... |
````

## 記述基準

- **型は DB の論理型で表記**（`UUID` / `VARCHAR(255)` / `INTEGER` / `TIMESTAMP` / `BOOLEAN` / `JSONB` 等）。言語固有の型（TS 型等）は持ち込まない（→ feature の TECH_DESIGN）。
- **NULL 列は `NOT NULL` / `許容` の 2 値**で統一。
- FK は説明欄に `FK → <table>.<column>` と明記する（ER 図の代替）。
- 既存 DB に同名カラムがある場合はそれを正とし、無い場合は新規追加として説明欄に「新規」と注記する。

## 記述しない内容（責務分界）

- 集計・変換・ドメインロジック → 各 feature の `TECH_DESIGN.md`（ロジック設計）
- 画面項目とのマッピング → 各 feature の `TECH_DESIGN.md`（画面項目定義）
- インデックス / RLS / トリガ等の詳細 → 必要に応じて feature の `TECH_DESIGN.md`
- 履歴・経緯・version（SSoT 原則）
