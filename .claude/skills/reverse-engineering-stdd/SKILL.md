---
name: reverse-engineering-stdd
description: |-
  既存実装からSpecドキュメント（REQUIREMENTS.md + TECH_DESIGN.md）とE2Eテストをリバースエンジニアリングで作成するためのガイドライン。新規機能の仕様策定ではなく、既に動いている実装を正確にドキュメント化・テスト化する場合に使用。「リバースエンジニアリング」「既存コードからspec」「既存機能のドキュメント化」「実装からテスト作成」「specカバー率向上」に関する作業で使用。
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# リバースエンジニアリングSTDDスキル

既に動いている実装コードを精読し、その挙動を正確に反映したSpecドキュメント（REQUIREMENTS.md + TECH_DESIGN.md）とテスト（E2E / Unit / Integration）を作成する。

## 最重要原則

### Specに記載する文言は正確に実装を反映すること

リバースエンジニアリングでは、**実装が真実（Source of Truth）**である。Specは実装の挙動を忠実にドキュメント化したものであり、理想論や推測で書いてはならない。

```
❌ 悪い例: 実装を確認せずに一般的な仕様を書く
  - 「電話番号は10〜11桁の数字」 ← Zodスキーマを確認していない
  - 「戻るボタンで前のステップに戻る」 ← 実際のボタンラベルは「前へ」

✅ 良い例: 実装を確認してから書く
  - 「電話番号は10文字以上（数字とハイフンのみ許可）」 ← schema.tsのZodルールを確認
  - 「「前へ」ボタンで前のステップに戻る」 ← JSXのボタンテキストを確認
```

**具体的な確認項目**:

| 項目 | 確認元 | よくある間違い |
|------|--------|--------------|
| ボタンラベル | JSX内のテキスト | 「送信」と書いたが実際は「保存」 |
| バリデーションルール | Zodスキーマ（schema.ts） | 桁数・形式を想像で書く |
| エラーメッセージ | Zodのmessageプロパティ | 一般的なメッセージを推測で書く |
| フォーム項目名 | `<label>` / `getByLabel` / `aria-label` | 項目名を想像で書く |
| ページ遷移先 | `router.push()` / `redirect()` | パスを想像で書く |
| API呼び出し | Server Actions / fetch | エンドポイントを想像で書く |
| DB操作 | repository層のメソッド | テーブル名・カラム名を想像で書く |
| 型定義 | domain/models配下の型 | フィールド名を想像で書く |

詳細: [正確性ガイド](guides/accuracy.md)

---

## 対象の 2 ティア（common / feature）

リバースエンジニアリングには、リバースする高度が 2 つある。どちらも「実装が真実」という原則は共通で、**読む対象だけが違う**。

| モード             | 出力                                                                | 主に読む対象                                                                 |
| ------------------ | ------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| **共通spec (Phase 0)** | `docs/common/REQUIREMENTS.md` + `docs/common/ARCHITECTURE.md`       | リポジトリ構成・workspaces・DB 型定義・CI/CD・レイヤ規約・外部サービス連携    |
| **feature spec (Phase 1〜)** | `docs/<app>/<feature>/REQUIREMENTS.md` + `TECH_DESIGN.md`           | ページ・Client・schema・Server Action・domain (単一機能のコード)             |

**順序**: 既存プロジェクト導入時は **共通spec (Phase 0) を先に作る**。プロジェクト全体のレイヤ規約・共有ドメインモデル・テーブル一覧が common ティアに揃っていると、各 feature のリバース精度が上がる。共通spec が既にある場合は Phase 0 をスキップして Phase 1 から始める。

`docs/common/` のテンプレートは `packages/core/templates/common/REQUIREMENTS.md` / `ARCHITECTURE.md` を参照。

---

## Phase 0: プロジェクト全体（共通spec）のリバース

コードベース全体を input に、サービス全体の俯瞰 spec を 2 ファイルで作成する。

### 読む順序とチェックリスト

`ARCHITECTURE.md` の目次がそのまま読む順序になる。

