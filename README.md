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

## STDD の始め方

導入は 2 パターン。**コードがまだ無いなら【新規】、既に動くコードがあるなら【既存】** を選んでください。
どちらも Claude Code を起動して専用スキルに任せれば、フローを 1 ステップずつ対話的に進められます。

| パターン | 起点コマンド | 起動するスキル | 手順ガイド |
| --- | --- | --- | --- |
| **新規**（コードなし） | `create-stdd-project ... --template nextjs-supabase-starter` | `starting-new-with-stdd` | [`guide-for-new-project.md`](packages/core/docs/guide-for-new-project.md) |
| **既存**（コードあり） | `.claude/` と `.stdd.config.yml` を配置 | `introducing-stdd` | [`guide-for-existing-project.md`](packages/core/docs/guide-for-existing-project.md) |

> **前提**: 現状 CLI は npm 未公開のため、このリポジトリを clone してローカルから実行します（`npx create-stdd-project` 直接実行は npm 公開後）。

### パターンA: 新規プロジェクト（コードがまだ無い）

1. CLI で雛形を生成（Next.js + Supabase + Playwright スターター）:

   ```bash
   git clone https://github.com/careerchain-ys/stdd.git
   cd stdd && npm install && npm run build
   node packages/create-stdd-project/dist/cli.js <project-name> --template nextjs-supabase-starter
   ```

   `<project-name>/` に `.stdd.config.yml`・`.claude/`（skill / agent / hook）・`docs/common/` 雛形が展開されます。
   （技術スタック非依存の最小構成は `--template` 省略 = `minimal`）

2. 生成先で Claude Code を起動し、「STDD で立ち上げを進めて」と伝える:

   ```bash
   cd <project-name> && claude
   ```

   `starting-new-with-stdd` スキルが **アプリ骨組み → common ティア設計 → 最初の feature → フォーマット策定 → feature ループ** を駆動します。進捗は `docs/common/plans/stdd-bootstrap.md` に保持され、セッションを跨いで再開できます。
   → 手順と判断基準: [`guide-for-new-project.md`](packages/core/docs/guide-for-new-project.md)

### パターンB: 既存プロジェクト（既に動くコードがある）

1. このリポジトリの `.claude/`（skill / agent / hook）と `.stdd.config.yml` を自プロジェクトに配置（またはコピー）。`.stdd.config.yml` は構成に合わせて調整します（CLI の対話セットアップでも作成可）。

2. Claude Code を起動し、「STDD を導入して」と伝える:

   ```bash
   claude
   ```

   `introducing-stdd` スキルが **共通spec 逆生成 → 機能インベントリ → 代表機能リバース → フォーマット策定 → 機能ループ → 順行運用** を駆動します。進捗は `docs/common/plans/stdd-introduction.md` に保持されます。
   → 手順と判断基準: [`guide-for-existing-project.md`](packages/core/docs/guide-for-existing-project.md)

<details>
<summary>手動セットアップ（CLI / スキルを使わず構成する場合の参考）</summary>

1. リポジトリを取得: `git clone https://github.com/careerchain-ys/stdd.git`
2. `.stdd.config.yml` を作成（`packages/core/README.md` の「最小構成例」を調整）。
3. テンプレートをコピー:

   ```bash
   mkdir -p docs/<app>/<feature_path>
   cp stdd/packages/core/templates/REQUIREMENTS.md docs/<app>/<feature_path>/
   cp stdd/packages/core/templates/TECH_DESIGN.md  docs/<app>/<feature_path>/
   # 全体版（common ティア）を使う場合
   mkdir -p docs/common && cp stdd/packages/core/templates/common/*.md docs/common/
   ```

4. `.claude/agents/` および `.claude/skills/` を配置（またはコピー）して Claude Code で実行。

</details>

---

## 現状の制約（v0.1.0 時点）

- skill / agent / hook は `.stdd.config.yml` 駆動で動作します（`apps[].path` / `commands.*` / `project.primary_branch` 等を実行時に参照）。下流プロジェクト固有値のハードコードは除去済みです。記述規約は [`docs/config-driven-authoring.md`](docs/config-driven-authoring.md) を参照してください。
- 別レイアウトのプロジェクト（単一アプリ・複数アプリ・別命名等）で使う場合は、`.stdd.config.yml` の `apps[]` / `commands` を調整すれば対応できます。
- 新規プロジェクトの CLI テンプレートは現状 `minimal` と `nextjs-supabase-starter` の 2 種です。`starting-new-with-stdd` / `guide-for-new-project.md` は Next.js + Supabase + Playwright を主な対象としています。
- CLI (`create-stdd-project`) は実装済みですが、npm への公開（`npx` での直接実行）は今後の Phase で対応予定です。現状はローカル clone から `node packages/create-stdd-project/dist/cli.js <project-name>` で実行してください。

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
│   │   ├── docs/              # methodology / 各導入ガイド / workflow-diagram
│   │   ├── templates/         # REQUIREMENTS / TECH_DESIGN / PLAN / common
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

**導入ガイド（ユースケース別）**

- [`packages/core/docs/guide-for-new-project.md`](packages/core/docs/guide-for-new-project.md) — 新規プロジェクトの立ち上げ（最初から順行）
- [`packages/core/docs/guide-for-existing-project.md`](packages/core/docs/guide-for-existing-project.md) — 既存プロジェクトへの導入（遡行ブートストラップ → 順行）

**方法論**

- [`packages/core/docs/stdd-methodology.md`](packages/core/docs/stdd-methodology.md) — STDD 方法論（Spec の 2 ティア構造・テスト戦略・開発フロー）
- [`packages/core/docs/workflow-diagram.md`](packages/core/docs/workflow-diagram.md) — 開発フロー図

**開発・運用の参考**

- [`AGENTS.md`](AGENTS.md) — AI エージェント向けのプロジェクト情報
- [`packages/core/README.md`](packages/core/README.md) — core パッケージ・`.stdd.config.yml` の詳細
- [`docs/plugin-separation-policy.md`](docs/plugin-separation-policy.md) — プラグイン分離方針・core skill 一覧
- [`docs/config-driven-authoring.md`](docs/config-driven-authoring.md) — skill / agent / hook の設定駆動オーサリング規約
- [`SECURITY.md`](SECURITY.md) — セキュリティ脆弱性の報告経路

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
