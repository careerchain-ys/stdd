# API_SPEC.md テンプレート（common）

**目的**: プロジェクトの API 仕様（入出力契約）を集約する SSoT。各 feature の `TECH_DESIGN.md` は本書を**参照**し、エンドポイントを再定義しない。

**配置**: `docs/common/API_SPEC.md`（`.stdd.config.yml` の `docs.layout.common_api_spec` に従う）

## 章立ての骨格

- OpenAPI / Swagger 風の **Markdown テーブル**で記述する（実 YAML ではない）。
- エンドポイント単位に: **パス / メソッド / 概要 / パラメータ / リクエスト / レスポンス / エラー**。
- REST に限らず、RPC / Server Actions / GraphQL なども「操作単位」で同形式で表現できる。
- **API を持たない構成**（例: フロントから DB を直接参照）では本書は「該当なし」と明記してよい。

**含めない**:

- 各操作の**処理アルゴリズム**（どう集計・計算するか）→ 各 feature の `TECH_DESIGN.md`（ロジック設計）
- クライアント側のエラーハンドリング方針 → 各 feature の `TECH_DESIGN.md`（エラーハンドリング戦略）
- データ構造の定義 → [`TABLE_DEFINITION.md`](./table-definition-common.md)

## テンプレート構造

````markdown
# [サービス名] API 仕様

> API 入出力契約の SSoT。各機能の `TECH_DESIGN.md` は本書を参照する。
> 処理アルゴリズムは各 feature の `TECH_DESIGN.md`（ロジック設計）に置く。
>
> **最終更新**: [yyyy-mm-dd] / **ベース URL**: [https://example.com/api] / **認証**: [Bearer / Cookie 等]

## 共通仕様

- **認証**: [全エンドポイント共通の認証方式]
- **共通エラー形式**:

  ```json
  { "code": "ERROR_CODE", "message": "ユーザー向けメッセージ" }
  ```

- **共通エラーコード**:

  | コード | HTTP | 意味 |
  | --- | --- | --- |
  | `UNAUTHORIZED` | 401 | 未認証 |
  | `FORBIDDEN` | 403 | 権限なし |
  | `VALIDATION_ERROR` | 400 | 入力検証エラー |

---

## [リソース / 機能グループ名]

### POST /api/[resource]   — [操作の概要]

[このエンドポイントが何をするかを 1 行で]

**パラメータ（パス / クエリ）**

| 名前 | 位置 | 型 | 必須 | 説明 |
| --- | --- | --- | --- | --- |
| [id] | path | string | ○ | ... |
| [page] | query | integer | – | ... |

**リクエストボディ**

| フィールド | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| [email] | string | ○ | メール形式・最大 255 |

**レスポンス（200 / 201）**

| フィールド | 型 | 説明 |
| --- | --- | --- |
| [user] | object | 作成されたユーザー（→ `TABLE_DEFINITION.md#users`） |

**エラー**

| コード | HTTP | 条件 |
| --- | --- | --- |
| `EMAIL_ALREADY_EXISTS` | 409 | メール重複 |
| `VALIDATION_ERROR` | 400 | 入力検証エラー |

### GET /api/[resource]/{id}   — [操作の概要]

（同形式で繰り返す）
````

## 記述基準

- フィールド型は論理型（`string` / `integer` / `boolean` / `object` / `array` / `ISO8601` 等）で表記。
- レスポンスの実体（リソース）は `TABLE_DEFINITION.md` の該当テーブルへリンクして二重定義を避ける。
- エラーは「共通エラーコード」に集約し、エンドポイント固有のものだけ各操作の「エラー」表に記す。

## 記述しない内容（責務分界）

- 処理アルゴリズム・集計ロジック → 各 feature の `TECH_DESIGN.md`（ロジック設計）
- クライアントのエラー UX（リトライ / トースト等）→ 各 feature の `TECH_DESIGN.md`（エラーハンドリング戦略）
- データ構造 → `TABLE_DEFINITION.md`
- 履歴・経緯・version（SSoT 原則）
