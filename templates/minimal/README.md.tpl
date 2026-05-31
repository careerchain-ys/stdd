# {{project.name}}

STDD (Spec and Test Driven Development) ベースのプロジェクトです。`npx stdd init` で導入されました。

## 次の手順

1. Claude Code を起動する

   ```bash
   claude
   ```

2. 任意の機能要望を Claude に伝えると、`.claude/skills/auto-implement` が起動して以下を自動生成します。
   - `docs/<feature>/REQUIREMENTS.md` — ビジネス要件
   - `docs/<feature>/TECH_DESIGN.md` — 技術設計
   - `docs/<feature>/plans/<date>.md` — 実装計画
   - テストコード（Red）
   - 実装コード（Green）
   - Pull Request 草案

## プロジェクト設定

`.stdd.config.yml` がプロジェクト固有の設定を保持しています。`apps[].path` や `commands.*` を実環境に合わせて調整してください。

設定スキーマの詳細は [stdd リポジトリ](https://github.com/careerchain-ys/stdd) を参照してください。

## ライセンス

このテンプレートをそのまま採用する場合は、必要に応じて `LICENSE` ファイルを追加してください。
