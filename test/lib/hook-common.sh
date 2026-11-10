# PreToolUse フックの振る舞いテストで共有する補助（source して使う）。jq が必要。
# 一時 git リポジトリを作り、フックへの入力（JSON）を stdin で流して stdout を確かめる。

PASS=0
FAIL=0
OUT=""; RC=0
ok() { PASS=$((PASS+1)); echo "  PASS: $1"; }
ng() { FAIL=$((FAIL+1)); echo "  FAIL: $1 (rc=$RC)"; echo "----- OUT -----"; printf '%s\n' "$OUT"; echo "---------------"; }

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq が無いためテストを実行できません"
    exit 0
fi

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP_ROOT=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/stdd-hook-test.XXXXXX")" && pwd -P)
trap 'rm -rf "$TMP_ROOT"' EXIT
unset CLAUDE_PROJECT_DIR CLAUDE_CODE_SESSION_ID CODEX_SESSION_ID CODEX_THREAD_ID

# $1 = ディレクトリ、$2 = workflow: の下に足す行（空可）、$3 = commands.test（既定 "npm test"）
make_repo() {
    local dir="$1"
    mkdir -p "$dir"
    (
        cd "$dir" || exit 1
        git init -q -b main
        git config user.email t@example.com
        git config user.name t
        cat > .stdd.config.yml <<YML
version: 1
project:
  name: "tmp"
  primary_branch: "main"
apps:
  - id: app
    path: "."
commands:
  typecheck: "true"
  test: "${3:-npm test}"
docs:
  layout:
    common_requirements: "docs/common/REQUIREMENTS.md"
    requirements: "docs/{{app.id}}/{{feature_path}}/REQUIREMENTS.md"
    tech_design: "docs/{{app.id}}/{{feature_path}}/TECH_DESIGN.md"
    test_plan: "docs/{{app.id}}/{{feature_path}}/TEST_PLAN.md"
    plan: "plans/{{date}}.md"  # PLAN は別の場所
workflow:
  branch_prefix: "claude/"
$2
YML
        git add -A
        git commit -qm init
    )
}

# フックを実行する。$1 = フック名、$2 = 入力 JSON、$3 = 実行するディレクトリ
run_hook() {
    OUT=$(cd "$3" && printf '%s' "$2" | bash "$REPO_ROOT/packages/core/hooks/$1")
    RC=$?
}

# 入力 JSON を作る。$1 = tool_name、$2 = tool_input（JSON）、$3 = agent_type（空ならメインのエージェント）、$4 = cwd、$5 = session_id
hook_input() {
    jq -cn --arg t "$1" --argjson i "$2" --arg a "${3:-}" --arg c "${4:-}" --arg s "${5:-sess-1}" \
        '{tool_name:$t, tool_input:$i, session_id:$s}
         + (if $a == "" then {} else {agent_id:"agent-1", agent_type:$a} end)
         + (if $c == "" then {} else {cwd:$c} end)'
}

expect_silent() { [ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "$1" || ng "$1"; }
expect_warn()   { [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '"additionalContext"' && ! printf '%s' "$OUT" | grep -q '"deny"' && ok "$1" || ng "$1"; }
expect_deny()   { [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '"permissionDecision": *"deny"' && ok "$1" || ng "$1"; }
expect_out_contains() { printf '%s' "$OUT" | grep -qF -- "$2" && ok "$1" || ng "$1"; }

finish() {
    echo
    echo "結果: PASS ${PASS} / FAIL ${FAIL}"
    [ "$FAIL" -eq 0 ]
}
