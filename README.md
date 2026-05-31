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

> **重要**: v0.1.0 時点で `create-stdd-project` CLI が利用できます。ただし npm への公開は今後の Phase で行うため、現状は **このリポジトリを clone してローカルから CLI を実行する** 方式で利用してください（`npx create-stdd-project` での直接実行は npm 公開後に対応）。

### 0. CLI で新規プロジェクトを作成する（推奨）

```bash
git clone https://github.com/careerchain-ys/stdd.git
cd stdd && npm install && npm run build

# 最小構成（デフォルト）
node packages/create-stdd-project/dist/cli.js <project-name>

# Next.js + Supabase スターター（nextjs-supabase / playwright プラグイン同梱）
node packages/create-stdd-project/dist/cli.js <project-name> --template nextjs-supabase-starter
```

`<project-name>/` に `.stdd.config.yml`・`.claude/`（skill / agent / hook）・`docs/`・`README.md` が展開されます。`--template` を指定すると、テンプレートが宣言するプラグインの skill も `.claude/skills/` に展開されます。

利用可能なテンプレート:

| テンプレート | 内容 |
| --- | --- |
| `minimal`（既定） | 最小構成。コア skill / agent / hook のみ |
| `nextjs-supabase-starter` | Next.js (App Router) + Supabase 向け。`nextjs-supabase`・`playwright` プラグインを同梱 |

以降の手順 1〜4 は CLI を使わず手動で構成する場合の参考です。

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

- skill / agent / hook は `.stdd.config.yml` 駆動で動作します（`apps[].path` / `commands.*` / `project.primary_branch` 等を実行時に参照）。下流プロジェクト固有値のハードコードは除去済みです。記述規約は [`docs/config-driven-authoring.md`](docs/config-driven-authoring.md) を参照してください。
- 別レイアウトのプロジェクト（単一アプリ・複数アプリ・別命名等）で使う場合は、`.stdd.config.yml` の `apps[]` / `commands` を調整すれば対応できます。
- CLI (`create-stdd-project`) は Phase 2-B で実装済みですが、npm への公開（`npx` での直接実行）は今後の Phase で対応予定です。現状はローカル clone から `node packages/create-stdd-project/dist/cli.js <project-name>` で実行してください。

---

## ディレクトリ構成

```
stdd/
├── README.md                  # 本ファイル
├── AGENTS.md                  # AI エージェント設定（agents.md 標準準拠）
├── LICENSE                    # Apache License 2.0
├── NOTICE                     # 著作権表記
├── packages/
│   ├── core/                  # 方法論ドキュメント / テンプレ / JSON Schema
│   │   ├── docs/
│   │   ├── templates/
│   │   └── schema/
│   └── create-stdd-project/   # プロジェクト生成 CLI（create-stdd-project）
├── templates/                 # CLI が展開するプロジェクトテンプレート
│   ├── minimal/               # 最小構成テンプレート
│   └── nextjs-supabase-starter/ # Next.js + Supabase スターター（プラグイン同梱）
├── plugins/                   # 技術スタック別プラグイン
│   ├── nextjs-supabase/       # Next.js + Supabase 向け skill
│   ├── playwright/            # Playwright E2E 向け skill
│   └── worktree/              # git worktree + devcontainer 向け skill
├── .claude/                   # Claude Code 用ファイル群
│   ├── agents/                # エージェント定義
│   └── skills/                # core skill 群
└── docs/                      # 方針・オーサリング規約ドキュメント
```

各プラグインディレクトリには `plugin.json`（プラグインメタデータ）と `skills/` が含まれます。プラグインの分離方針は [`docs/plugin-separation-policy.md`](docs/plugin-separation-policy.md) を参照してください。

---

## 関連ドキュメント

- [`AGENTS.md`](AGENTS.md) — AI エージェント向けのプロジェクト情報
- [`SECURITY.md`](SECURITY.md) — セキュリティ脆弱性の報告経路
- [`packages/core/README.md`](packages/core/README.md) — core パッケージの詳細
- [`packages/core/docs/stdd-methodology.md`](packages/core/docs/stdd-methodology.md) — STDD 方法論
- [`packages/core/docs/workflow-diagram.md`](packages/core/docs/workflow-diagram.md) — 開発フロー図
- [`docs/plugin-separation-policy.md`](docs/plugin-separation-policy.md) — プラグイン分離方針
- [`docs/config-driven-authoring.md`](docs/config-driven-authoring.md) — skill / agent / hook の設定駆動オーサリング規約

---

## 公開リポジトリの所在地について

このリポジトリは GitHub 上で公開されており、Quick Start に記載された clone URL のホスト組織名は **公開リポジトリのホスト組織名** にすぎず、stdd の利用に特定組織への依存はありません。`.stdd.config.yml` の JSON Schema `$id` や `yaml-language-server` ディレクティブで参照される URL も同じ理由で当該パスを含みます。詳細は [`packages/core/README.md`](packages/core/README.md) の注記を参照してください。将来 GitHub org / repo のリネームが行われた場合は別 Phase で URL を更新します。

---

## コントリビューションについて

本リポジトリは **read-only 配布** です。外部からの Issue / Pull Request / コミュニティ貢献は受け付けていません（Apache License 2.0 の範囲で自由に fork・利用できます）。

例外として、**セキュリティ脆弱性の報告のみ** [`SECURITY.md`](SECURITY.md) に記載の GitHub Private Vulnerability Reporting 経由で受け付けます。

---

## ライセンス

[Apache License 2.0](LICENSE)

著作権表記は [`NOTICE`](NOTICE) を参照してください。
