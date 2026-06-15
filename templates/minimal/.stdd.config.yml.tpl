# STDD 設定ファイル
# JSON Schema: https://raw.githubusercontent.com/careerchain-ys/stdd/main/packages/core/schema/.stdd.config.schema.json
# yaml-language-server: $schema=https://raw.githubusercontent.com/careerchain-ys/stdd/main/packages/core/schema/.stdd.config.schema.json

version: 1

project:
  name: "{{project.name}}"
  language: "ja"
  primary_branch: "main"

apps:
  - id: app
    path: "."
    # port: 3000   # dev サーバのポート。QA の Playwright MCP 動作確認で URL 構築に使う

commands:
  # 使用 stack に合わせて置き換える（STDD は stack 非依存）。例:
  #   Node/TS:  typecheck: "npx tsc --noEmit"  test: "npm test"            build: "npm run build"
  #   Python:   typecheck: "mypy ."            test: "pytest"             build: ""
  #   Rails:    typecheck: ""                  test: "bin/rails test"     build: ""
  typecheck: "npx tsc --noEmit"
  test: "npm test"
  build: "npm run build"
  # dev: "npm run dev"   # 任意。定義すると QA がブラウザ動作確認（Playwright MCP）を実施。未定義ならスキップ

docs:
  layout:
    requirements: "docs/{{feature_path}}/REQUIREMENTS.md"
    tech_design: "docs/{{feature_path}}/TECH_DESIGN.md"
    test_plan: "docs/{{feature_path}}/TEST_PLAN.md"
    plan: "docs/{{feature_path}}/plans/{{date}}.md"

workflow:
  branch_prefix: "claude/"
  enforce_spec_first: "warn"   # off | warn | block — 実装編集時に Spec→テスト→実装 の順序を促す PreToolUse フック
  worktree:
    enabled: false
  devcontainer:
    enabled: false

plugins: []
