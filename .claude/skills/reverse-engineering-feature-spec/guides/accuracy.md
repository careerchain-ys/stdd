# 正確性ガイド - Specに記載する文言は正確に実装を反映すること

リバースエンジニアリングにおける最重要原則。既存実装からSpecを作成する場合、**推測や一般化で書かず、必ず実装コードを確認してから書く**こと。

---

## 原則

```
実装のコードが真実（Single Source of Truth）
Specはその真実を忠実にドキュメント化したもの
```

一般的なSTDDではSpecが先でSpec→テスト→実装の順序だが、リバースエンジニアリングでは実装が既にあるため、**実装→Spec→テスト**の順序で、実装に忠実なSpecを作る。

---

## カテゴリ別の確認ポイント

### 1. UIテキスト（ボタンラベル、見出し、プレースホルダー）

**確認元**: JSXのテキストノード、`aria-label`、`placeholder`

```typescript
// 実装コード例
<Button type="submit">保存して次へ</Button>
<h1>プロフィール登録</h1>
<Input placeholder="例: 090-1234-5678" />
```

| 書くべき内容 | 書いてはいけない内容 |
|------------|-------------------|
| 「保存して次へ」ボタン | 「次へ」ボタン |
| 「プロフィール登録」見出し | 「プロフィール入力」見出し |
| プレースホルダー「例: 090-1234-5678」 | プレースホルダー「電話番号」 |

### 2. バリデーションルール

**確認元**: Zodスキーマ（`schema.ts` / `lib/schemas/*.ts`）

```typescript
// 実装コード例
const schema = z.object({
  phone: z.string()
    .min(10, { message: '電話番号は10文字以上で入力してください' })
    .regex(/^[0-9-]+$/, { message: '数字とハイフンのみ入力可能です' }),
  email: z.string()
    .email({ message: '有効なメールアドレスを入力してください' }),
});
```

| 書くべき内容 | 書いてはいけない内容 |
|------------|-------------------|
| 10文字以上、数字とハイフンのみ | 10〜11桁の数字（ハイフン許可） |
| エラー: 「電話番号は10文字以上で入力してください」 | エラー: 「電話番号の形式が不正です」 |

**特に注意**: `min()` / `max()` の値、`regex()` のパターン、`message` の文言を正確に転記すること。

### 3. エラーメッセージ

**確認元**: Zodスキーマの`message`、Server Actionsの`return { error: '...' }`、toast/Snackbarの文言

```typescript
// Server Actions
if (!user) {
  return { error: 'ユーザーが見つかりません' };
}

// Snackbar
showSnackbar('プロフィールを更新しました', 'success');
```

| 書くべき内容 | 書いてはいけない内容 |
|------------|-------------------|
| 「ユーザーが見つかりません」 | 「ユーザーが存在しません」 |
| 「プロフィールを更新しました」 | 「保存しました」 |

### 4. 画面遷移・URL

**確認元**: `router.push()`, `redirect()`, `<Link href="...">`, `useRouter`

```typescript
// 実装コード例
router.push('/dashboard');
redirect('/onboarding?step=2');
```

| 書くべき内容 | 書いてはいけない内容 |
|------------|-------------------|
| `/dashboard` に遷移 | ダッシュボードに遷移（パスが不明） |
| `/onboarding?step=2` に遷移 | ステップ2に遷移 |

### 5. フォーム項目

**確認元**: `<label>`, `<FormLabel>`, `aria-label`, React Hook Formの`register`名

```typescript
// 実装コード例
<FormField name="last_name" label="姓" required />
<FormField name="first_name" label="名" required />
<FormField name="nickname" label="ニックネーム" />
```

| 書くべき内容 | 書いてはいけない内容 |
|------------|-------------------|
| 姓（必須）、名（必須） | 氏名（必須） |
| ニックネーム（任意） | ニックネーム（必須） |

### 6. 型定義・データモデル

**確認元**: `domain/models/*.ts`, `database.types.ts`

```typescript
// 実装コード例 - domain/models/user.ts
export interface UserEntity {
  id: string;
  last_name: string | null;
  first_name: string | null;
  nickname: string | null;
  phone: string;
  email: string;
}
```

| 書くべき内容 | 書いてはいけない内容 |
|------------|-------------------|
| `last_name: string \| null` | `lastName: string` |
| `phone: string` | `phone: string \| null` |

**注意**: Entity型（DB層）はsnake_case、UI型はcamelCase。混同しないこと。

### 7. DB操作・テーブル名

**確認元**: `database.types.ts`, repository層の`.from('table_name')`

```typescript
// 実装コード例 - repository
const { data } = await supabase
  .from('users')
  .select('id, last_name, first_name')
  .eq('id', userId);
```

| 書くべき内容 | 書いてはいけない内容 |
|------------|-------------------|
| `users`テーブル | `user`テーブル（単数形） |
| `last_name`カラム | `lastName`カラム |

---

## よくある間違いパターン

### パターン1: 一般的な知識で書いてしまう

```
❌ 「電話番号は10〜11桁の数字」（日本の一般常識）
✅ 「電話番号は10文字以上、数字とハイフンのみ」（実際のZodスキーマ）
```

### パターン2: 似ているが違う文言

```
❌ 「戻る」ボタン（一般的なUI用語）
✅ 「前へ」ボタン（実際のJSXテキスト）
```

### パターン3: カラム名の推測

```
❌ career テーブル（単数形で推測）
✅ careers テーブル（database.types.tsで確認）
```

### パターン4: nullable の見落とし

```
❌ first_name: string（nullableを見落とし）
✅ first_name: string | null（database.types.tsで確認）
```

### パターン5: テスト総数の不正確

```
❌ Unit 9件（describeブロック数を数えた）
✅ Unit 41件（itブロック数を正確にカウントした）
```

---

## 検証方法

### 1. Spec作成後のセルフレビュー

Specに記載した各文言について、以下を確認する:

```
□ この文言は、どのファイルの何行目から取得したか説明できるか？
□ 実装コードを見ずに書いた推測的な記述はないか？
□ 「〜だろう」「〜と思われる」という曖昧な表現はないか？
```

### 2. /verifying-consistency の活用

Spec・テスト・実装の3点整合性を自動チェックする。不整合が見つかった場合、原則としてSpecを実装に合わせて修正する。

### 3. grep での文言一致確認

```bash
# REQUIREMENTS.mdに書いたボタンラベルが実装に存在するか確認
# <app.path> は .stdd.config.yml の apps[].path（複数アプリは apps[] をループ）
grep -r "保存して次へ" <app.path>/app/

# TECH_DESIGN.mdに書いたバリデーションルールが実装に存在するか確認
grep -r "min(10" <app.path>/app/
```
