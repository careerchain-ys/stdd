<!--
共通 API_SPEC.md — STDD API 仕様ドキュメント (プロジェクト全体)

位置づけ:
  - API 入出力契約（パス / メソッド / パラメータ / リクエスト / レスポンス / エラー）の SSoT。
  - 各 feature の TECH_DESIGN.md は本書を参照し、エンドポイントを再定義しない。
  - 処理アルゴリズム（どう集計・計算するか）は各 feature の TECH_DESIGN.md（ロジック設計）に置く。

書き換え方:
  - OpenAPI / Swagger 風の Markdown テーブルで記述する（実 YAML ではない）。
  - REST に限らず Route Handler / RPC / Server Actions も「操作単位」で同形式で表現する。
  - レスポンスの実体は TABLE_DEFINITION.md の該当テーブルへリンクして二重定義を避ける。
-->

# [サービス名] API 仕様

> API 入出力契約の SSoT。各機能の `TECH_DESIGN.md` は本書を参照する。
> 処理アルゴリズムは各 feature の `TECH_DESIGN.md`（ロジック設計）に置く。
>
> **最終更新**: [yyyy-mm-dd] / **ベース URL**: `/api` / **認証**: Supabase セッション（Cookie）

## 共通仕様

- **認証**: 各エンドポイントは Supabase セッションを要求する（未認証は `401 UNAUTHORIZED`）。
- **共通エラー形式**:

  ```json
  { "code": "ERROR_CODE", "message": "ユーザー向けメッセージ" }
  ```

- **共通エラーコード**:

  | コード | HTTP | 意味 |
  | --- | --- | --- |
  | `UNAUTHORIZED` | 401 | 未認証 |
  | `FORBIDDEN` | 403 | 権限なし（RLS で弾かれた等） |
  | `VALIDATION_ERROR` | 400 | 入力検証エラー |
  | `NOT_FOUND` | 404 | リソースが存在しない |

---

## users

### GET /api/users   — ユーザー一覧取得

認証済みユーザーがアクセス可能な users を一覧取得する（論理削除は除外）。

**パラメータ（クエリ）**

| 名前 | 位置 | 型 | 必須 | 説明 |
| --- | --- | --- | --- | --- |
| q | query | string | – | email の部分一致検索 |
| page | query | integer | – | ページ番号（1 始まり・既定 1） |

**レスポンス（200）**

| フィールド | 型 | 説明 |
| --- | --- | --- |
| items | array | ユーザー配列（要素は `TABLE_DEFINITION.md#users`） |
| total | integer | 総件数 |

**エラー**

| コード | HTTP | 条件 |
| --- | --- | --- |
| `UNAUTHORIZED` | 401 | 未認証 |

### POST /api/users   — ユーザー作成

新規ユーザーを作成する。

**リクエストボディ**

| フィールド | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| email | string | ○ | メール形式・最大 255 |

**レスポンス（201）**

| フィールド | 型 | 説明 |
| --- | --- | --- |
| user | object | 作成されたユーザー（→ `TABLE_DEFINITION.md#users`） |

**エラー**

| コード | HTTP | 条件 |
| --- | --- | --- |
| `EMAIL_ALREADY_EXISTS` | 409 | メール重複 |
| `VALIDATION_ERROR` | 400 | 入力検証エラー |

### GET /api/users/{user_id}   — ユーザー詳細取得

（同形式で繰り返す）
