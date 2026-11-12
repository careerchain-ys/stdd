# STDD 設定ファイル（Next.js + Supabase スターター）
# JSON Schema: https://raw.githubusercontent.com/careerchain-ys/stdd/main/packages/core/schema/.stdd.config.schema.json
# yaml-language-server: $schema=https://raw.githubusercontent.com/careerchain-ys/stdd/main/packages/core/schema/.stdd.config.schema.json

version: 1

project:
  name: "{{project.name}}"
  language: "ja"
  primary_branch: "main"

apps:
  - id: web
    path: "."
    port: 3000
    framework: "nextjs"

commands:
  typecheck: "npx tsc --noEmit"
  test: "npm test"
  build: "npm run build"
  dev: "npm run dev"
  lint: "npm run lint"
  db_reset: "npx supabase db reset"
  db_types: "npx supabase gen types typescript --local"

docs:
  # 技術 spec のラインナップ（packages/core/docs/spec-lineup.md）。
  #   layered: バックエンド（API_DESIGN / API_TEST_DESIGN）とフロントエンド（SCREEN_DESIGN / SCREEN_TEST_DESIGN）を分け、
  #            機能全体の担保は TEST_DESIGN にまとめる。API だけ・画面だけの構成なら片方の 2 行を消す
  #   single : 機能ごとに TECH_DESIGN と TEST_PLAN の 2 本（layout に tech_design / test_plan を書く）
  lineup: "layered"
  layout:
    # common ティア（プロジェクト全体の俯瞰 spec）
    common_requirements: "docs/common/REQUIREMENTS.md"
    common_architecture: "docs/common/ARCHITECTURE.md"
    common_table_definition: "docs/common/TABLE_DEFINITION.md"
    common_api_spec: "docs/common/API_SPEC.md"
    common_design: "docs/common/DESIGN.md"
    # feature ティア（機能単位の spec）
    requirements: "docs/{{feature_path}}/REQUIREMENTS.md"
    api_design: "docs/{{feature_path}}/API_DESIGN.md"
    api_test_design: "docs/{{feature_path}}/API_TEST_DESIGN.md"
    screen_design: "docs/{{feature_path}}/SCREEN_DESIGN.md"
    screen_test_design: "docs/{{feature_path}}/SCREEN_TEST_DESIGN.md"
    test_design: "docs/{{feature_path}}/TEST_DESIGN.md"
    plan: "docs/{{feature_path}}/plans/{{date}}.md"
  # 転記の検査（skills/documenting-requirements/scripts/state-claims.sh）の語彙。既定の語彙を変えるときだけ書く。
  # state_claims:
  #   nouns: ["機能", "画面", "テーブル"]   # 件数の句で数える成果物の名詞
  #   words: ["未作成", "実装済み"]         # ほかの文書の作成状況を断定する語

workflow:
  branch_prefix: "claude/"
  worktree:
    enabled: false
  devcontainer:
    enabled: false

# ID ベースのトレーサビリティ監査（要件⇄設計⇄テスト⇄実装を UC/FL の ID で機械追跡）。
traceability:
  enabled: true
  enforce: "warn"              # off | warn | block（抜け漏れで pre-push を止めるなら block）
  require_impl_annotation: false
  scan:
    tests:
      - "**/*.test.ts"
      - "**/*.test.tsx"
      - "e2e/**/*.spec.ts"
    impl:
      - "app/**"
      - "components/**"
      - "lib/**"
      - "actions/**"
      - "domain/**"

# nextjs-supabase / playwright プラグインを有効化（CLI が各 skills を .claude/skills/ に展開済み）
plugins:
  - "nextjs-supabase"
  - "playwright"
