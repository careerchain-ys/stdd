# トラブルシューティングガイド

## マイグレーションが適用されない

### 症状

- `npm run reset`後もテーブルが作成されない
- マイグレーションがスキップされる

### 解決方法

```bash
# 1. ローカルDBをリセット
npm run reset

# 2. ログを確認
docker logs supabase_db_careerchain

# 3. マイグレーションファイルの構文エラーを確認
# SQLの構文が正しいか手動でチェック
```

### よくある原因

| 原因 | 対策 |
|------|------|
| ファイル名の形式が不正 | `YYYYMMDDHHMMSS_name.sql` 形式にする |
| SQL構文エラー | セミコロン忘れ、括弧の対応を確認 |
| 依存関係エラー | テーブル作成順序を確認 |

## 型定義が生成されない

### 症状

- `npm run generate-types`が失敗
- `database.types.ts`が更新されない

### 解決方法

```bash
# 1. Supabaseが起動しているか確認
docker ps | grep supabase

# 2. 起動していない場合
npm run start

# 3. 手動で型生成
npm run generate-types
```

## RLSポリシーでアクセスできない

### 症状

- データが取得できない（空配列が返る）
- 403エラーが発生

### 診断方法

```sql
-- ポリシーの確認
SELECT * FROM pg_policies WHERE tablename = 'your_table_name';

-- RLSが有効か確認
SELECT relname, relrowsecurity FROM pg_class WHERE relname = 'your_table_name';
```

### よくある原因と対策

| 症状 | 原因 | 対策 |
|------|------|------|
| データが空 | RLSポリシーが厳しすぎる | `USING`条件を確認 |
| 403エラー | GRANT権限がない | `GRANT ALL TO service_role` |
| 特定操作のみ失敗 | FOR句が不足 | SELECT/INSERT/UPDATE/DELETE各ポリシーを確認 |

## service_roleでアクセスできない（403エラー）

### 症状

- Edge FunctionやServer Actionから403エラー
- RLSポリシーは設定済み

### 原因

**RLSポリシーだけでは不十分**。GRANT権限も必要。

### 解決方法

```sql
-- 1. RLSポリシーを確認
SELECT * FROM pg_policies
WHERE tablename = 'your_table_name'
AND roles @> ARRAY['service_role'];

-- 2. GRANT権限を確認
SELECT grantee, privilege_type
FROM information_schema.table_privileges
WHERE table_name = 'your_table_name';

-- 3. 不足している場合は追加
GRANT ALL ON public.your_table_name TO service_role;
```

## パフォーマンスが遅い

### 症状

- クエリが数秒かかる
- ページ読み込みが遅い

### 診断方法

```sql
EXPLAIN ANALYZE
SELECT * FROM table_name WHERE user_id = 'uuid';
```

### 確認ポイント

| 状態 | 良い | 悪い |
|------|------|------|
| スキャン方式 | Index Scan | Seq Scan |
| 実行時間 | < 10ms | > 100ms |

### 解決方法

```sql
-- インデックスを作成
CREATE INDEX idx_table_name_user_id ON public.table_name(user_id);

-- auth.uid()をSELECTでラップ（ポリシー再作成）
DROP POLICY "policy_name" ON public.table_name;
CREATE POLICY "policy_name" ON public.table_name
    FOR SELECT TO authenticated
    USING ((SELECT auth.uid()) = user_id);  -- SELECTでラップ
```

## マイグレーションファイル名の衝突

### 症状

- 同日に複数のマイグレーションを作成すると上書きされる
- マイグレーションが実行されない

### 原因

ファイル名の時分秒が`000000`になっている。

### 解決方法

```bash
# 正しいファイル名の生成
touch supabase/migrations/$(date +%Y%m%d%H%M%S)_migration_name.sql
```

```
❌ 20251225000000_add_table.sql
✅ 20251225154732_add_table.sql
```

## 外部キー制約エラー

### 症状

- `violates foreign key constraint`エラー
- 削除操作が失敗

### 解決方法

```sql
-- ON DELETE CASCADEを設定（子レコードも削除）
ALTER TABLE public.child_table
DROP CONSTRAINT child_table_parent_id_fkey,
ADD CONSTRAINT child_table_parent_id_fkey
    FOREIGN KEY (parent_id)
    REFERENCES public.parent_table(id)
    ON DELETE CASCADE;
```

## デバッグ用SQLクエリ集

```sql
-- すべてのテーブル一覧
SELECT tablename FROM pg_tables WHERE schemaname = 'public';

-- テーブルのカラム情報
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'your_table_name';

-- すべてのRLSポリシー
SELECT * FROM pg_policies WHERE schemaname = 'public';

-- インデックス一覧
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'your_table_name';

-- 外部キー制約一覧
SELECT
    tc.constraint_name,
    tc.table_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_name = 'your_table_name';
```