**1. システム構成**（`REQUIREMENTS.md` のサービス概要・アクターもここで把握）
```
□ README / トップレベルディレクトリ構成 → サービスの目的・アプリ構成
□ デプロイ設定 (vercel.json / Dockerfile / .github/workflows) → 環境とブランチ戦略
□ 環境変数・SDK の import → 外部サービス連携 (認証 / DB / ストレージ / メール / 監視 等)
```

**2. リポジトリ構成**
```
□ package.json の workspaces / モジュール分割
□ 依存管理ルール (どの依存がどこに置かれているか、アプリ間 import 制限の有無)
□ 共有パッケージ (packages/shared 等) の責務
```

**3. レイヤードアーキテクチャ**
```
□ domain/ 配下の構成 (models / repository / service / ports)
□ 依存方向ルール (UI → Service → Repository → DB 等)、禁止依存
□ 代表的なデータフロー 1 本 (Server Action / API → Service → Repository)
```

**4. データモデル・DB設計**
```
□ 生成された DB 型定義 (database.types.ts 等) を正としてテーブルを列挙
□ ドメイングループへの分類、中心テーブルごとの ER 図
□ 設計方針 (論理削除 / 主キー / 時系列カラム / マイグレーション規約)
```

### 確信が持てない箇所は要確認マーカーを残す

実装からの読み取りに確信が持てない箇所は `<!-- 要確認: ... -->` のインラインコメントで明示する。
これは**一時的な注記**であり、人間レビューで確定したら除去する（恒久的に残さない）。SSoT 原則上、確定済みの spec に作成プロセスや未確定メモを残してはならない。

```markdown
- **NFT / ウォレット**: wallets / nft_management テーブルが存在する。<!-- 要確認: 外部ウォレット連携の現行稼働範囲 -->
```

### Phase 0 完了条件

```
□ docs/common/REQUIREMENTS.md を作成（サービス概要 / アクター / アプリ構成）
□ docs/common/ARCHITECTURE.md を作成（システム構成 / リポジトリ / レイヤ / データモデル）
□ テーブル一覧は生成された型定義ファイルと一致している
□ 要確認マーカーは「人間に確認すべき項目」としてレビュー依頼にまとめた
```

---

## Quick Start

### 前提条件

- 対象機能が既に動いている実装コードがある
- 対応するSpecドキュメント（REQUIREMENTS.md / TECH_DESIGN.md）が存在しない、または不十分

### 作業フロー

```
1. 実装コードリーディング（精読）
   ↓
2. REQUIREMENTS.md作成（ユーザー視点の挙動を記述）
   ↓
3. Playwright MCPでUIキャプチャ → Figmaファイル作成
   ↓
4. TECH_DESIGN.md作成（技術設計 + テスト戦略）
   ↓
5. E2Eテスト作成
   ↓
6. Unit / Integrationテスト作成（必要に応じて）
   ↓
7. /verify-consistency で整合性チェック
   ↓
8. 不整合の修正（Specを実装に合わせる）
```

---

## Phase 1: 実装コードリーディング

### 読む順序

以下の順序で実装を精読し、機能の全体像を把握する。

**1. ページコンポーネント**（エントリーポイント）
```
<app>/app/<path>/page.tsx
```
- サーバーコンポーネント or クライアントコンポーネントの判定
- データ取得方法（Server Component直接 / Server Actions）
- レイアウト構成

**2. クライアントコンポーネント**（UIとインタラクション）
```
<app>/app/<path>/*Client.tsx
<app>/components/<name>.tsx
```
- フォーム項目、ボタンラベル、表示テキストを**正確に**読み取る
- 状態管理（useState, useForm）
- 条件分岐によるUI出し分け

**3. バリデーションスキーマ**（入力ルール）
```
<app>/app/<path>/schema.ts
<app>/lib/schemas/<name>.ts
```
- Zodスキーマの各フィールドのルールを**正確に**読み取る
  - `min()`, `max()`, `regex()`, `refine()` の具体値
  - `message` プロパティのエラーメッセージ文言
  - `optional()`, `nullable()` の有無

