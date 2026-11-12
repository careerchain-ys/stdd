# コードリーディングガイド - 実装を読む順序と、読みながら控える項目

[SKILL.md](../SKILL.md) の Phase 1（実装コードリーディング）で、各層の読み方と控える項目を確かめるときに読む。

## 読む順序

以下の順序で実装を精読し、機能の全体像を把握する。

**1. ページ/画面コンポーネント**（エントリーポイント）
```
# 例: Next.js での一例
<app>/app/<path>/page.tsx
```
- レンダリング方式（例: サーバーコンポーネント or クライアントコンポーネント）の判定
- データ取得方法（例: Server Component直接 / Server Actions）
- レイアウト構成

**2. クライアント/UI コンポーネント**（UIとインタラクション）
```
# 例: Next.js / React での一例
<app>/app/<path>/*Client.tsx
<app>/components/<name>.tsx
```
- フォーム項目、ボタンラベル、表示テキストを**正確に**読み取る
- 状態管理（例: useState, useForm）
- 条件分岐によるUI出し分け

**3. バリデーション定義**（入力ルール）
```
# 例: Zod スキーマでの一例
<app>/app/<path>/schema.ts
<app>/lib/schemas/<name>.ts
```
- バリデーション定義（例: Zod スキーマ）の各フィールドのルールを**正確に**読み取る
  - 桁数・上限・形式・カスタム検証（例: Zod の `min()`, `max()`, `regex()`, `refine()`）の具体値
  - エラーメッセージ文言（例: Zod の `message` プロパティ）
  - 任意/null 許容の有無（例: Zod の `optional()`, `nullable()`）

**4. ハンドラ/ビジネスロジック層**（ビジネスロジック）
```
# 例: Server Actions での一例
<app>/app/<path>/actions.ts
<app>/actions/<name>.ts
```
- 入力→処理→出力のフロー
- エラーハンドリング

**5. ドメイン層**（データモデルとデータアクセス）
```
# 例: domain 層での一例
<app>/domain/models/<name>.ts
<app>/domain/repository/<name>.ts
<app>/domain/service/<name>.ts
```
- Entity型定義（例: domain/models 配下）
- CRUD操作の実装（例: データアクセス層 / repository）
- ビジネスルール（例: ドメインサービス層 / service）

**6. DBスキーマ**（テーブル定義）
```
# 例: Supabase の生成された DB 型定義での一例
supabase/generated/database.types.ts
```
- テーブル名、カラム名を**正確に**確認
- リレーション

## コードリーディング時のメモ取り

以下の情報を収集しながら読む:

```
□ ページURL・ルーティング構成
□ 画面遷移フロー
□ フォーム項目（名前、型、必須/任意、バリデーションルール）
□ ボタンラベル・アクション
□ 条件分岐（表示/非表示、有効/無効）
□ エラーハンドリング（エラーメッセージ文言）
□ 使用しているDB テーブル・カラム
□ 外部サービス連携（API呼び出し等）
```

> 上記のファイルパスは代表スタック（例: Next.js / Supabase）での一例。採用スタックの配置に読み替えること。
