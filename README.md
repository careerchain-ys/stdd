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

**新規・既存のどちらでも手順は同じ**です。STDD を導入して Claude Code に「導入して」と伝えるだけ。
新規 / 既存の判定はルータースキル (`setup-stdd`) が自動で行い、適切な駆動スキルへ振り分けます。

```bash
cd my-project                 # 既存プロジェクト、または新規の空ディレクトリ
npx @careerchain/stdd init    # ① STDD 一式を現在のディレクトリに導入
claude                        # ② Claude Code を起動
# ③ 「STDD を導入して」と伝える
```

3 ステップの内訳:

1. **`npx @careerchain/stdd init`** — `.claude/`（skill / agent / hook）・`.stdd.config.yml`・`docs/` を**現在のディレクトリ**に配置します。既存ファイルは破壊せず、追加・生成のみ行います（既存の `.stdd.config.yml` は保持）。
2. **`claude`** — Claude Code を起動します。
3. **「STDD を導入して」** — `setup-stdd` ルーターがコードの有無を調べ、確認のうえ次へ委譲します。

| 判定 | 委譲先スキル | 駆動するフロー | 手順ガイド |
| --- | --- | --- | --- |
| **新規**（コードなし） | `starting-new-with-stdd` | アプリ骨組み → common 設計 → 最初の feature → フォーマット策定 → feature ループ | [`guide-for-new-project.md`](packages/core/docs/guide-for-new-project.md) |
| **既存**（コードあり） | `introducing-stdd` | 共通spec 逆生成 → 機能インベントリ → 代表機能リバース → フォーマット策定 → 機能ループ → 順行運用 | [`guide-for-existing-project.md`](packages/core/docs/guide-for-existing-project.md) |

進捗は `docs/common/plans/`（新規=`stdd-bootstrap.md` / 既存=`stdd-introduction.md`）に保持され、セッションを跨いで再開できます。
新規 / 既存が明確な場合は、ルーターを介さず `starting-new-with-stdd` / `introducing-stdd` を直接指名しても構いません。

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
- `npx @careerchain/stdd init` は STDD ツール（`.claude/` / `.stdd.config.yml` / `docs/`）の導入に専念します。アプリの骨組み（Next.js + Supabase + Playwright 等）は `starting-new-with-stdd` スキルが Claude セッション内で構築します。`starting-new-with-stdd` / `guide-for-new-project.md` は Next.js + Supabase + Playwright を主な対象としています。
- CLI の npm パッケージ名は `@careerchain/stdd`（`npx @careerchain/stdd init`）。ローカルで試す場合は、clone 後 `npm install && npm run build` し、対象ディレクトリで `node <stdd>/packages/stdd/dist/cli.js init` を実行してください。

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
│   └── stdd/                  # 導入 CLI（npm パッケージ `@careerchain/stdd`）
├── templates/                 # 参照用プロジェクトテンプレート
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
