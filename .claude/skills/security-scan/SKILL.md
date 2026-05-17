---
name: security-scan
description: |-
  プロジェクトのコードベースに対してセキュリティ監査を実行するスキル。シークレット漏洩検出、OWASP Top 10チェック（インジェクション・認証・アクセス制御）、Supabase RLSポリシー監査、依存パッケージの脆弱性（npm audit）を網羅的に行いレポート出力する。「セキュリティスキャン」「脆弱性チェック」「security scan」「OWASP」「シークレット漏洩確認」「RLS監査」「npm audit」「セキュリティ監査」など、セキュリティ確認の依頼があった際に使用する。
allowed-tools: Read, Grep, Glob, Bash
---

# セキュリティ脆弱性スキャンスキル

プロジェクトのコードベースに対してセキュリティ監査を実行し、脆弱性・設定ミス・シークレット漏洩を検出する。

## 引数

**形式**: `[--scope <user_app|admin_app|all>] [--focus <secrets|owasp|rls|deps|all>]`

デフォルト: `--scope all --focus all`

## Step 1: スキャン対象の決定

引数から以下を抽出:

- **scope**: スキャン対象アプリ（デフォルト: `all`）
- **focus**: スキャン重点領域（デフォルト: `all`）

## Step 2: シークレット漏洩検出

以下のパターンでハードコードされたシークレットを検索する:

```
検出パターン:
- APIキー: sk-, ghp_, gho_, AKIA, xox[bpas]-
- トークン: token, secret, password, credential
- 接続文字列: DATABASE_URL, SUPABASE_SERVICE_ROLE_KEY
- Base64エンコードされた認証情報
- .env ファイルの値がコードに直接記載されていないか
```

**検索対象ファイル**: `*.ts`, `*.tsx`, `*.js`, `*.json`（`node_modules/`, `.next/`, `generated/` を除く）

**除外対象**:

- `.env.example`（テンプレートファイル）
- テストファイル内のモック値
- 型定義ファイル

## Step 3: OWASP Top 10 チェック

### 3-1: インジェクション（A03:2021）

- SQLインジェクション: テンプレートリテラルでの直接クエリ構築がないか
- XSS: `dangerouslySetInnerHTML` の使用、ユーザー入力の未サニタイズ出力
- コマンドインジェクション: `exec()`, `spawn()` へのユーザー入力

### 3-2: 認証の不備（A07:2021）

- セッション管理: NextAuth設定の適切性
- パスワードポリシー: 最小要件の確認
- JWTの取り扱い: トークンの保存場所・有効期限

### 3-3: アクセス制御の不備（A01:2021）

- Server Actions / API ルートでの認証チェック漏れ
- `hasRoleOrHigher()` による権限検証の適用漏れ
- admin_appのroute保護

### 3-4: セキュリティ設定ミス（A05:2021）

- CORSヘッダーの設定
- セキュリティヘッダー（CSP, X-Frame-Options等）
- デバッグモードの本番環境での有効化

## Step 4: Supabase RLSポリシー監査

```
チェック項目:
- RLSが有効化されていないテーブルの検出
- 過度に寛容なポリシー（USING (true)）の検出
- service_roleキーのクライアント側使用
- anon keyでアクセス可能な範囲の確認
```

マイグレーションファイル（`supabase/migrations/`）を走査してRLSポリシーを分析する。

## Step 5: 依存パッケージの脆弱性

各アプリディレクトリで `npm audit` を実行し、結果を分析する:

```bash
cd user_app && npm audit 2>/dev/null
cd admin_app && npm audit 2>/dev/null
```

**分析手順**:

1. `npm audit` の出力からCritical/Highの脆弱性を抽出
2. 影響を受けるパッケージ名・バージョン・脆弱性の概要を記録
3. `npm audit fix` で自動修正可能かを確認
4. 自動修正不可の場合は代替パッケージまたはワークアラウンドを提案

Critical/Highの脆弱性を報告する。

## Step 6: レポート出力

```markdown
## セキュリティスキャンレポート

**スキャン日時**: YYYY-MM-DD HH:MM
**スキャン対象**: <scope>
**重点領域**: <focus>

### サマリー

| カテゴリ         | Critical | High  | Medium | Low   |
| ---------------- | -------- | ----- | ------ | ----- |
| シークレット漏洩 | X        | X     | X      | X     |
| OWASP Top 10     | X        | X     | X      | X     |
| RLSポリシー      | X        | X     | X      | X     |
| 依存パッケージ   | X        | X     | X      | X     |
| **合計**         | **X**    | **X** | **X**  | **X** |

### 検出された問題

#### [Critical/High/Medium/Low] 問題タイトル

**ファイル**: path/to/file.ts:123
**カテゴリ**: シークレット / インジェクション / 認証 / アクセス制御 / RLS / 依存パッケージ
**問題**: 具体的な説明
**リスク**: 悪用された場合の影響
**推奨対応**: 修正方法

### 総合評価: A / B / C / D / F

- **A**: 重大な問題なし
- **B**: Lowレベルの問題のみ
- **C**: Mediumレベルの問題あり
- **D**: Highレベルの問題あり
- **F**: Criticalレベルの問題あり（即座に対応が必要）
```

## 注意事項

- Critical/Highの問題が検出された場合、修正案を提示する
- シークレットが検出された場合、即座にローテーションを推奨する
- RLSの問題は `migrating-supabase` スキルを参照して修正する
