#!/bin/bash
# review-runner.sh の振る舞いテスト。
#   bash test/review-runner.test.sh
set -u
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
S="$REPO_ROOT/packages/core/skills/auto-implement/scripts/review-runner.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/stdd-review-runner.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
unset CODEX_SESSION_ID CODEX_THREAD_ID CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS

# $1 = 説明、$2 = 期待する 1 行目、$3 = 期待する 2 行目の一部、以降 = 実行する前置（env ...）
check() {
    local desc="$1" want="$2" reason="$3"; shift 3
    local out first
    out=$("$@" bash "$S" --root "$TMP/repo" 2>&1)
    first=$(printf '%s\n' "$out" | head -1)
    if [ "$first" = "$want" ] && printf '%s' "$out" | grep -qF -- "$reason"; then
        PASS=$((PASS+1)); echo "  PASS: $desc"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $desc"; printf '%s\n' "$out"
    fi
}

mkdir -p "$TMP/repo/.claude" "$TMP/home/.claude"
H="HOME=$TMP/home"

echo "review-runner.sh tests"
check "何も設定が無ければ subagents" subagents "設定されていない" env "$H"
check "環境変数 1 なら teams" teams "環境変数" env "$H" CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
check "環境変数 0 なら subagents" subagents "=0" env "$H" CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0

printf '{\n  "env": {\n    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"\n  }\n}\n' > "$TMP/home/.claude/settings.json"
check "ユーザーの settings の 1 で teams" teams "home/.claude/settings.json" env "$H"
check "settings の値は環境変数より優先する" teams "settings.json" env "$H" CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0

printf '{"env":{"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS":0}}' > "$TMP/repo/.claude/settings.json"
check "プロジェクトの settings はユーザーより優先する（数値の 0）" subagents "repo/.claude/settings.json" env "$H"

printf '{"env":{"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS":"1"}}' > "$TMP/repo/.claude/settings.local.json"
check "local の settings が最優先" teams "settings.local.json" env "$H"

check "Codex のセッションは subagents" subagents "Codex" env "$H" CODEX_THREAD_ID=t1

printf '{"env":{"OTHER":"1"}}' > "$TMP/repo/.claude/settings.local.json"
rm "$TMP/repo/.claude/settings.json" "$TMP/home/.claude/settings.json"
check "ほかの env だけなら設定なしとみなす" subagents "設定されていない" env "$H"

out=$(bash "$S" --bogus 2>&1); rc=$?
if [ $rc -ne 0 ] && printf '%s' "$out" | grep -q "未知の引数"; then PASS=$((PASS+1)); echo "  PASS: 未知の引数はエラー"; else FAIL=$((FAIL+1)); echo "  FAIL: 未知の引数はエラー"; fi

echo
echo "結果: PASS $PASS / FAIL $FAIL"
[ "$FAIL" -eq 0 ]
