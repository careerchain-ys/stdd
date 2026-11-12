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
  # 以下 3 つも off | warn | block。操作を止める前に、まず warn で誤検知が無いかを確かめる
  enforce_agent_scope: "warn"     # writer / reviewer の subagent の編集範囲とシェルの用途を制限する
  enforce_worktree_lock: "warn"   # subagent の作業先を、宣言した作業ツリーと突き合わせる
  enforce_test_scope: "warn"      # 対象を絞らない commands.test の全件実行を知らせる
  worktree:
    enabled: false
  devcontainer:
    enabled: false

# ID ベースのトレーサビリティ監査（要件⇄設計⇄テスト⇄実装を UC/FL の ID で機械追跡）。
# scan.tests / scan.impl を採用 stack に合わせて調整して有効化する。
# traceability:
#   enabled: true
#   enforce: "warn"            # off | warn | block（抜け漏れで pre-push を止めるなら block）
#   require_impl_annotation: false
#   scan:
#     tests:
#       - "**/*.test.*"
#       - "e2e/**/*.spec.*"
#     impl:
#       - "src/**"

# 開発時のフィードバックの収集と集計（packages/core/docs/feedback-loop.md）。
# PR を作る前にプロセス上の課題を GitHub issue に起票し（recording-dev-feedback）、
# PR ごとに工程テレメトリを PR コメントへ投稿する（create-pr）。gh コマンドが必要。
# 値はすべて既定値なので、変えないなら省略してよい。
feedback:
  enabled: true
  labels:
    base: "dev-feedback"
    priority_high: "priority:high"
    priority_medium: "priority:medium"
    category_prefix: "category:"
  max_issues_per_pr: 5        # 1 PR から起票してよい件数の上限
  stale_days: 14              # この日数動きのない priority:medium は見送りの候補
  recurrence_to_high: 2       # 再発コメントがこの数に達したら priority:high へ上げる
  registry: "docs/process/improvement-registry.md"

telemetry:
  enabled: true

# 緊急モード（packages/core/docs/work-modes-and-limits.md）。ユーザーが「緊急モード」と明示したときだけ入り、
# 分業・レビューの回数・品質ゲートの合格を必須にしない（Spec → テスト → 実装の順序は守る）。
# 値はすべて既定値なので、変えないなら省略してよい。
emergency_mode:
  enabled: true
  request_ttl_minutes: 120    # ユーザーの申し出を宣言に使える時間（分）

plugins: []
