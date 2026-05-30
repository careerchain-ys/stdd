# AGENTS.md

このファイルは [agents.md](https://agents.md/) 標準に準拠した、AI エージェント向けのプロジェクト情報です。Claude Code をはじめとする AI エージェントは、リポジトリ作業を始める前にまず本ファイルを参照してください。

---

## プロジェクト概要

**STDD (Spec and Test Driven Development)** は、AI エージェントと人間の開発者が協働し、仕様駆動・テスト駆動で開発を進めるための方法論・テンプレート・skill / agent 群を提供する OSS プロジェクトです。

- **対象**: あらゆる Web アプリケーションプロジェクト
- **想定読者**: stdd を導入する外部開発者 / プラグイン開発者 / リポジトリメンテナ / AI エージェント
- **言語**: ドキュメントは日本語。英訳は将来検討
- **ライセンス**: Apache License 2.0

エージェントが最初に読むべき参考資料:

- `README.md` — リポジトリの全体像
- `packages/core/docs/stdd-methodology.md` — STDD 方法論
- `packages/core/docs/workflow-diagram.md` — 開発フローの図
- `docs/plugin-separation-policy.md` — プラグイン分離方針

---

## セットアップ手順

リポジトリをクローン直後にエージェントが実行すべきセットアップは以下です。

```bash
# 1. リポジトリを取得
git clone https://github.com/careerchain-ys/stdd.git
cd stdd

# 2. JSON Schema 検証ツールを取得（ローカル検証で使用、任意）
npx -y ajv-cli compile -s packages/core/schema/.stdd.config.schema.json

# 3. プラグイン構造を確認
ls plugins/
```

stdd 本体には Node.js / TypeScript のランタイム実装は含まれていません（v0.1.0 時点ではドキュメント・テンプレート・skill / agent 定義のみ）。`npm install` 等は不要です。

下流プロジェクトに stdd を組み込む場合は、`README.md` の Quick Start に従って `.stdd.config.yml` を作成してください。

---

## ビルド・テスト・lint コマンド

stdd 本体はランタイムコードを含まないため、伝統的なビルド・テスト・lint コマンドは存在しません。代わりに以下の **検証コマンド** を提供します。

| 目的                          | コマンド                                                                       |
| ----------------------------- | ------------------------------------------------------------------------------ |
| JSON Schema の構文検証        | `npx -y ajv-cli compile -s packages/core/schema/.stdd.config.schema.json`      |
| `.stdd.config.yml` の妥当性検証 | YAML を JSON に変換してから `ajv-cli validate` で検証する。詳細手順は [`packages/core/README.md`](packages/core/README.md) の「JSON Schema のローカル検証」セクション（`js-yaml` を介した変換例を含む）を参照 |
| プラグインメタデータの構文検証 | `for f in plugins/*/plugin.json; do python3 -m json.tool "$f" > /dev/null && echo "OK $f"; done` |
| 禁止語監査                    | リポジトリの公開状態に応じて、旧名称・固有名詞が残っていないかを `grep -rI` で確認（詳細は `CONTRIBUTING.md` 参照）         |

下流プロジェクト側の `.stdd.config.yml` には `commands.typecheck` / `commands.test` / `commands.lint` を定義してください。stdd の skill / agent はこれらの設定を参照してコマンドを実行します。

---

## コードスタイル

- **言語**: ドキュメント・コメントは日本語を基本とする
- **Markdown**: 見出しは `#`（H1）から始まり、コード塊は ` ``` ` でフェンス
- **JSON**: インデント 2 スペース。`plugin.json` は `PluginManifest` interface（[`docs/phase2/specs/TECH_DESIGN.md`](docs/phase2/specs/TECH_DESIGN.md) §3 参照）に準拠
- **YAML**: インデント 2 スペース。`.stdd.config.yml` は kebab-case
- **ファイル名**: skill / agent / plugin の ID は kebab-case
- **Spec / PLAN ドキュメント**: `packages/core/templates/` 配下の構造を踏襲

詳細は `.claude/skills/documenting-specifications/SKILL.md` および `.claude/skills/documenting-plans/SKILL.md` を参照してください。

---

## テスト方針

STDD では **Spec → Test → Implementation** の順序を厳守します。

1. **Spec 作成**: `REQUIREMENTS.md`（ビジネス要件）と `TECH_DESIGN.md`（技術設計）を先に書く。UI を持つ機能では `generating-wireframes` スキルで HTML ワイヤーフレームを生成し、REQUIREMENTS.md の「UI/UX デザイン」から参照する
2. **Test 作成**: TECH_DESIGN.md のテスト戦略に基づきテストを書く（Red 状態の確認）
3. **Implementation**: テストが Green になるよう最小限の実装を行う

テスト層の責務分離:

| 層           | 責務                                                          |
| ------------ | ------------------------------------------------------------- |
| Unit         | 単一関数・コンポーネントの振る舞い                            |
| Integration | 複数モジュール間の連携（DB / API / Server Action 等）         |
| E2E          | ユーザー視点のシナリオ（Playwright を用いる場合は plugins/playwright を参照） |

stdd 本体（ドキュメント・テンプレート）は監査スクリプト（grep / JSON validation / schema validation）でテストを構成します。詳細は [`docs/phase2/specs/TECH_DESIGN.md`](docs/phase2/specs/TECH_DESIGN.md) §8 を参照してください。

---

## セキュリティ留意事項

- **シークレット**: API キー・トークン・パスワードを **絶対にコミットしない**。`.env` 系ファイルは `.gitignore` で除外する
- **個人情報**: 個人を特定可能な情報（氏名・メールアドレス・内部ホスト名等）を含むサンプルをコミットしない
- **公開リポジトリで扱わない情報**: 社内プロジェクト固有の値・テストユーザー情報・本番ホスト名は持ち込まない
- **行動規範**: コントリビュータは [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) を尊重すること
- **脆弱性報告窓口**: `SECURITY.md` は Phase 2-B 〜 Phase 2-C で整備予定。それまでは GitHub Issue を使い、機密度の高い問題はメンテナ宛 DM 等で個別連絡

---

## PR ガイドライン

- **コミット粒度**: 1 コミット = 1 論理的変更。リファクタと機能追加は分離
- **コミットメッセージ**: 本文に「何を」「なぜ」を記載
- **DCO sign-off**: すべてのコミットに `git commit -s` で `Signed-off-by: 名前 <email>` を付与する。詳細は [`CONTRIBUTING.md`](CONTRIBUTING.md) 参照
- **PR テンプレート**: `.github/pull_request_template.md` に従い、変更概要 / 関連 issue / テスト結果 / 評価結果 (eval-result) / チェックリストを記入
- **評価結果 (eval-result)**: skill / agent を変更する PR では評価スコアの添付を **強く推奨**（Phase 2-C で QA gate として必須化予定）
- **破壊的変更**: schema / skill API / plugin interface の破壊的変更は PR 説明に明記し、レビューでメンテナの承認を得る

---

## 参考: 主要ファイルの位置

| 種別                  | パス                                            |
| --------------------- | ----------------------------------------------- |
| 方法論ドキュメント    | `packages/core/docs/stdd-methodology.md`        |
| 開発フロー図          | `packages/core/docs/workflow-diagram.md`        |
| Spec テンプレート     | `packages/core/templates/REQUIREMENTS.md`       |
| 技術設計テンプレート  | `packages/core/templates/TECH_DESIGN.md`        |
| PLAN テンプレート     | `packages/core/templates/PLAN.md`               |
| 設定 JSON Schema      | `packages/core/schema/.stdd.config.schema.json` |
| core skill 群         | `.claude/skills/`                               |
| エージェント定義      | `.claude/agents/`                               |
| プラグイン            | `plugins/`                                      |
