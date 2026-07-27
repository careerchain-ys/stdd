---
name: reverse-engineering-feature-spec
description: |-
  既存の機能/ページの実装から feature 階層の Spec ドキュメント（REQUIREMENTS.md + TECH_DESIGN.md + TEST_PLAN.md）とテスト（E2E / Unit / Integration）をリバースエンジニアリングで作成するためのガイドライン。新規機能の仕様策定ではなく、既に動いている機能を正確にドキュメント化・テスト化する場合に使う。プロジェクト全体（common 階層）のリバースには reverse-engineering-common-spec を使用する。
when_to_use: |-
  「リバースエンジニアリング」「既存コードからspec」「既存機能のドキュメント化」「機能のドキュメント化」「実装からテスト作成」「specカバー率向上」に関する作業のとき。
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# feature spec のリバースエンジニアリング

既に動いている **機能 / ページ単位**の実装コードを精読し、その挙動を正確に反映した feature 階層の Spec ドキュメント（REQUIREMENTS.md + TECH_DESIGN.md + TEST_PLAN.md）とテスト（E2E / Unit / Integration）を作成する。

> **前提（推奨）**: プロジェクト全体の **common 階層**（`docs/common/REQUIREMENTS.md` + `ARCHITECTURE.md` + `TABLE_DEFINITION.md` + `API_SPEC.md`）が未作成なら、先に `reverse-engineering-common-spec` スキルで作成しておくと、レイヤ規約・共有ドメインモデル・テーブル定義・API 契約を踏まえられて精度が上がる。既にある場合は本スキルから始める。データモデル・API は common 階層が SSoT のため、feature 側では common の `TABLE_DEFINITION.md` / `API_SPEC.md` を参照する。

## 最重要原則

### Specに記載する文言は正確に実装を反映すること

リバースエンジニアリングでは、**実装が真実（Source of Truth）**である。Specは実装の挙動を忠実にドキュメント化したものであり、理想論や推測で書いてはならない。

```
❌ 悪い例: 実装を確認せずに一般的な仕様を書く
  - 「電話番号は10〜11桁の数字」 ← バリデーション定義（例: Zod スキーマ）を確認していない
  - 「戻るボタンで前のステップに戻る」 ← 実際のボタンラベルは「前へ」

✅ 良い例: 実装を確認してから書く
  - 「電話番号は10文字以上（数字とハイフンのみ許可）」 ← バリデーション定義（例: Zod スキーマ）を確認
  - 「「前へ」ボタンで前のステップに戻る」 ← ビューのボタンテキストを確認
```

**具体的な確認項目**（「確認元」は**ソースの種別**。括弧内は代表スタックでの一例なので、採用スタックに読み替えること）:

| 項目 | 確認元（ソースの種別） | よくある間違い |
|------|--------|--------------|
| ボタンラベル | ビュー/テンプレート内のテキスト（例: JSX） | 「送信」と書いたが実際は「保存」 |
| バリデーションルール | バリデーション定義（例: Zod スキーマ `schema.ts`） | 桁数・形式を想像で書く |
| エラーメッセージ | バリデーション定義のメッセージ（例: Zod の message） | 一般的なメッセージを推測で書く |
| フォーム項目名 | ラベル要素（例: `<label>` / `getByLabel` / `aria-label`） | 項目名を想像で書く |
| ページ遷移先 | ルーティング/リダイレクト（例: `router.push()` / `redirect()`） | パスを想像で書く |
| API呼び出し | ハンドラ/通信層（例: Server Actions / fetch） | エンドポイントを想像で書く |
| DB操作 | データアクセス層のメソッド（例: repository 層） | テーブル名・カラム名を想像で書く |
| 型定義 | ドメインモデルの型（例: `domain/models` 配下） | フィールド名を想像で書く |

詳細: [正確性ガイド](guides/accuracy.md)

---

## Quick Start

### 前提条件

- 対象機能が既に動いている実装コードがある
- 対応するSpecドキュメント（REQUIREMENTS.md / TECH_DESIGN.md / TEST_PLAN.md）が存在しない、または不十分

### 作業フロー

```
1. 実装コードリーディング（精読）
   ↓
2. REQUIREMENTS.md作成（ユーザー視点の挙動を記述）
   ↓
3. Playwright MCPでUIキャプチャ → Figmaファイル作成
   ↓
4. TECH_DESIGN.md作成（ロジック設計中心の技術設計。データモデル/APIは common 参照）
   ↓
4.5 TEST_PLAN.md作成（テスト戦略）
   ↓
5. E2Eテスト作成
   ↓
6. Unit / Integrationテスト作成（必要に応じて）
   ↓
7. /verifying-consistency で整合性チェック
   ↓
8. 不整合の修正（Specを実装に合わせる）
```

---

## Phase 1: 実装コードリーディング

### 読む順序

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

> 上記のファイルパスは代表スタック（例: Next.js / Supabase）での一例。採用スタックの配置に読み替えること。

