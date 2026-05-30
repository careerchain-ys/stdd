# {{project.name}}

Next.js (App Router) + Supabase 向けの STDD (Spec and Test Driven Development) プロジェクトです。`create-stdd-project` CLI の `nextjs-supabase-starter` テンプレートで生成されました。

## 同梱プラグイン

`.stdd.config.yml` の `plugins` で以下を有効化済みです。各プラグインの skill は `.claude/skills/` に展開されています。

- **nextjs-supabase** — `implementing-ui`（UI 実装ガイド）/ `migrating-supabase`（マイグレーション・RLS 運用）
- **playwright** — `e2e-testing` / `run-e2e`（E2E テスト）

## 前提

このテンプレートは設定（`.stdd.config.yml`）と STDD スキル一式のみを提供します。Next.js / Supabase アプリ本体は別途用意してください（例: `npx create-next-app`、`npx supabase init`）。`.stdd.config.yml` の `apps[].path` / `commands.*` を実環境に合わせて調整してください。

## 次の手順

1. アプリ本体をセットアップ（未作成の場合）

   ```bash
   # 例
   npx create-next-app@latest .
   npx supabase init
   ```

2. `.stdd.config.yml` を実環境に合わせて確認・調整
   - `apps[].path` / `apps[].port`
   - `commands.test` / `commands.build` / `commands.db_reset` / `commands.db_types`

3. Claude Code を起動して STDD フローを実行

   ```bash
   claude
   ```

   機能要望を伝えると `.claude/skills/auto-implement` が起動し、REQUIREMENTS / TECH_DESIGN / PLAN / テスト / 実装 / PR 草案を生成します。プラグインの skill（`implementing-ui` 等）も必要に応じて参照されます。

設定スキーマの詳細は [stdd リポジトリ](https://github.com/careerchain-ys/stdd) を参照してください。

## ライセンス

このテンプレートをそのまま採用する場合は、必要に応じて `LICENSE` ファイルを追加してください。
