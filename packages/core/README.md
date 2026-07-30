# @stdd/core

STDD (Spec and Test Driven Development) の **方法論ドキュメント**, **Spec / PLAN テンプレート**, **プロジェクト設定 JSON Schema** をまとめた core パッケージ。

技術スタックや実行環境に依存しない汎用部分のみを含む。
具体的なスタック (Next.js + Supabase, Playwright, devcontainer + worktree 等) のノウハウは別途プラグイン (`@stdd/plugin-*`) に分離する。

---

## ディレクトリ構成

```
packages/core/
├── docs/
│   └── stdd-methodology.md       # STDD とは / 開発フロー（Mermaid 図を含む）
├── schema/
│   └── .stdd.config.schema.json  # .stdd.config.yml の JSON Schema (Draft 2020-12)
└── README.md                     # 本ファイル
```

> spec / PLAN テンプレートは `.claude/skills/documenting-requirements/templates/`（REQUIREMENTS）・
> `.claude/skills/documenting-tech-specs/templates/`（TECH_DESIGN・TEST_PLAN・common 技術階層）と
> `.claude/skills/documenting-plans/templates/`（PLAN）に集約されている。

---

## はじめての方は

1. `docs/stdd-methodology.md` を読んで STDD の全体像とフロー図を掴む
2. 自プロジェクトに `.stdd.config.yml` を作成し、`schema/.stdd.config.schema.json` で IDE 補完 / 検証を有効化する
3. `documenting-requirements`（要件）／ `documenting-tech-specs`（技術設計）スキルのテンプレート（`.claude/skills/documenting-requirements/templates/`・`.claude/skills/documenting-tech-specs/templates/`）を参照して spec を書き始める

---

## `.stdd.config.yml` の最小構成例

```yaml
project:
  name: my-app
  primary_branch: main

apps:
  - id: web
    path: apps/web

commands:
  # 使用 stack に合わせて指定（STDD は stack 非依存。下記は Node/TS の例）
  typecheck: "npx tsc --noEmit"
  test: "npm test"

docs:
  layout:
    # common 階層 (プロジェクト全体の俯瞰 spec。任意)
    common_requirements: "docs/common/REQUIREMENTS.md"
    common_architecture: "docs/common/ARCHITECTURE.md"
    # feature 階層 (機能単位の spec)
    requirements: "docs/{{app.id}}/{{feature_path}}/REQUIREMENTS.md"
    tech_design: "docs/{{app.id}}/{{feature_path}}/TECH_DESIGN.md"
    plan: "docs/{{app.id}}/{{feature_path}}/plans/{{date}}.md"
```

`common_requirements` / `common_architecture` はプロジェクト全体を俯瞰する **common 階層** の spec
(`REQUIREMENTS.md` の全体版と `TECH_DESIGN.md` の全体版 = `ARCHITECTURE.md`) を指す。任意項目であり、
common 階層を使わないプロジェクトでは省略してよい。なお `ARCHITECTURE` / `TECH_DESIGN` / `TABLE_DEFINITION` / `API_SPEC` / `TEST_PLAN` / `DESIGN` など技術系の設計書は技術 spec (tech_specs) と総称する。詳細は
[`docs/stdd-methodology.md`](docs/stdd-methodology.md) §3 を参照。

このまま `apps/web/` に Next.js / Remix / SvelteKit 等を配置すれば動作する。
複数アプリ構成 (例: `admin` と `web`) は `apps[]` に複数項目を追加する。

### IDE 補完を有効化する

`.stdd.config.yml` の先頭に `yaml-language-server` ディレクティブを追加すると、VS Code / Neovim 等で補完と検証が効く。

**(A) このリポジトリ内部から参照する場合 (相対パス)**:

```yaml
# yaml-language-server: $schema=./packages/core/schema/.stdd.config.schema.json
```

**(B) 下流プロジェクトから参照する場合 (raw URL)**:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/careerchain-ys/stdd/main/packages/core/schema/.stdd.config.schema.json
```

(B) は本パッケージを直接 vendoring せず GitHub 上から都度フェッチする方式。
本番運用ではバージョン固定のため、`main` をリリースタグ (例: `v0.1.0`) に置き換えることを推奨する。

> **注記**: 上記 URL に含まれる組織名 (`careerchain-ys`) は **公開リポジトリのホスト組織名** にすぎず、stdd の利用に当該組織固有の概念・依存はない。`$id` の URL は JSON Schema の identifier として下流プロジェクトの `yaml-language-server` 参照から解決されるため、互換性維持のためにそのまま維持している。将来 GitHub org / repo のリネームが行われた場合は別 Phase で URL を更新する。

---

## JSON Schema のローカル検証

`ajv-cli` でスキーマ自体の構文を検証できる:

```bash
npx -y ajv-cli@5 compile --spec=draft2020 -s packages/core/schema/.stdd.config.schema.json
```

任意の `.stdd.config.yml` を検証する場合は YAML を JSON に変換した上で `validate` する:

```bash
npx -y js-yaml my-project/.stdd.config.yml > /tmp/stdd.json
npx -y ajv-cli@5 validate --spec=draft2020 \
  -s packages/core/schema/.stdd.config.schema.json \
  -d /tmp/stdd.json
```

---

## このパッケージに含めないもの

- 各エージェント向けの生成物（`.claude/` `.agents/` `.codex/`）→ `scripts/build-adapters.mjs` が `packages/core/{skills,agents,hooks,rules}` から生成し、リポジトリルートに committed（本パッケージには含めない）
- プラグイン (`@stdd/plugin-nextjs-supabase`, `@stdd/plugin-playwright`, `@stdd/plugin-worktree`)
- 設定駆動化レンダラ (`packages/shared-rendering/`)
- **テストファイル配置の宣言** (`e2e/tests/...`, `<app>/components/*.test.tsx` 等は現状テンプレ内に直接記述)。schema に `tests.layout` を導入するかは Phase 1-B で再評価する
- サンプルプロジェクト (`examples/`)

これらは Phase 1-B 以降の別 issue / 別 PR で順次追加する。

---

## ライセンス

Apache License 2.0 (リポジトリルートの `LICENSE` を参照)
