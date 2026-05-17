# STDD違反例と対策ガイド

このドキュメントでは、実際に発生したSTDD違反例を記録し、同じミスを繰り返さないための教訓を共有します。

## 実装開始前の必須チェックリスト

**⚠️ 重要**: 以下のチェックリストをすべて✅にするまで、**絶対に実装コードを書いてはいけません**。

```
□ 1. 対応するREQUIREMENTS.mdを読んだ
□ 2. 対応するTECH_DESIGN.mdを読んだ
□ 3. TECH_DESIGN.mdの「Test Strategy」セクションを確認した
□ 4. TECH_DESIGN.mdに記載されたテスト総数を確認した（例: 合計33件）
□ 5. Unit/Integration/E2Eのテスト内訳を理解した（例: Unit 18件, Integration 9件, E2E 6件）
□ 6. テスト作成タスクをTodoWriteに追加した
□ 7. テストファイルを作成した（Red状態）
□ 8. テストファイルをコミットした
```

**このチェックリストを完了するまで、Server Actions、UI Components、Pages等の実装コードは一切書かないこと。**

---

## 違反例1: テスト作成をスキップして実装開始

**発生日**: 2026-01-04
**機能**: パスワード再設定機能（user_app）

### ❌ 何が間違っていたか

```
1. REQUIREMENTS.md + TECH_DESIGN.md 作成 ✅
2. Tasks分解 ✅
3. Server Actions実装開始 ❌ ← ここが間違い！テストを飛ばした
4. UI実装 ❌
5. テスト作成（後から） ❌ ← 実装後にテストを書いてしまった
```

### ✅ 正しい手順

```
1. REQUIREMENTS.md + TECH_DESIGN.md 作成 ✅
2. Tasks分解 ✅
3. Unit テスト作成（18件） ✅ ← 実装前に必須！
4. Integration テスト作成（9件） ✅
5. E2E テスト作成（6件） ✅
6. テストコミット ✅
7. 実装 + テスト更新（Red → Green） ✅
8. テスト実行・通過確認 ✅
```

### 教訓

- テストを先に書くことで、仕様の理解漏れを防ぎ、Red-Green-Refactorサイクルを回せる
- TECH_DESIGN.mdには必ずテスト総数が記載されているので、実装前に確認すること
- TodoWriteでタスクを作成する際、テスト作成を最優先タスクとして明記すること

### 再発防止策

- 実装タスクを開始する前に、必ず「実装開始前の必須チェックリスト」を確認する
- チェックリストの項目7「テストファイルを作成した」が✅になるまで、実装コードを書かない

---

## 違反例2: TECH_DESIGN.mdのテスト総数を確認せずに実装

### ❌ 悪い例

```
TECH_DESIGN.mdに「合計33件（Unit: 18件, Integration: 9件, E2E: 6件）」と明記されているのに、
テスト総数を確認せずに実装を開始してしまう
```

### ✅ 正しい手順

```
1. TECH_DESIGN.mdの「Test Strategy」セクションを開く
2. テスト総数を確認: 「合計33件」
3. 内訳を確認: Unit 18件, Integration 9件, E2E 6件
4. TodoWriteに33件分のタスクを作成
5. 33件すべてのテストファイルを作成してからコミット
6. この時点で初めて実装を開始
```

### 教訓

TECH_DESIGN.mdには必ずテスト総数が記載されているので、実装前に必ず確認すること

---

## 違反例3: TECH_DESIGN.mdを見ずにE2Eテストを作成

### ❌ 悪い例

```typescript
// TECH_DESIGN.mdには「利用規約のE2Eテストは不要」と書いてあるのに作成してしまう
test('利用規約リンクが別タブで開く', async ({ page }) => {
  // このテストはTECH_DESIGN.mdに記載がない = 不要
});
```

### ✅ 正しい手順

```
1. タスク受領: "ログイン機能のE2Eテストを作成して"
2. ドキュメント確認:
   - docs/user_app/login/REQUIREMENTS.md を読む
   - docs/user_app/login/TECH_DESIGN.md を読む
   - TECH_DESIGN.mdの「Journey別テスト戦略」セクションを確認
3. 実装:
   - TECH_DESIGN.mdに記載されたテストケースのみを実装
   - TECH_DESIGN.mdに記載されていないテストは作成しない
```

---

## TodoWriteでのタスク分解の正しい順序

```typescript
// ❌ 悪い例（実装を優先してしまう）
[
  { content: "Server Actions実装", status: "in_progress" },
  { content: "UI実装", status: "pending" },
  { content: "テスト作成", status: "pending" }, // 後回しは禁止！
]

// ✅ 良い例（テスト作成を最優先）
[
  { content: "Unit テスト作成（18件）", status: "in_progress" }, // 最優先
  { content: "Integration テスト作成（9件）", status: "pending" },
  { content: "E2E テスト作成（6件）", status: "pending" },
  { content: "テストをコミット", status: "pending" },
  // ↓ テスト完了後に実装を開始
  { content: "実装 + テスト更新（Green状態へ）", status: "pending" },
  { content: "テスト実行・通過確認", status: "pending" },
]
```

