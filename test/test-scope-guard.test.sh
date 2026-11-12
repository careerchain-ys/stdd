#!/bin/bash
# test-scope-guard.sh の振る舞いテスト。
#   bash test/test-scope-guard.test.sh
set -u
. "$(dirname "$0")/lib/hook-common.sh"
H=test-scope-guard.sh

echo "test-scope-guard.sh tests"

B="$TMP_ROOT/block"; make_repo "$B" '  enforce_test_scope: "block"'
R="$TMP_ROOT/warn"; make_repo "$R" ""
O="$TMP_ROOT/off"; make_repo "$O" '  enforce_test_scope: "off"'
N="$TMP_ROOT/notest"; make_repo "$N" '  enforce_test_scope: "block"' ""
sed -i.bak '/^  test:/d' "$N/.stdd.config.yml"

bash_in() { hook_input Bash "$(jq -cn --arg c "$1" '{command:$c}')" "${2:-}" "$3"; }

echo "[全件とみなす]"
for c in "npm test" "npm  test" "cd app && npm test" "npm test -- --watch=false" "npm test 2>&1" "npm test > test.log" \
         "CI=1 npm test" "npm run build && npm test | tail -5" "npm test; echo done" "STDD_FULL_TEST_REASON= npm test" \
         "STDD_FULL_TEST_REASON=\"\" npm test" $'echo a\nnpm test'; do
    run_hook $H "$(bash_in "$c" "" "$B")" "$B"; expect_deny "全件: $c"
done
run_hook $H "$(bash_in "npm test" general-purpose "$B")" "$B"; expect_deny "subagent の全件も見る"
expect_out_contains "メッセージに絞り方が入る" "npm test <テストファイル>"
expect_out_contains "メッセージに例外の前置が入る" "STDD_FULL_TEST_REASON="

echo "[通す]"
for c in "npm test -- src/foo.test.ts" "npm test -- -t 保存できる" "cd app && npm test src/a.test.ts" \
         "STDD_FULL_TEST_REASON=\"共通部品を変えたため\" npm test" "cd app && STDD_FULL_TEST_REASON=x npm test" \
         "npm run test:e2e" "npm testing" "npm run build" "git log" "echo npm test"; do
    run_hook $H "$(bash_in "$c" "" "$B")" "$B"; expect_silent "通す: $c"
done
run_hook $H "$(bash_in "npm test" qa-engineer "$B")" "$B"; expect_silent "qa-engineer は通す"
run_hook $H "$(hook_input Edit '{"file_path":"a.ts"}' "" "$B")" "$B"; expect_silent "Bash 以外は見ない"

echo "[強さとフェイルオープン]"
run_hook $H "$(bash_in "npm test" "" "$R")" "$R"; expect_warn "既定の warn では知らせるだけ"
run_hook $H "$(bash_in "npm test" "" "$O")" "$O"; expect_silent "off では何もしない"
run_hook $H "$(bash_in "npm test" "" "$N")" "$N"; expect_silent "commands.test が無ければ通す"
NC="$TMP_ROOT/noconfig"; mkdir -p "$NC"; ( cd "$NC" && git init -q )
run_hook $H "$(bash_in "npm test" "" "$NC")" "$NC"; expect_silent "設定が無ければ通す"

echo "[commands.test が複数語のランナー]"
V="$TMP_ROOT/vitest"; make_repo "$V" '  enforce_test_scope: "block"' "npx vitest run"
run_hook $H "$(bash_in "npx vitest run" "" "$V")" "$V"; expect_deny "全件: npx vitest run"
run_hook $H "$(bash_in "npx vitest run src/a.test.ts" "" "$V")" "$V"; expect_silent "通す: npx vitest run src/a.test.ts"

finish
