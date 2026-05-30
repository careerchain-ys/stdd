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
  lint: "npm run lint"
  db_reset: "npx supabase db reset"
  db_types: "npx supabase gen types typescript --local"

docs:
  layout:
    requirements: "docs/{{feature_path}}/REQUIREMENTS.md"
    tech_design: "docs/{{feature_path}}/TECH_DESIGN.md"
    plan: "docs/{{feature_path}}/plans/{{date}}.md"

workflow:
  branch_prefix: "claude/"
  worktree:
    enabled: false
  devcontainer:
    enabled: false

# nextjs-supabase / playwright プラグインを有効化（CLI が各 skills を .claude/skills/ に展開済み）
plugins:
  - "nextjs-supabase"
  - "playwright"