**4. Server Actions**（ビジネスロジック）
```
<app>/app/<path>/actions.ts
<app>/actions/<name>.ts
```
- 入力→処理→出力のフロー
- エラーハンドリング

**5. Domain層**（データモデルとDB操作）
```
<app>/domain/models/<name>.ts
<app>/domain/repository/<name>.ts
<app>/domain/service/<name>.ts
```
- Entity型定義
- CRUD操作の実装
- ビジネスルール

**6. DBスキーマ**（テーブル定義）
```
supabase/generated/database.types.ts
```
- テーブル名、カラム名を**正確に**確認
- リレーション

### コードリーディング時のメモ取り

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

---

## Phase 2: REQUIREMENTS.md作成

`documenting-specifications` skillのテンプレートに従って作成する。

### リバースエンジニアリング固有のルール

**1. ユーザージャーニーは実装の挙動から抽出する**

実装コードの条件分岐・状態遷移を元に、ユーザーが辿るパスを網羅的に洗い出す。

```
# コードの条件分岐 → User Journey
if (form.isValid) → 正常系ジャーニー
if (error.type === 'validation') → バリデーションエラージャーニー
if (error.type === 'network') → ネットワークエラージャーニー
```

**2. UIテキストは実装から正確に転記する**

```typescript
// 実装コード
<Button>保存して次へ</Button>

// ❌ REQUIREMENTS.md に書いてはいけない
「次へ」ボタンをクリック

// ✅ REQUIREMENTS.md に書くべき内容
「保存して次へ」ボタンをクリック
```

**3. Priority判定の基準**

リバースエンジニアリングの場合、以下の基準でPriorityを判断する:

| Priority | 判断基準 |
|----------|---------|
| P0 | 主要な正常系フロー、ビジネスの中核機能 |
| P1 | 重要なエラーハンドリング、バリデーション |
| P2 | エッジケース、低頻度の操作 |

**4. 「備考」セクションにリバースエンジニアリングの注記を追加**

```markdown
## 7. 備考

このドキュメントは既存実装からリバースエンジニアリングで作成されました。

**確認が必要な項目**:
- [ ] ビジネス目標がビジネス要件と合致しているか
- [ ] Priority判断がビジネス優先度と合っているか
```

---

## Phase 3: UIキャプチャ → Figmaファイル作成

REQUIREMENTS.md作成後、Playwright MCPを使って実装済みUIのスクリーンショットを取得し、Figmaデザインファイルとして整理する。

### 作業手順

1. **キャプチャ計画作成**: コードリーディング結果を元に、キャプチャすべき画面と状態を一覧化
2. **Playwright MCPで操作・キャプチャ**: テストユーザーでログイン → 各画面を操作 → スクリーンショット取得 → ログアウト
3. **Figmaファイル作成**: スクリーンショットをFigmaに取り込み、フレームとして整理
4. **REQUIREMENTS.md更新**: 「UI/UXデザイン」セクションにFigmaファイルのnode-id付きリンクを記載

### キャプチャすべき画面状態

| カテゴリ | 状態例 |
|---------|--------|
| 初期状態 | データなし（空）、ローディング中 |
| データあり | 1件表示、複数件表示 |
| フォーム | 未入力、入力済み、バリデーションエラー |
| モーダル | 開いた状態（新規追加/編集） |
| 操作結果 | 成功トースト、削除確認ダイアログ |
| レスポンシブ | デスクトップ（1280px）、モバイル（375px） |

### REQUIREMENTS.mdへの記載フォーマット

既存のSpec（例: `docs/<app.id>/<feature_path>/REQUIREMENTS.md`、`.stdd.config.yml` の `docs.layout.requirements` テンプレートに従う）の「Figmaデザイン」セクションを参考にする:

```markdown
### Figmaデザイン

**Figmaファイル**: [ファイル名](FigmaファイルURL)

#### [画面名1]

- [状態A](FigmaファイルURL?node-id=X-Y)
- [状態B](FigmaファイルURL?node-id=X-Y)
```