---

## Phase 2: REQUIREMENTS.md作成

`documenting-requirements` skillのテンプレートに従って作成する。

### リバースエンジニアリング固有のルール

**1. ユースケース（振る舞い＋受入基準）は実装の挙動から抽出する**

実装コードの条件分岐・状態遷移を元に、ユーザーが辿るパスを網羅的に洗い出す。主要フローは振る舞い（番号付き手順・主語明示）に、例外・境界・分岐は受入基準（EARS）に落とす。

```
# コードの条件分岐 → ユースケースの振る舞い / 受入基準
if (form.isValid) → 正常系の振る舞い（手順）
if (error.type === 'validation') → 受入基準（IF：バリデーションエラー時）
if (error.type === 'network') → 受入基準（IF：ネットワークエラー時）
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
## 5. 備考

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

## Phase 4: TECH_DESIGN.md作成

`documenting-tech-specs` skillのテンプレートに従って作成する。章構成は **1.概要 / 2.主要な設計判断(任意) / 3.画面項目定義(画面 feature のみ必須) / 4.ロジック設計(コア) / 5.エラーハンドリング戦略 / 6.非機能要件(任意)**。

> **データモデル / API は common 階層が SSoT**。TECH_DESIGN にはデータモデルや ER 図、API 設計を持たず、common の `TABLE_DEFINITION.md` / `API_SPEC.md` を**参照**する。TECH_DESIGN のコアはロジック設計。テスト戦略は別ファイル `TEST_PLAN.md`（Phase 4.5）。

### リバースエンジニアリング固有のルール

**1. 型定義は実装から正確にコピーする**

ドメインモデルの型（例: domain/models 配下の Entity 型）やスキーマの型をそのまま記載する。推測で型を書かない。テーブル定義そのものは common の `TABLE_DEFINITION.md` を参照する。

```typescript
// 例: TypeScript での一例
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

**2. バリデーションルールはバリデーション定義（例: Zod スキーマ）から正確に転記する**

```typescript
// 例: Zod スキーマ（schema.ts）での一例
// schema.ts の実際のコード
const phoneSchema = z.string()
  .min(10, { message: '電話番号は10文字以上で入力してください' })
  .regex(/^[0-9-]+$/, { message: '数字とハイフンのみ入力可能です' });

// ✅ TECH_DESIGN.md に書く内容
// - `phone`: 10文字以上、数字とハイフンのみ許可
//   - エラー: 「電話番号は10文字以上で入力してください」「数字とハイフンのみ入力可能です」
```

**3. ロジック設計は実装のフローを正確に反映する**

入力 → バリデーション → ビジネスロジック → 永続化 → 出力 の流れを、実装のハンドラ/ビジネスロジック層（例: Server Actions / service 層）から正確に書き起こす。データモデル（テーブル・ER）は common の `TABLE_DEFINITION.md`、API 契約は common の `API_SPEC.md` を参照し、TECH_DESIGN では重複して持たない。

**4. データモデル / API への言及は common を参照する**

```
❌ TECH_DESIGN にテーブル定義・ER 図・API 設計を書く（common と二重管理になる）
✅ common の TABLE_DEFINITION.md / API_SPEC.md を参照し、生成された DB 型定義（例: Supabase の supabase/generated/database.types.ts）と一致させる
```

---

## Phase 4.5: TEST_PLAN.md作成

テスト戦略は feature 単位の `TEST_PLAN.md` に記述する（TECH_DESIGN には書かない）。`documenting-tech-specs` skillのテンプレートに従う。

**テスト総数は作成後に正確にカウントする**

TEST_PLAN.mdにはテスト総数を記載するが、テストを実際に書いた後にitブロック数を正確にカウントして更新する。

```
# 例: Jest でのカウント方法（テストフレームワークに合わせて読み替える）
grep -c "it(" path/to/test.test.tsx

# 例: Playwright でのカウント方法
grep -c "test(" e2e/tests/user-app/feature.spec.ts
```

---

## Phase 5: テスト作成

### E2Eテスト

`e2e-testing` skillに従い、TEST_PLAN.mdのテスト戦略に基づいて作成する。

**リバースエンジニアリング固有のポイント**:

1. **実際の画面を操作して動作確認してからテストを書く**
   - テストデータ（seedデータ）がどのユーザー・どの状態で入っているか確認
   - 実際のUI操作で画面遷移・表示を確認

2. **Locatorは実装のビュー/テンプレート（例: JSX）から正確に取得する**
   ```typescript
   // 例: JSX + Playwright での一例
   // 実装を確認
   <button aria-label="保存">保存して次へ</button>

   // ✅ テストのLocator
   await page.getByRole('button', { name: '保存して次へ' });
   ```

3. **テストデータはseedファイルから確認する**
   ```
   # 例: Supabase の seed での一例
   supabase/seeds/*.sql
   ```

