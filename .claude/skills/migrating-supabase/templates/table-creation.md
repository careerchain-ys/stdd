# テーブル作成テンプレート

## 基本テンプレート（コピー用）

```sql
-- ===========================================
-- テーブル: table_name
-- 説明: [テーブルの説明]
-- ===========================================

-- 1. テーブル作成
CREATE TABLE IF NOT EXISTS public.table_name (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    -- ビジネスカラム
    field1 TEXT NOT NULL,
    field2 INTEGER,
    field3 JSONB DEFAULT '{}'::jsonb
);

-- 2. インデックス作成（RLSパフォーマンス最適化）
CREATE INDEX idx_table_name_user_id ON public.table_name USING btree (user_id);
CREATE INDEX idx_table_name_created_at ON public.table_name USING btree (created_at DESC);

-- 3. RLS有効化
ALTER TABLE public.table_name ENABLE ROW LEVEL SECURITY;

-- 4. authenticatedユーザー用RLSポリシー（パフォーマンス最適化版）
CREATE POLICY "Users can view their own data" ON public.table_name
    FOR SELECT
    TO authenticated
    USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can insert their own data" ON public.table_name
    FOR INSERT
    TO authenticated
    WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can update their own data" ON public.table_name
    FOR UPDATE
    TO authenticated
    USING ((SELECT auth.uid()) = user_id)
    WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can delete their own data" ON public.table_name
    FOR DELETE
    TO authenticated
    USING ((SELECT auth.uid()) = user_id);

-- 5. service_role用ポリシー（Admin API用）
CREATE POLICY "Service role full access to table_name" ON public.table_name
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- 6. 【重要】service_roleへのGRANT権限付与
GRANT ALL ON public.table_name TO service_role;
```

## カラム追加テンプレート

```sql
-- カラム追加: [カラム説明]
ALTER TABLE public.table_name
ADD COLUMN new_column TEXT;

-- NULL不可のカラムを追加する場合（既存データ対応）
ALTER TABLE public.table_name
ADD COLUMN new_column TEXT DEFAULT '' NOT NULL;

-- インデックスが必要な場合
CREATE INDEX idx_table_name_new_column ON public.table_name(new_column);
```

## 外部キー制約付きテーブル

```sql
CREATE TABLE IF NOT EXISTS public.child_table (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id UUID NOT NULL REFERENCES public.parent_table(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 複合インデックス
CREATE INDEX idx_child_table_parent_user
    ON public.child_table USING btree (parent_id, user_id);
```

## Enumテーブル

```sql
-- Enumタイプを作成
CREATE TYPE public.status_type AS ENUM ('pending', 'active', 'completed', 'cancelled');

-- テーブルで使用
CREATE TABLE IF NOT EXISTS public.tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status public.status_type DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

## JSONB カラムのインデックス

```sql
-- GINインデックス（JSONB検索用）
CREATE INDEX idx_table_name_metadata ON public.table_name USING gin (metadata);

-- 特定のキーに対するインデックス
CREATE INDEX idx_table_name_metadata_key
    ON public.table_name ((metadata->>'specific_key'));
```

## 更新日時の自動更新トリガー

```sql
-- 関数作成（既に存在する場合はスキップ）
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- トリガー作成
CREATE TRIGGER update_table_name_updated_at
    BEFORE UPDATE ON public.table_name
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();
```

## チェックリスト

テーブル作成後:

```
□ CREATE TABLE が成功
□ インデックスが作成されている
□ RLSが有効化されている
□ SELECT/INSERT/UPDATE/DELETE ポリシーがある
□ service_role ポリシーがある
□ GRANT ALL TO service_role がある
□ npm run reset でエラーなし
□ npm run generate-types で型が生成される
```