---

## 実装・テスト修正時のSpecドキュメント更新ルール

**絶対に守るべき原則**: テストや実装を修正した場合は、**必ず対応するREQUIREMENTS.mdとTECH_DESIGN.mdも更新の必要がないか確認し、適宜更新すること**。

⚠️ **更新時もSSOT原則を厳守する**。Specには「現在の最新仕様」だけを書き、変更前後の比較・変更理由・「今回の追加」は一切書かない。履歴はgit log・PR・issueに任せる。詳細は[SKILL.md「絶対ルール: SSOT原則」](../SKILL.md)を参照。

### テスト修正時の更新ルール

1. **テストケースを追加した場合**
   - TECH_DESIGN.mdの該当セクション（E2E/Integration/Unit）にテストケースを追加
   - テスト総数を更新（「テストカバレッジサマリー」セクション）

2. **テストケースを削除した場合**
   - TECH_DESIGN.mdから該当テストケースを除去
   - テスト総数を更新
   - **削除理由・「削除した」旨の注記は書かない**（履歴はgit logが保持する）
   - ただし、現在の仕様として「このケースはUnitテストでカバーする」など読者が必要とする情報があれば、現在仕様の説明として記述してよい

3. **テストの実装方法を変更した場合**
   - TECH_DESIGN.mdの「実装方法」セクションを**現在の方式のみ**に書き換える
   - **「変更前」「変更後」「変更理由」のラベルや比較表現を使わない**

### 実装修正時の更新ルール

1. **実装方法を変更した場合**
   - TECH_DESIGN.mdの該当する「Decision」「Technical Implementation」セクションを**現在の方式のみ**に書き換える
   - 「現在この方式を採用している理由」は書いてよい（設計根拠）。「以前の方式から変更した理由」は書かない（履歴）

2. **UIを変更した場合**
   - REQUIREMENTS.mdのUser Journey、画面仕様を**現在のUIのみ**を反映する形で書き換える
   - TECH_DESIGN.mdの画面設計セクションを書き換える
   - **E2Eテスト、Integrationテストの両方を確認・更新**

### 更新チェックリスト

```
□ 1. TECH_DESIGN.mdのテストケース一覧を確認・更新
□ 2. TECH_DESIGN.mdのテスト総数を確認・更新
□ 3. TECH_DESIGN.mdの実装方法・技術的詳細を「現在の仕様のみ」に更新
□ 4. SSOT原則違反の禁止語（変更前/変更後/今回/既存/...）が含まれていないかgrep
□ 5. REQUIREMENTS.mdのUser Journey、画面仕様を確認
□ 6. E2Eテストが実装と整合しているか確認・更新
□ 7. Integrationテストが実装と整合しているか確認・更新
```

**重要**: UI変更を行った場合は、E2EテストとIntegrationテストの**両方**を必ず確認すること。

---

## 具体例

### 例1: テストケースを除去した場合

✅ **良い例**（現在の仕様のみ記述）:

```markdown
**SignupForm（`user_app/components/auth/SignupForm.test.tsx`）**:

1. メール検証リンク送信（正常系）
2. Googleアカウントで新規登録（正常系）
3. メールアドレス重複エラー（異常系）
4. 空のメールアドレスのバリデーションエラー
5. ネットワークエラー/サーバーエラー

**メール形式バリデーションについて**: `type="email"`のHTML5バリデーションが先に実行されるため、
React Hook Form側ではテストせず、`signupSchema`のUnitテストでカバーする。

**テスト総数**: 36件（E2E: 5件、Integration: 9件、Unit: 31件）
```

❌ **悪い例**（履歴・削除理由を書いている）:

```markdown
~~6. 無効なメール形式のバリデーション~~ ← 削除
**削除理由**: HTML5バリデーションが先に動くためテストできない
```

### 例2: 実装方法を変更した場合

✅ **良い例**（現在の方式のみ記述）:

```markdown
### メール送信実装

`admin.generateLink()` でリンクを生成し、Resend経由でHTMLメールを送信する。
HTMLテンプレートのカスタマイズ性を確保するため、Supabase Authの組み込みメール送信は使わない。
```

❌ **悪い例**（変更前後を比較している）:

```markdown
### メール送信実装

**変更前**: `supabase.auth.signUp()`でSupabase Auth経由でメール送信
**変更後**: `admin.generateLink()` + Resend経由でHTMLメール送信
**変更理由**: テンプレートのカスタマイズ性
```