### Unit / Integrationテスト

TEST_PLAN.mdのテスト戦略で定めたテストレベルに従って作成する。

---

## Phase 6: 整合性チェック

### `/verifying-consistency` の実行

すべてのドキュメント・テスト作成後、`/verifying-consistency` コマンドで整合性を確認する。

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
| **C: 複雑時はサブ分割** | ユースケース 7つ以上 or 実装1000行超で分割 | ダッシュボード（タブ別） |
| **D: 機能追加は独立Spec可** | 既存画面への追加機能は独立Specとして配置可 | 評価ボタン追加 |

**⚠️ 作業開始前の確認**: 上記方針を踏まえたうえで、必ず開発者にSpec粒度（どの画面・機能を1 Specにまとめるか）とスコープ（どこまでを対象とするか）を確認してから作業を開始すること。

---

## チェックリスト

### コードリーディング完了時

```
□ ページ/画面コンポーネントを読んだ
□ クライアント/UI コンポーネントを読んだ
□ バリデーション定義（例: Zod スキーマ）を読んだ
□ ハンドラ/ビジネスロジック層（例: Server Actions）を読んだ
□ ドメイン層（例: models, repository, service）を読んだ
□ 生成された DB 型定義（例: Supabase の database.types.ts）で関連テーブルを確認した
□ seedデータを確認した
```

### REQUIREMENTS.md作成時

```
□ ボタンラベル・リンクテキストは実装のビュー/テンプレート（例: JSX）から転記した
□ フォーム項目名は実装のラベル要素（例: <label> / aria-label）から転記した
□ エラーメッセージはバリデーション定義のメッセージ（例: Zod の message）から転記した
□ 画面遷移はルーティング/リダイレクト（例: router.push / redirect）の実際のパスを記載した
□ すべてのユースケースにPriority（P0/P1/P2）＋振る舞い（手順）＋受入基準（EARS）を付与した
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
□ 型定義はドメインモデル（例: domain/models 配下）から正確にコピーした
□ バリデーションルールはバリデーション定義（例: Zod スキーマ schema.ts）から正確に転記した
□ ロジック設計（入力→検証→ロジック→永続化→出力）を実装から書き起こした
□ データモデル/ER/API は common の TABLE_DEFINITION.md / API_SPEC.md を参照（TECH_DESIGN に重複して持っていない）
□ 画面 feature の場合、画面項目定義セクションを記載した
□ 実装例・コード例が含まれていないことを確認した（型定義・I/Fは除く）
```

### TEST_PLAN.md作成時

```
□ テスト戦略を記載した（ユースケース別テストマッピング）
□ テスト総数と内訳を記載した
```

### テスト作成時

```
□ E2EテストのLocatorは実装のビュー/テンプレート（例: JSX）のテキストから取得した
□ テストデータはseedファイルの内容を確認した
□ TEST_PLAN.mdのテスト戦略に記載されたテストケースを網羅した
□ テスト実行して全件パスした
□ TEST_PLAN.mdのテスト総数を実際のitブロック数で更新した
```

### 最終確認

```
□ /verifying-consistency を実行した
□ 検出された不整合をすべて修正した（Specを実装に合わせる方向で）
□ TypeScript型チェック（`.stdd.config.yml` の `commands.typecheck`）がクリーン
```

---

## When NOT to Use This Skill

以下の場合はこのスキルを使用しない:

- **プロジェクト全体 / common 階層のリバース**（STDD 導入時の `docs/common/` 作成）: `reverse-engineering-common-spec` skillを使用
- **新規機能の仕様策定**: `documenting-requirements`（要件）／ `documenting-tech-specs`（技術設計）skillを使用
- **実装タスクの計画**: `documenting-plans` skillを使用
- **E2Eテストのみの作成**（Specドキュメントが既に存在する場合）: `e2e-testing` skillを使用
- **バグ修正**: リバースエンジニアリングではなく直接修正

---

## 参照ファイル

- **共通spec（common階層）リバース**: [reverse-engineering-common-spec skill](../reverse-engineering-common-spec/SKILL.md)
- **要件テンプレート**: [documenting-requirements skill](../documenting-requirements/SKILL.md)
- **技術設計・テストテンプレート**: [documenting-tech-specs skill](../documenting-tech-specs/SKILL.md)
- **E2Eテストガイド**: [e2e-testing skill](../../../plugins/playwright/skills/e2e-testing/SKILL.md)（`playwright` プラグイン）
- **PLANドキュメント**: [documenting-plans skill](../documenting-plans/SKILL.md)
- **STDD違反例**: [stdd-violations guide](../documenting-requirements/guides/stdd-violations.md)
- **正確性ガイド**: [accuracy guide](guides/accuracy.md)
- **Figmaキャプチャガイド**: [figma-capture guide](guides/figma-capture.md)
- **DB型定義**: 生成された DB 型定義（例: Supabase の `supabase/generated/database.types.ts`）