詳細: [Figmaキャプチャガイド](guides/figma-capture.md)

---

## Phase 4: TECH_DESIGN.md作成（旧Phase 3）

`documenting-specifications` skillのテンプレートに従って作成する。

### リバースエンジニアリング固有のルール

**1. 型定義は実装から正確にコピーする**

domain/models配下のEntity型、スキーマの型をそのまま記載する。推測で型を書かない。

```typescript
// ❌ 想像で書いた型
interface UserProfile {
  name: string;        // ← 実際は first_name + last_name
  phone: string;       // ← 実際は phone: string（nullable）
}

// ✅ 実装から正確にコピーした型
// <app.path>/domain/models/user.ts から転記（app.path は .stdd.config.yml の apps[].path）
interface UserEntity {
  first_name: string | null;
  last_name: string | null;
  phone: string;
}
```

**2. バリデーションルールはZodスキーマから正確に転記する**

```typescript
// schema.ts の実際のコード
const phoneSchema = z.string()
  .min(10, { message: '電話番号は10文字以上で入力してください' })
  .regex(/^[0-9-]+$/, { message: '数字とハイフンのみ入力可能です' });

// ✅ TECH_DESIGN.md に書く内容
// - `phone`: 10文字以上、数字とハイフンのみ許可
//   - エラー: 「電話番号は10文字以上で入力してください」「数字とハイフンのみ入力可能です」
```

**3. テスト総数は作成後に正確にカウントする**

TECH_DESIGN.mdにはテスト総数を記載するが、テストを実際に書いた後にitブロック数を正確にカウントして更新する。

```
# カウント方法（Jest）
grep -c "it(" path/to/test.test.tsx

# カウント方法（Playwright）
grep -c "test(" e2e/tests/user-app/feature.spec.ts
```

**4. ER図はdatabase.types.tsを正確に反映する**

```
❌ テーブル名やカラム名を想像で書く
✅ supabase/generated/database.types.ts の定義を参照して書く
```

---

## Phase 5: テスト作成（旧Phase 4）

### E2Eテスト

`e2e-testing` skillに従い、TECH_DESIGN.mdのテスト戦略に基づいて作成する。

**リバースエンジニアリング固有のポイント**:

1. **実際の画面を操作して動作確認してからテストを書く**
   - テストデータ（seedデータ）がどのユーザー・どの状態で入っているか確認
   - 実際のUI操作で画面遷移・表示を確認

2. **Locatorは実装のJSXから正確に取得する**
   ```typescript
   // 実装を確認
   <button aria-label="保存">保存して次へ</button>

   // ✅ テストのLocator
   await page.getByRole('button', { name: '保存して次へ' });
   ```

3. **テストデータはseedファイルから確認する**
   ```
   supabase/seeds/*.sql
   ```

### Unit / Integrationテスト

TECH_DESIGN.mdのテスト戦略で定めたテストレベルに従って作成する。

---

## Phase 6: 整合性チェック（旧Phase 5）

### `/verify-consistency` の実行

すべてのドキュメント・テスト作成後、`/verify-consistency` コマンドで整合性を確認する。

### 不整合発見時の修正方針

リバースエンジニアリングの場合、**Specを実装に合わせる**のが原則。

```
❌ 実装をSpecに合わせて変更する（リバースエンジニアリングでは原則禁止）
✅ Specを実装の実際の挙動に合わせて修正する
```

**例外**: 実装に明らかなバグがある場合は、バグとして記録し別途修正する。

---

## Spec粒度の基本方針

| 原則 | ルール | 例 |
|------|--------|------|
| **A: 1フロー = 1 Spec** | 開始〜完了まで一連の操作は1 Spec | パスワードリセット、新規登録 |
| **B: 関連画面はまとめる** | 同一データの一覧+詳細等は1 Spec | 通知一覧+詳細 |
| **C: 複雑時はサブ分割** | User Journey 7つ以上 or 実装1000行超で分割 | ダッシュボード（タブ別） |
| **D: 機能追加は独立Spec可** | 既存画面への追加機能は独立Specとして配置可 | 評価ボタン追加 |

