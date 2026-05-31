# {{project.name}}

Next.js (App Router) + Supabase 向けの STDD (Spec and Test Driven Development) プロジェクトです。`npx stdd init` で導入されました。

## 同梱プラグイン

`.stdd.config.yml` の `plugins` で以下を有効化済みです。各プラグインの skill は `.claude/skills/` に展開されています。

- **nextjs-supabase** — `implementing-ui`（UI 実装ガイド）/ `migrating-supabase`（マイグレーション・RLS 運用）
- **playwright** — `e2e-testing` / `run-e2e`（E2E テスト）

## 前提

このテンプレートは設定（`.stdd.config.yml`）・STDD スキル一式・`docs/common/` の雛形を提供します。Next.js / Supabase アプリ本体は別途用意してください（下記「アプリ骨組み」）。

## おすすめ: Claude に立ち上げを任せる

`claude` を起動して「STDD で立ち上げを進めて」と伝えると、`.claude/skills/starting-new-with-stdd` が起動し、**下記の骨組み生成 → common ティア設計 → 最初の feature → フォーマット策定 → feature ループ**を 1 ステップずつ対話的に駆動します（進捗は `docs/common/plans/stdd-bootstrap.md` に保持）。
立ち上げの考え方は stdd の `guide-for-new-project.md` を参照。

## アプリ骨組み（step 1 の手順 / SSoT）

`starting-new-with-stdd` の step 1 はこの手順を参照して駆動します。手動で進める場合もここに従ってください。

1. アプリ本体をセットアップ（未作成の場合）

   ```bash
   npx create-next-app@latest .   # Next.js (App Router)
   npx supabase init              # Supabase
   # Playwright（E2E）
   npm init playwright@latest
   ```

2. `.stdd.config.yml` を実環境に合わせて確認・調整
   - `apps[].path` / `apps[].port`
   - `commands.test` / `commands.build` / `commands.db_reset` / `commands.db_types`

## 手動でフローを回す場合

`claude` を起動し、common ティア（`docs/common/`）を設計後、機能要望を伝えると `.claude/skills/auto-implement` が REQUIREMENTS / TECH_DESIGN / PLAN / テスト / 実装 / PR 草案を生成します。プラグインの skill（`implementing-ui` / `e2e-testing` 等）も必要に応じて参照されます。

設定スキーマの詳細は [stdd リポジトリ](https://github.com/careerchain-ys/stdd) を参照してください。

## ライセンス

このテンプレートをそのまま採用する場合は、必要に応じて `LICENSE` ファイルを追加してください。
