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
- `packages/core/docs/stdd-methodology.md` — STDD 方法論（開発フロー図を含む）
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
| 禁止語監査                    | リポジトリの公開状態に応じて、旧名称・固有名詞が残っていないかを `grep -rI` で確認                                          |
| トレーサビリティ監査スクリプトの検証 | `bash test/trace-audit.test.sh`（`packages/core/hooks/trace-audit.sh` の順方向 gap 検知・逆方向影響範囲の振る舞いテスト）        |
| 生成物のドリフト検査          | `npm run check:adapters`（`.claude/` `.agents/` `.codex/` が `packages/core/` と一致するか検査）                          |

> **Core + Adapter**: skill / agent / hook / spec-first ルールの SSoT は `packages/core/{skills,agents,hooks,rules}` です。`scripts/build-adapters.mjs`（`npm run build:adapters`）がこれを各エージェントのネイティブ形式へ生成します — Claude ビュー `.claude/`、Codex ビュー `.agents/skills`・`.codex/`（agents は TOML、hooks は `.codex/hooks.json` + 共有スクリプト）。生成物は committed です。**編集は必ず `packages/core/` 側で行い**、`.claude/` 等の生成物を直接編集しないでください（`npm run check:adapters` がドリフトを検出します）。下流への導入は `stdd init --agent claude|codex|both` が担います。

下流プロジェクト側の `.stdd.config.yml` には `commands.typecheck` / `commands.test` / `commands.lint` を定義してください。stdd の skill / agent はこれらの設定を参照してコマンドを実行します。

---

## コードスタイル

- **言語**: ドキュメント・コメントは日本語を基本とする
- **Markdown**: 見出しは `#`（H1）から始まり、コード塊は ` ``` ` でフェンス
- **JSON**: インデント 2 スペース。`plugin.json` は各プラグインのメタデータ（`id` / `name` / `version` / `skills` / `description`）を記述する
- **YAML**: インデント 2 スペース。`.stdd.config.yml` は kebab-case
- **ファイル名**: skill / agent / plugin の ID は kebab-case
- **Spec / PLAN ドキュメント**: `.claude/skills/documenting-requirements/templates/` ・ `.claude/skills/documenting-tech-specs/templates/` ・ `.claude/skills/documenting-plans/templates/` 配下の構造を踏襲

詳細は `.claude/skills/documenting-requirements/SKILL.md`（要件）・ `.claude/skills/documenting-tech-specs/SKILL.md`（技術設計）および `.claude/skills/documenting-plans/SKILL.md` を参照してください。

---

## テスト方針

STDD では **Spec → Test → Implementation** の順序を厳守します。

1. **Spec 作成**: `REQUIREMENTS.md`（ビジネス要件）・`TECH_DESIGN.md`（技術設計）・`TEST_PLAN.md`（テスト戦略）を先に書く。技術系の設計書（`TECH_DESIGN` / `TEST_PLAN` と common の `ARCHITECTURE` / `TABLE_DEFINITION` / `API_SPEC` / `DESIGN`）は技術 spec (tech_specs) と総称する。テーブル・API は common の `TABLE_DEFINITION.md` / `API_SPEC.md` に集約し feature から参照する。UI を持つ機能では `generating-wireframes` スキルで HTML ワイヤーフレームを生成し、REQUIREMENTS.md の「UI/UX デザイン」から参照する
2. **Test 作成**: TEST_PLAN.md のテスト戦略に基づきテストを書く（Red 状態の確認）
3. **Implementation**: テストが Green になるよう最小限の実装を行う

テスト層の責務分離:

| 層           | 責務                                                          |
| ------------ | ------------------------------------------------------------- |
| Unit         | 単一関数・コンポーネントの振る舞い                            |
| Integration | 複数モジュール間の連携（DB / API / Server Action 等）         |
| E2E          | ユーザー視点のシナリオ（Playwright を用いる場合は plugins/playwright を参照） |

stdd 本体（ドキュメント・テンプレート）は監査スクリプト（grep / JSON validation / schema validation）でテストを構成します。具体的な検証コマンドは本ファイルの「検証コマンド」セクションを参照してください。

---

## セキュリティ留意事項

- **シークレット**: API キー・トークン・パスワードを **絶対にコミットしない**。`.env` 系ファイルは `.gitignore` で除外する
- **個人情報**: 個人を特定可能な情報（氏名・メールアドレス・内部ホスト名等）を含むサンプルをコミットしない
- **公開リポジトリで扱わない情報**: 社内プロジェクト固有の値・テストユーザー情報・本番ホスト名は持ち込まない
- **脆弱性報告窓口**: 脆弱性は公開せず [`SECURITY.md`](SECURITY.md) に記載の GitHub Private Vulnerability Reporting 経由で報告する

---

## コミット / 変更ガイドライン

> 本リポジトリは read-only 配布で、外部からの Issue / Pull Request は受け付けていません（[`README.md`](README.md) 参照）。以下はメンテナ内部の変更運用ルールです。

- **コミット粒度**: 1 コミット = 1 論理的変更。リファクタと機能追加は分離
- **コミットメッセージ**: 本文に「何を」「なぜ」を記載
- **検証**: 変更後は本ファイルの「検証コマンド」を実行し、構文・schema が通ることを確認する
- **評価結果 (eval-result)**: skill / agent を変更する際は評価スコアの記録を **強く推奨**
- **破壊的変更**: schema / skill API / plugin interface の破壊的変更はコミット / リリースノートに明記する

---

## 参考: 主要ファイルの位置

| 種別                  | パス                                            |
| --------------------- | ----------------------------------------------- |
| 方法論ドキュメント（開発フロー図を含む） | `packages/core/docs/stdd-methodology.md` |
| skill / agent / hook / rule の SSoT | `packages/core/{skills,agents,hooks,rules}/`      |
| 要件テンプレート      | `packages/core/skills/documenting-requirements/templates/`             |
| 技術設計テンプレート  | `packages/core/skills/documenting-tech-specs/templates/tech-design.md` |
| PLAN テンプレート     | `packages/core/skills/documenting-plans/templates/plan.md`             |
| 設定 JSON Schema      | `packages/core/schema/.stdd.config.schema.json` |
| ビュー生成器          | `scripts/build-adapters.mjs`（`npm run build:adapters` / `check:adapters`） |
| Claude ビュー（生成物） | `.claude/skills/` `.claude/agents/`             |
| Codex ビュー（生成物）  | `.agents/skills/` `.codex/agents/*.toml` `.codex/hooks.json` `.codex/config.toml` |
| マルチエージェント対応 設計メモ | `docs/multi-agent-support.md`                 |
| プラグイン            | `plugins/`                                      |
