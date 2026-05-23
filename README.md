# STDD (Spec and Test Driven Development)

STDD は、AI エージェントと人間の開発者が協働して仕様駆動・テスト駆動でソフトウェアを開発するための **方法論・テンプレート・skill / agent 群** を提供する OSS プロジェクトです。

「**Spec → Test → Implementation**」を一方向に流す開発フローを軸に、Spec / Plan / Test / Code の整合性を AI エージェントが継続的に検証することで、プロジェクト規模が大きくなっても破綻しない開発体験を目指しています。

なぜ TDD ではなく STDD かについては [`packages/core/docs/stdd-methodology.md`](packages/core/docs/stdd-methodology.md) と [`packages/core/docs/workflow-diagram.md`](packages/core/docs/workflow-diagram.md) を参照してください。

---

## 対応 AI エージェント

v0.1.0 時点で公式に対応している AI エージェントは以下です。

| エージェント   | サポート状況 | 備考                                                                    |
| -------------- | ------------ | ----------------------------------------------------------------------- |
| Claude Code    | 公式サポート | `.claude/agents/` および `.claude/skills/` 配下のファイルがそのまま動作 |
| 他エージェント | 検討中       | agents.md 標準に準拠した `AGENTS.md` を提供しているため、随時対応予定   |

---

## Quick Start

> **重要**: v0.1.0 時点では `create-stdd-project` 等の CLI は未実装です。CLI は Phase 2-B で提供予定です。それまでは **git clone してテンプレートを手動コピーする方式** で利用してください。

### 1. リポジトリを取得する

```bash
git clone https://github.com/careerchain-ys/stdd.git
```

### 2. 自プロジェクトに `.stdd.config.yml` を作成する

`packages/core/README.md` の「`.stdd.config.yml` の最小構成例」をコピーし、自プロジェクトの構成に合わせて調整してください。

### 3. テンプレートをコピーする

```bash
mkdir -p docs/web/<feature_path>
cp stdd/packages/core/templates/REQUIREMENTS.md docs/web/<feature_path>/
cp stdd/packages/core/templates/TECH_DESIGN.md  docs/web/<feature_path>/
cp stdd/packages/core/templates/PLAN.md         docs/web/<feature_path>/plans/$(date +%F).md
```

### 4. Claude Code でフローを実行する

`.claude/agents/` および `.claude/skills/` 配下を自プロジェクトにコピーするか、参照可能な位置に配置することで、Claude Code が STDD フローを実行できるようになります。

詳細な手順は [`AGENTS.md`](AGENTS.md) と [`packages/core/docs/stdd-methodology.md`](packages/core/docs/stdd-methodology.md) を参照してください。

---

## 現状の制約（v0.1.0 時点）

- `.claude/agents/*.md` および `.claude/skills/**/*.md` の一部に、二系統アプリ構成（例: `user_app` / `admin_app`）を前提とした具体コマンド（`cd user_app && npm test` 等）が残存しています。これらは Phase 1-B でテンプレート変数（`{{apps[].path}}` 等）に置換予定です。
- 現状、stdd を別レイアウトのプロジェクト（単一アプリ・別命名等）で使う場合は、当該箇所を手動で書き換えてください。
- CLI (`create-stdd-project`) は Phase 2-B で提供予定です。

---

## ディレクトリ構成

```
stdd/
├── README.md                  # 本ファイル
├── AGENTS.md                  # AI エージェント設定（agents.md 標準準拠）
├── CONTRIBUTING.md            # 貢献ガイド
├── CODE_OF_CONDUCT.md         # 行動規範（Contributor Covenant 2.1）
├── LICENSE                    # Apache License 2.0
├── NOTICE                     # 著作権表記
├── packages/
│   └── core/                  # 方法論ドキュメント / テンプレ / JSON Schema
│       ├── docs/
│       ├── templates/
│       └── schema/
├── plugins/                   # 技術スタック別プラグイン
│   ├── nextjs-supabase/       # Next.js + Supabase 向け skill
│   ├── playwright/            # Playwright E2E 向け skill
│   └── worktree/              # git worktree + devcontainer 向け skill
├── .claude/                   # Claude Code 用ファイル群
│   ├── agents/                # エージェント定義
│   └── skills/                # core skill 群
└── docs/                      # 方針ドキュメント / 各 Phase の spec / plan
```

各プラグインディレクトリには `plugin.json`（プラグインメタデータ）と `skills/` が含まれます。プラグインの分離方針は [`docs/plugin-separation-policy.md`](docs/plugin-separation-policy.md) を参照してください。

---

## 関連ドキュメント

- [`AGENTS.md`](AGENTS.md) — AI エージェント向けのプロジェクト情報
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — 貢献フロー（DCO sign-off など）
- [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) — 行動規範
- [`packages/core/README.md`](packages/core/README.md) — core パッケージの詳細
- [`packages/core/docs/stdd-methodology.md`](packages/core/docs/stdd-methodology.md) — STDD 方法論
- [`packages/core/docs/workflow-diagram.md`](packages/core/docs/workflow-diagram.md) — 開発フロー図
- [`docs/plugin-separation-policy.md`](docs/plugin-separation-policy.md) — プラグイン分離方針

---

## 公開リポジトリの所在地について

このリポジトリは GitHub 上で公開されており、Quick Start に記載された clone URL のホスト組織名は **公開リポジトリのホスト組織名** にすぎず、stdd の利用に特定組織への依存はありません。`.stdd.config.yml` の JSON Schema `$id` や `yaml-language-server` ディレクティブで参照される URL も同じ理由で当該パスを含みます。詳細は [`packages/core/README.md`](packages/core/README.md) の注記を参照してください。将来 GitHub org / repo のリネームが行われた場合は別 Phase で URL を更新します。

---

## ライセンス

[Apache License 2.0](LICENSE)

著作権表記は [`NOTICE`](NOTICE) を参照してください。
