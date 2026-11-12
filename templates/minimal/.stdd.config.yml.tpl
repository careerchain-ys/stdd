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
  # 技術 spec のラインナップ（packages/core/docs/spec-lineup.md）。
  #   layered: バックエンド（API_DESIGN / API_TEST_DESIGN）とフロントエンド（SCREEN_DESIGN / SCREEN_TEST_DESIGN）を分け、
  #            機能全体の担保は TEST_DESIGN にまとめる。API だけ・画面だけの構成なら片方の 2 行を消す
  #   single : 機能ごとに TECH_DESIGN と TEST_PLAN の 2 本（layout に tech_design / test_plan を書く）
  lineup: "layered"
  layout:
    requirements: "docs/{{feature_path}}/REQUIREMENTS.md"
    api_design: "docs/{{feature_path}}/API_DESIGN.md"
    api_test_design: "docs/{{feature_path}}/API_TEST_DESIGN.md"
    screen_design: "docs/{{feature_path}}/SCREEN_DESIGN.md"
    screen_test_design: "docs/{{feature_path}}/SCREEN_TEST_DESIGN.md"
    test_design: "docs/{{feature_path}}/TEST_DESIGN.md"
    plan: "docs/{{feature_path}}/plans/{{date}}.md"

# レスポンスコード体系（skills/documenting-tech-specs/guides/response-codes.md）。帯の意味と「1 分岐 1 コード」は固定。
# 機能略号の書き方と共通コードの一覧を変えるときだけ書く。
# response_codes:
#   feature_code_pattern: "^[A-Z]{3,4}$"
#   common_codes:
#     - { name: VALIDATION_ERROR, code: "1800", http: 422 }

workflow:
  branch_prefix: "claude/"
  enforce_spec_first: "warn"   # off | warn | block — 実装編集時に Spec→テスト→実装 の順序を促す PreToolUse フック
  # 以下 3 つも off | warn | block。操作を止める前に、まず warn で誤検知が無いかを確かめる
  enforce_agent_scope: "warn"     # reviewer の subagent の書き込みとシェルの用途を制限する
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
#   patterns:
#     # テスト名の先頭に置いた ID だけをテストとして数える（例: it('[AT-03] [UC-orders-01] 在庫が無ければ拒否する')）
#     test_tag: '\([[:space:]]*.(\[[A-Z]+-[0-9]+\] *)?\[((UC|FL)-[a-z0-9]+-[0-9]+)\]'
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

# subagent と skill のモデルの使い分け（packages/core/docs/model-selection.md）。Claude Code 向けのみ。
# 値はモデルの別名（inherit / opus / sonnet / haiku / fable）。モデルの ID は書かない。
# agent の既定は opus。変えたら stdd init を実行し直す。
# models:
#   agents:
#     code-reviewer: fable    # 影響の大きい変更のレビューで上げる例
#   mechanical: haiku         # 機械的な作業を subagent に任せるときのモデル（既定 haiku）

plugins: []
