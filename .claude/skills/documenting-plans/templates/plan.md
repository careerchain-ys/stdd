# PLANドキュメント テンプレート

**目的**: セッションごとの実装タスクを管理し、作業計画を明確化する

**配置**: `docs/<app>/<feature-path>/plans/[yyyy-mm-dd].md`

## テンプレート構造

```markdown
# PLAN: [機能名] - [日付]

## 実装スコープ

**対象**: REQUIREMENTS.md / TECH_DESIGN.md のどの範囲を実装するか

- [ ] P0: Critical Paths（全て / 一部を指定）
- [ ] P1: Important（全て / 一部を指定）
- [ ] P2: Nice to Have（全て / 一部を指定）

**除外**: 今回のセッションでは実装しないもの

---

## タスクリスト

### 1. Specドキュメント更新（既存機能の場合）

- [ ] REQUIREMENTS.md の更新
- [ ] TECH_DESIGN.md の更新

### 2. テスト作成（Red状態）

**Unit Test**:
- [ ] `lib/validation/<schema>/index.test.ts` - バリデーションテスト（N件）

**Integration Test**:
- [ ] `components/<feature>/<Component>/index.test.tsx` - コンポーネントテスト（N件）

**E2E Test（P0のみ）**:
- [ ] `e2e/tests/<app>/<feature>.spec.ts` - E2Eテスト（N件）

### 3. 実装（Green状態）

**Unit testに対応する実装**:
- [ ] `lib/validation/<schema>/index.ts` - バリデーションスキーマ

**Integration testに対応する実装**:
- [ ] `actions/<feature>-actions/index.ts` - Server Actions
- [ ] `components/<feature>/<Component>/index.tsx` - コンポーネント

**E2E testに対応する実装**:
- [ ] `app/<feature>/page.tsx` - ページ

### 4. テスト実行・検証

- [ ] Unit test 通過確認
- [ ] Integration test 通過確認
- [ ] E2E test 通過確認
- [ ] `commands.typecheck`（`.stdd.config.yml`）型チェック通過

---

## ファイル構成

今回のセッションで作成・変更するファイルの一覧。

> 以下のファイル構成は Next.js + TypeScript スタックでの一例。`app/`・`actions/`・`domain/` 等の
> 配置やファイル名は採用スタックのレイヤ規約（common `ARCHITECTURE.md`）に読み替えること。

```
<app>/
├── app/
│   └── <feature>/
│       └── page.tsx                    # ページコンポーネント（新規/既存修正）
├── components/
│   └── <feature>/
│       ├── <Component>/
│       │   ├── index.tsx               # コンポーネント（新規/既存修正）
│       │   └── index.test.tsx          # Integration test
├── lib/
│   └── validation/
│       └── <schema>/
│           ├── index.ts                # バリデーションスキーマ（例: Zod）
│           └── index.test.ts           # Unit test
├── actions/
│   └── <feature>-actions/
│       ├── index.ts                    # Server Actions
│       └── index.test.ts               # Server Actions テスト
└── domain/
    ├── models/
    │   └── <entity>.ts                 # Entity定義
    ├── repository/
    │   └── <entity>.ts                 # Repository
    └── services/
        └── <entity>Service.ts          # Service
```

**凡例**:
- `（新規）`: 新規作成するファイル
- `（既存修正）`: 既存ファイルを修正
- `（既存維持）`: 変更なし（参照のみ）

### 実装詳細

各ファイルの実装詳細を記載。

- **UI/画面層**: 描画戦略の選択理由（例: サーバー/クライアントコンポーネントの別）
- **アプリケーション層/ハンドラ**: 処理フローの概要（例: Server Actions）
- **バリデーション**: 主要なバリデーションルール
- **ドメイン層**: Entity/Repository/Serviceの役割分担（採用している場合）

---

## 実装時の注意事項

セッション中に把握した実装上の注意点を記録。

### 認証・セッション

- （例）`/set-password`ページは認証サービスでの認証後のリダイレクト時のみ機能
- （例）セッションはリロードやブラウザ再起動後には維持されない

### エラーハンドリング

- （例）エラー表示: 「認証エラー」タイトルと具体的なメッセージ
- （例）ユーザー対応: フローを最初からやり直す導線を提供

### 外部サービス連携

- （例）メール送信サービスを使用したメール送信
- （例）認証サービスのトークン検証フロー

---

## 備考

セッション中に発生した課題や決定事項を記録。

- （例）XXの実装方針についてYYに変更
- （例）次回セッションへの引き継ぎ事項

---

## 既知の制限事項

現時点での制限や、Out of Scopeの項目。

- （例）パスワードリセット: 未実装（Out of Scope）
- （例）セッション無効化: JWT戦略のため即座の無効化が不可（最大24時間）
```

## 重要なポイント

### ファイル構成セクションについて

**目的**: TECH_DESIGN.mdの「Implementation Notes」に記載されていた内容をPLANドキュメントに移動

- どのファイルを作成/変更するかを明確にする
- 各ファイルの役割と対応するテストを明記
- 凡例で「新規」「既存修正」「既存維持」を区別

### 実装詳細セクションについて

**目的**: 各ファイルの実装方針を簡潔に記載

- コード例は記載しない
- 処理フローの概要や設計判断のポイントを記載
- 詳細は実装ファイル自体を参照

### 実装時の注意事項セクションについて

**目的**: 実装中に把握した技術的な注意点を記録

- 認証・セッションの制約
- エラーハンドリングの方針
- 外部サービスとの連携方法

**注意**: コード例は記載しない。コードの詳細は実装ファイル自体を参照。

### 既知の制限事項セクションについて

**目的**: 現時点での制限や、スコープ外の項目を明記

- REQUIREMENTS.mdの「Out of Scope」と重複する場合は、REQUIREMENTS.mdを参照する形でも可
- セッション中に発見された新たな制限は、ここに記録後、必要に応じてREQUIREMENTS.mdに反映
