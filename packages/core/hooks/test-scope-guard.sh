#!/bin/bash
# PreToolUse Hook: 対象を絞らないテストの全件実行を止める。
# 登録: Claude / Codex とも Bash（settings.json / .codex/hooks.json）。
#
# 規律（auto-implement の references/implementation.md）: Red / Green の確認では、対象のテストだけを実行する。
#   全件の実行は QA の工程（qa-engineer）・pre-push のフック・CI が受け持つ。
#   全件を何度も回すと待ち時間が積み上がるうえ、確かめたいテストの結果が埋もれる。
#
# 判定: コマンドを && / || / ; / | / & で区切った各部分について、先頭の環境変数の代入を除いた残りが
#   .stdd.config.yml の commands.test そのもので、後ろに対象（- で始まらない引数）が 1 つも無ければ全件とみなす。
#   例（commands.test が "npm test"）: `npm test` ・ `cd app && npm test` ・ `npm test -- --watch=false` は全件、
#   `npm test -- src/foo.test.ts` ・ `npm test -- -t "保存できる"` は対象を絞った実行として通す。
#   リダイレクト（> log、2>&1）は引数に数えない。
#   オプションだけで対象を絞る形（--grep=foo など）も全件と判定する。その場合は対象を引数で渡すか、下の前置を使う。
#
# 通すもの:
#   - qa-engineer の subagent（全件の実行が工程の役割）
#   - STDD_FULL_TEST_REASON="<理由>" を前置した実行（理由が空なら通さない）
#   - フックの外で起きる実行（pre-push のフックや npm script の中から起動される子プロセス）
#
# 強さ: .stdd.config.yml の workflow.enforce_test_scope = off | warn（既定）| block。
# 失敗時: 設定が無い・commands.test が無い・jq が無いときは通す。

command -v jq >/dev/null 2>&1 || exit 0
hook_input=$(cat)

jqr() { printf '%s' "$hook_input" | jq -r "$1 // empty" 2>/dev/null; }

[ "$(jqr '.tool_name')" = "Bash" ] || exit 0
[ "$(jqr '.agent_type')" = "qa-engineer" ] && exit 0
CMD=$(jqr '.tool_input.command')
[ -z "$CMD" ] && exit 0

INPUT_CWD=$(jqr '.cwd')
[ -n "$INPUT_CWD" ] && [ -d "$INPUT_CWD" ] || INPUT_CWD=$(pwd)
ROOT_DIR=$(git -C "$INPUT_CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
CONFIG="$ROOT_DIR/.stdd.config.yml"
[ -f "$CONFIG" ] || exit 0

yaml_scalar() {
    awk -v sec="$1:" -v k="$2:" '
        /^[^[:space:]]/ { insec = ($1 == sec) }
        insec && $1 == k {
            sub(/^[[:space:]]*[^:]*:[[:space:]]*/, "", $0)
            sub(/[[:space:]]+#.*$/, "", $0)
            print $0
            exit
        }
    ' "$CONFIG"
}

strip_quotes() {
    local v="$1"
    v="${v%\"}"; v="${v#\"}"
    v="${v%\'}"; v="${v#\'}"
    printf '%s' "$v"
}

MODE=$(strip_quotes "$(yaml_scalar workflow enforce_test_scope)")
case "$MODE" in
    off) exit 0 ;;
    block) ;;
    *) MODE=warn ;;
esac

squeeze() { printf '%s' "$1" | tr -s ' \t' '  ' | sed -E 's/^ //; s/ $//'; }

TEST_CMD=$(squeeze "$(strip_quotes "$(yaml_scalar commands test)")")
[ -z "$TEST_CMD" ] && exit 0

# 部分ごとに 1 行へ分ける（&&・||・;・|・& と改行）。2>&1 などのリダイレクトは先に取り除く。
SEGMENTS=$(printf '%s\n' "$CMD" \
    | sed -E 's/[0-9]*>&[0-9]+//g; s/[0-9]*>>?[[:space:]]*[^[:space:];&|]+//g; s/<[[:space:]]*[^[:space:];&|]+//g' \
    | sed -E 's/\&\&|\|\||;|\||&/\
/g')

is_full_run() { # $1=部分。全件なら 0
    local seg rest w
    seg=$(squeeze "$1")
    # 先頭の環境変数の代入を取り除く（理由の前置は別に扱う）
    while :; do
        case "$seg" in
            STDD_FULL_TEST_REASON=*) return 1 ;;
            [A-Za-z_]*=*)
                case "${seg%% *}" in
                    *=*) [ "${seg#* }" = "$seg" ] && return 1; seg="${seg#* }" ;;
                    *) break ;;
                esac ;;
            *) break ;;
        esac
    done
    case "$seg" in
        "$TEST_CMD") return 0 ;;
        "$TEST_CMD "*) rest="${seg#"$TEST_CMD" }" ;;
        *) return 1 ;;
    esac
    set -f
    for w in $rest; do
        case "$w" in
            --|-*) ;;
            *) set +f; return 1 ;;
        esac
    done
    set +f
    return 0
}

# 理由の前置: 空の理由（STDD_FULL_TEST_REASON= / ="" / ''）は前置とみなさない
has_empty_reason() {
    printf '%s' "$1" | grep -Eq "STDD_FULL_TEST_REASON=(\"\"|''|[[:space:]]|$)"
}

FOUND=""
while IFS= read -r s; do
    [ -z "$s" ] && continue
    if has_empty_reason "$s"; then
        s=$(printf '%s' "$s" | sed -E "s/STDD_FULL_TEST_REASON=(\"\"|'')?//")
    fi
    if is_full_run "$s"; then FOUND=$(squeeze "$s"); break; fi
done <<EOF
$SEGMENTS
EOF
[ -z "$FOUND" ] && exit 0

REASON="STDD test-scope: テストを全件で実行しようとしています（$FOUND）。\
Red / Green の確認では、対象のテストファイルやテスト名を引数で渡して実行してください（例: $TEST_CMD <テストファイル>）。\
全件の実行は QA の工程・pre-push・CI が受け持ちます。どうしても全件が必要なら、理由を前置して実行してください\
（例: STDD_FULL_TEST_REASON=\"共通部品を変更したため\" $TEST_CMD）。"

if [ "$MODE" = "block" ]; then
    jq -n --arg r "$REASON" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
else
    jq -n --arg r "$REASON（enforce_test_scope=warn のため実行は止めていません）" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$r}}'
fi
exit 0