**⚠️ 作業開始前の確認**: 上記方針を踏まえたうえで、必ず開発者にSpec粒度（どの画面・機能を1 Specにまとめるか）とスコープ（どこまでを対象とするか）を確認してから作業を開始すること。

---

## チェックリスト

### コードリーディング完了時

```
□ ページコンポーネントを読んだ
□ クライアントコンポーネントを読んだ
□ バリデーションスキーマを読んだ
□ Server Actionsを読んだ
□ Domain層（models, repository, service）を読んだ
□ database.types.tsで関連テーブルを確認した
□ seedデータを確認した
```

### REQUIREMENTS.md作成時

```
□ ボタンラベル・リンクテキストは実装のJSXから転記した
□ フォーム項目名は実装の<label>やaria-labelから転記した
□ エラーメッセージはZodスキーマのmessageから転記した
□ 画面遷移はrouter.push/redirectの実際のパスを記載した
□ すべてのUser JourneyにPriority（P0/P1/P2）を付与した
□ 「備考」セクションにリバースエンジニアリング注記を追加した
```

### UIキャプチャ → Figma作成時

```
□ キャプチャ計画を作成した（全画面・全状態を洗い出し）
□ Playwright MCPでテストユーザーを使用してログインした
□ デスクトップ（1280px）・モバイル（375px）の両方をキャプチャした
□ データが表示されたことを確認してからキャプチャした
□ フォーム・モーダルの各状態（空/入力済み/エラー）を網羅した
□ 操作完了後にログアウトした
□ Figmaファイルを作成し、フレームとして整理した
□ REQUIREMENTS.mdの「UI/UXデザイン」セクションにnode-id付きリンクを記載した
□ スクリーンショットを削除した（gitにはコミットしない）
```

### TECH_DESIGN.md作成時

```
□ 型定義はdomain/models配下から正確にコピーした
□ バリデーションルールはschema.tsから正確に転記した
□ ER図はdatabase.types.tsを参照して作成した
□ テスト戦略を記載した（ジャーニー別テストマッピング）
□ テスト総数と内訳を記載した
□ 実装例・コード例が含まれていないことを確認した（型定義・I/Fは除く）
```

### テスト作成時

```
□ E2EテストのLocatorは実装のJSXテキストから取得した
□ テストデータはseedファイルの内容を確認した
□ TECH_DESIGN.mdのテスト戦略に記載されたテストケースを網羅した
□ テスト実行して全件パスした
□ TECH_DESIGN.mdのテスト総数を実際のitブロック数で更新した
```

### 最終確認

```
□ /verify-consistency を実行した
□ 検出された不整合をすべて修正した（Specを実装に合わせる方向で）
□ TypeScript型チェック（`.stdd.config.yml` の `commands.typecheck`）がクリーン
```

---

## When NOT to Use This Skill

以下の場合はこのスキルを使用しない:

- **新規機能の仕様策定**: `documenting-specifications` skillを使用
- **実装タスクの計画**: `documenting-plans` skillを使用
- **E2Eテストのみの作成**（Specドキュメントが既に存在する場合）: `e2e-testing` skillを使用
- **バグ修正**: リバースエンジニアリングではなく直接修正

---

## 参照ファイル

- **Specテンプレート**: [documenting-specifications skill](../documenting-specifications/SKILL.md)
- **E2Eテストガイド**: [e2e-testing skill](../../../plugins/playwright/skills/e2e-testing/SKILL.md)（`playwright` プラグイン）
- **PLANドキュメント**: [documenting-plans skill](../documenting-plans/SKILL.md)
- **STDD違反例**: [stdd-violations guide](../documenting-specifications/guides/stdd-violations.md)
- **正確性ガイド**: [accuracy guide](guides/accuracy.md)
- **Figmaキャプチャガイド**: [figma-capture guide](guides/figma-capture.md)
- **DB型定義**: `supabase/generated/database.types.ts`
