# @stdd/core

STDD (Spec and Test Driven Development) の **方法論ドキュメント**, **Spec / PLAN テンプレート**, **プロジェクト設定 JSON Schema** をまとめた core パッケージ。

技術スタックや実行環境に依存しない汎用部分のみを含む。
具体的なスタック (Next.js + Supabase, Playwright, devcontainer + worktree 等) のノウハウは別途プラグイン (`@stdd/plugin-*`) に分離する。

---

## ディレクトリ構成

```
packages/core/
├── docs/
│   ├── stdd-methodology.md       # STDD とは / なぜ TDD でなく STDD か / 開発フロー
│   ├── stdd-vs-tdd-vs-bdd.md     # 隣接手法との比較と使い分け
│   └── workflow-diagram.md       # 各フローを Mermaid で図示
├── templates/
│   ├── REQUIREMENTS.md           # ビジネス要件テンプレ (コピーして使用)
│   ├── TECH_DESIGN.md            # 技術設計テンプレ (コピーして使用)
│   └── PLAN.md                   # 実装計画テンプレ (コピーして使用)
├── schema/
│   └── .stdd.config.schema.json  # .stdd.config.yml の JSON Schema (Draft 2020-12)
└── README.md                     # 本ファイル
```

---

## はじめての方は

1. `docs/stdd-methodology.md` を読んで STDD の全体像を掴む
2. `docs/stdd-vs-tdd-vs-bdd.md` で「自プロジェクトに STDD が合うか」を判定する
3. `docs/workflow-diagram.md` でフローを視覚的に把握する
4. 自プロジェクトに `.stdd.config.yml` を作成し、`schema/.stdd.config.schema.json` で IDE 補完 / 検証を有効化する
5. `templates/` を実機能のディレクトリにコピーして書き始める

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
  typecheck: "npx tsc --noEmit"
  test: "npm test"

docs:
  layout:
    requirements: "docs/{{app.id}}/{{feature_path}}/REQUIREMENTS.md"
    tech_design: "docs/{{app.id}}/{{feature_path}}/TECH_DESIGN.md"
    plan: "docs/{{app.id}}/{{feature_path}}/plans/{{date}}.md"
```

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

---

## JSON Schema のローカル検証

`ajv-cli` でスキーマ自体の構文を検証できる:

```bash
npx -y ajv-cli compile -s packages/core/schema/.stdd.config.schema.json
```

任意の `.stdd.config.yml` を検証する場合は YAML を JSON に変換した上で `validate` する:

```bash
npx -y js-yaml my-project/.stdd.config.yml > /tmp/stdd.json
npx -y ajv-cli validate \
  -s packages/core/schema/.stdd.config.schema.json \
  -d /tmp/stdd.json
```

---

## このパッケージに含めないもの

- 特定の skill / agent ファイル (Handlebars テンプレ展開後のもの) → `packages/claude-code/` 等の上位パッケージで提供
- プラグイン (`@stdd/plugin-nextjs-supabase`, `@stdd/plugin-playwright`, `@stdd/plugin-worktree`)
- 設定駆動化レンダラ (`packages/shared-rendering/`)
- **テストファイル配置の宣言** (`e2e/tests/...`, `<app>/components/*.test.tsx` 等は現状テンプレ内に直接記述)。schema に `tests.layout` を導入するかは Phase 1-B で再評価する
- サンプルプロジェクト (`examples/`)

これらは Phase 1-B 以降の別 issue / 別 PR で順次追加する。

---

## ライセンス

Apache License 2.0 (リポジトリルートの `LICENSE` を参照)
