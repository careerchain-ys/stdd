# RLSパフォーマンス最適化ガイド

## 概要

RLS（Row Level Security）は強力なセキュリティ機能ですが、適切に最適化しないとパフォーマンスに深刻な影響を与えます。本ガイドでは6つの最適化手法を解説します。

## 1. RLSカラムへのインデックス作成（最重要）

**最も効果的**: RLSポリシーで使用するカラムには**必ず**インデックスを作成。

```sql
-- user_idでフィルタリングする場合
CREATE INDEX idx_table_user_id ON public.table USING btree (user_id);
```

### 効果

| 条件 | パフォーマンス |
|------|--------------|
| インデックスなし | Seq Scan（全表スキャン） |
| インデックスあり | Index Scan（100倍以上高速） |

### 確認方法

```sql
EXPLAIN ANALYZE
SELECT * FROM table_name WHERE user_id = 'your-user-id';
```

**Index Scan** が表示されていれば最適化されている。

## 2. 関数をSELECTでラップ（クエリキャッシング）

**NG（行ごとに関数呼び出し）**:
```sql
USING (auth.uid() = user_id)
```

**OK（キャッシュされる）**:
```sql
USING ((SELECT auth.uid()) = user_id)
```

### なぜ効果があるか

- `auth.uid()`を直接使用: 各行の評価時に関数が呼び出される
- `(SELECT auth.uid())`でラップ: 1回の評価でキャッシュされる

### 効果

10〜50倍のパフォーマンス改善が期待できる。

## 3. クライアント側での明示的フィルタリング

RLSのみに依存せず、クライアント側でも**明示的にフィルタリング**:

```typescript
// TypeScriptでの例
const { data } = await supabase
  .from('table_name')
  .select('*')
  .eq('user_id', userId); // 明示的なフィルタを追加
```

### なぜ効果があるか

- クエリプランナーがより効率的な実行計画を選択できる
- RLSポリシーの評価前にデータが絞り込まれる

### 効果

2〜5倍のパフォーマンス改善が期待できる。

## 4. Security Definer関数でRLSバイパス

JOIN時の多段RLS評価を回避:

```sql
CREATE OR REPLACE FUNCTION get_user_team_data(p_user_id UUID)
RETURNS TABLE (team_id UUID, team_name TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT t.id, t.name
    FROM teams t
    INNER JOIN team_users tu ON t.id = tu.team_id
    WHERE tu.user_id = p_user_id;
END;
$$;
```

### 注意点

- `SECURITY DEFINER`は関数の所有者権限で実行される
- セキュリティ上のリスクがあるため、入力値のバリデーションを必ず行う
- `SET search_path = public`でサーチパス攻撃を防ぐ

## 5. JOINロジックの最適化

**NG（サブクエリ内で直接関数呼び出し）**:
```sql
USING (team_id IN (SELECT team_id FROM team_user WHERE user_id = auth.uid()))
```

**OK（SELECTでラップ）**:
```sql
USING (team_id IN (
    SELECT team_id
    FROM team_user
    WHERE user_id = (SELECT auth.uid())
))
```

## 6. ロールベースのアクセス制御

TOクロージャを使用してロールを明示:

```sql
CREATE POLICY "Authenticated users only" ON public.table_name
    FOR SELECT
    TO authenticated  -- ロールを明示
    USING ((SELECT auth.uid()) = user_id);
```

### なぜ効果があるか

- ロールを明示することで、該当しないロールの評価をスキップ
- `anon`ロールでのアクセス時に不要なポリシー評価を回避

## パフォーマンスベンチマーク方法

### テスト手順

```sql
-- RLS有効時のパフォーマンス
EXPLAIN ANALYZE
SELECT * FROM table_name WHERE user_id = 'uuid';

-- RLS無効時のパフォーマンス（比較用）
SET LOCAL ROLE postgres;
EXPLAIN ANALYZE
SELECT * FROM table_name WHERE user_id = 'uuid';
```

### 確認ポイント

| 項目 | 良い状態 | 悪い状態 |
|------|---------|---------|
| スキャン方式 | Index Scan | Seq Scan |
| 実行時間 | < 10ms | > 100ms |
| 行数 | フィルタ後の行数 | 全行数 |

## 最適化チェックリスト

```
□ RLSで使用するカラムにインデックスがある
□ auth.uid() を (SELECT auth.uid()) でラップしている
□ クライアント側で明示的なフィルタを追加している
□ JOINが多い場合はSecurity Definer関数を検討
□ TOクロージャでロールを明示している
□ EXPLAIN ANALYZEでIndex Scanを確認
```

## 参考リンク

- [Supabase RLS Performance Discussion](https://github.com/orgs/supabase/discussions/14576)
- PostgreSQL EXPLAIN Documentation
