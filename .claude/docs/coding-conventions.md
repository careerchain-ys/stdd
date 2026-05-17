# コーディング規約

> このファイルはCareerChainプロジェクトのコーディング規約の正本です。
> エージェントはセッション開始時に必ずこのファイルをReadしてください。

## 命名規則の厳格なルール

- **snake_case禁止**: TypeScript変数定義でsnake_caseは使用しないこと（例外：DBカラム名、APIレスポンス）
- **テストファイル構成**: `Component.tsx`と`Component.test.tsx`が並列する場合、フォルダ構成にすること

  ```
  # ❌ 悪い例: ファイル並列
  SignupForm.tsx / SignupForm.test.tsx

  # ✅ 良い例: フォルダ構成
  SignupForm/
    ├── index.tsx
    └── index.test.tsx
  ```

- \***\*tests**ディレクトリ禁止\*\*: テストとソースを分離しない

## DBカラム名を正確に記載する

**⚠️ 重要**: DBカラム名を想像で書かないこと。必ず `supabase/generated/database.types.ts` で実際のスキーマを確認すること。

## コメントポリシー

- **Whyコメントのみ**: コードの意図・理由を説明（例: `// パフォーマンス改善のためキャッシュ`）
- **What/Howコメント削除**: コードを見れば分かる内容は不要（例: `// ユーザー情報を取得` ← 削除）

## Null/Undefinedアサーション

**`!`演算子禁止**: `assert()`を使用すること

```typescript
import assert from 'node:assert';

// ❌ 悪い例
const email = user.email!;

// ✅ 良い例
assert(user.email, 'user.email is required');
const email = user.email;
```

## `as`型キャスト禁止

`as`による型キャストは意図しないエラーの原因となるため、特段の理由がない限り使用しないこと。代わりに型注釈（`: Type`）、`satisfies`演算子、明示的なマッピング関数を使用する。

```typescript
// ❌ 悪い例
const users = data as UserEntity[];

// ✅ 良い例: 型注釈
const users: UserEntity[] = data.map((row) => ({
  id: row.id,
  name: row.name,
}));

// ✅ 良い例: satisfies
const config = { timeout: 3000 } satisfies RequestConfig;
```

## 純粋関数の定義場所

- コンポーネント外（ファイルのトップレベル）に定義
- 複数コンポーネントで使用する場合は `user_app/lib` に抽象化
- user_appとadmin_appで共有する場合は `packages/shared/` に配置

## DOM直接操作の禁止

**`document.querySelector` / `getAttribute` 禁止**: Reactの宣言的UIパターンに従い、コールバックで状態をリフトアップすること

```typescript
// ❌ 悪い例: DOM直接操作
const handleCancel = useCallback(() => {
  const form = document.querySelector('[data-project-form]');
  const isDirty = form?.getAttribute('data-is-dirty') === 'true';
  if (isDirty) { ... }
}, []);

// ✅ 良い例: 状態のリフトアップ
const [isDirty, setIsDirty] = useState(false);
const handleDirtyChange = useCallback((dirty: boolean) => {
  setIsDirty(dirty);
}, []);
// 子コンポーネントに onDirtyChange={handleDirtyChange} を渡す
```

## Zodバリデーションスキーマ

- **配置先**: `lib/validations/` に一元化（`lib/validation/`、`lib/schemas/`、コンポーネント内、Server Action内への配置は禁止）
- **ファイル名**: kebab-caseのフォルダ/index.tsパターン（例: `lib/validations/login/index.ts`）
- **スキーマ名**: camelCase + Schema suffix（例: `loginSchema`, `projectFormSchema`）
- **型エクスポート**: `z.infer<typeof schema>` で生成する型も同ファイルからexport
- **テスト配置**: 同フォルダに `index.test.ts`（例: `lib/validations/login/index.test.ts`）
- **重複禁止**: 同じバリデーションロジックのコピーは禁止。extend/omit/pickで派生させる

## 型安全性チェック

`.ts`/`.tsx`ファイルの編集後、PostToolUseフック（`post-typecheck.sh`）が自動で`npx tsc --noEmit`を実行する。型エラーが検出された場合は即座に修正すること。
