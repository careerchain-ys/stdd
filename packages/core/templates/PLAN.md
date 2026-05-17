<!--
PLAN.md — STDD 実装計画ドキュメント (セッション単位のタスクリスト)

目的:
  - 1 つの開発セッションで実装するタスクを列挙する
  - REQUIREMENTS.md / TECH_DESIGN.md の Test Strategy に従い、テスト → 実装の順で並べる
  - Spec ドキュメントとは異なり、進捗ステータス (チェックボックス) を保持してよい

配置:
  .stdd.config.yml の `docs.layout.plan` に従う。
  デフォルト例: docs/{{app.id}}/{{feature_path}}/plans/{{date}}.md
  (`{{date}}` はセッション開始日の yyyy-mm-dd)

書き換え方:
  - プレースホルダを実値に置き換え、不要セクションは削除する
  - スコープが大きい場合は複数 PLAN に分割し、それぞれを別セッション扱いにする
  - 「実装スコープ」セクションでセッション開始時に必ずスコープ合意を取る
-->

# PLAN: [機能名] — [yyyy-mm-dd]

関連: REQUIREMENTS.md / TECH_DESIGN.md / 関連 issue #...

---

## 実装スコープ

**対象**: REQUIREMENTS.md / TECH_DESIGN.md のどの範囲を本セッションで実装するか

- [ ] P0: Critical Paths (全て / 一部を指定)
- [ ] P1: Important (全て / 一部を指定)
- [ ] P2: Nice to Have (全て / 一部を指定)

**除外**: 今回のセッションでは実装しないもの

- ...

---

## タスクリスト

### 1. Spec ドキュメント更新 (既存機能への追加・変更の場合)

- [ ] REQUIREMENTS.md の更新
- [ ] TECH_DESIGN.md の更新

### 2. テスト作成 (Red 状態)

**Unit Test**:

- [ ] `{{app.path}}/lib/validation/<schema>/index.test.ts` — バリデーションテスト (N 件)

**Integration Test**:

- [ ] `{{app.path}}/components/<feature>/<Component>/index.test.tsx` — コンポーネントテスト (N 件)

**E2E Test** (P0 のみ):

- [ ] `e2e/tests/{{app.id}}/<feature>.spec.ts` — E2E テスト (N 件)

### 3. 実装 (Green 状態)

**Unit test に対応する実装**:

- [ ] `{{app.path}}/lib/validation/<schema>/index.ts` — バリデーションスキーマ

**Integration test に対応する実装**:

- [ ] `{{app.path}}/actions/<feature>-actions/index.ts` — サーバーアクション
- [ ] `{{app.path}}/components/<feature>/<Component>/index.tsx` — コンポーネント

**E2E test に対応する実装**:

- [ ] `{{app.path}}/app/<feature>/page.tsx` — ページ

### 4. テスト実行・検証

- [ ] Unit test 通過確認
- [ ] Integration test 通過確認
- [ ] E2E test 通過確認
- [ ] 型チェック通過 (`commands.typecheck` に従う)

---

## ファイル構成

今回のセッションで作成 / 変更するファイル一覧。

```
{{app.path}}/
├── app/
│   └── <feature>/
│       └── page.tsx                    # ページコンポーネント (新規 / 既存修正)
├── components/
│   └── <feature>/
│       └── <Component>/
│           ├── index.tsx               # コンポーネント
│           └── index.test.tsx          # Integration test
├── lib/
│   └── validation/
│       └── <schema>/
│           ├── index.ts                # バリデーションスキーマ
│           └── index.test.ts           # Unit test
└── actions/
    └── <feature>-actions/
        ├── index.ts                    # サーバーアクション
        └── index.test.ts               # サーバーアクションテスト
```

**凡例**:

- `(新規)`: 新規作成
- `(既存修正)`: 既存ファイルを修正
- `(既存維持)`: 変更なし (参照のみ)

### 実装詳細

- **ページコンポーネント**: サーバー / クライアントの選択理由
- **サーバーアクション**: 処理フローの概要
- **バリデーション**: 主要なバリデーションルール
- **Domain 層**: Entity / Repository / Service の役割分担

(コード例は記載しない。詳細は実装ファイル自体を参照する)

---

## 実装時の注意事項

セッション中に把握した実装上の注意点を記録。

### 認証 / セッション

- (例) 該当ページは認証後のリダイレクト時のみ機能する
- (例) セッションはリロードや再起動後には維持されない

### エラーハンドリング

- (例) エラー表示: 「認証エラー」タイトルと具体的なメッセージ
- (例) ユーザー対応: フローを最初からやり直す導線を提供

### 外部サービス連携

- (例) 外部メール送信サービスを使用
- (例) 認証プロバイダのトークン検証フロー

---

## 備考

セッション中に発生した課題や決定事項を記録。

- (例) 〇〇 の実装方針について △△ に変更
- (例) 次回セッションへの引き継ぎ事項

---

## 既知の制限事項

現時点での制限や、Out of Scope の項目。

- (例) パスワードリセット: 未実装 (Out of Scope)
- (例) セッション無効化: JWT 戦略のため即時無効化は不可
