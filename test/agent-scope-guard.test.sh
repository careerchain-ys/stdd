#!/bin/bash
# agent-scope-guard.sh の振る舞いテスト。
#   bash test/agent-scope-guard.test.sh
set -u
. "$(dirname "$0")/lib/hook-common.sh"
H=agent-scope-guard.sh

echo "agent-scope-guard.sh tests"

R="$TMP_ROOT/warn"; make_repo "$R" ""
B="$TMP_ROOT/block"; make_repo "$B" '  enforce_agent_scope: "block"'
O="$TMP_ROOT/off"; make_repo "$O" '  enforce_agent_scope: "off"'

edit() { hook_input Edit "{\"file_path\":\"$1\"}" "$2" "$3"; }
bash_in() { hook_input Bash "$(jq -cn --arg c "$1" '{command:$c}')" "$2" "$3"; }

echo "[対象の絞り込み]"
run_hook $H "$(edit "$R/src/app.ts" "" "$R")" "$R"; expect_silent "メインのエージェントは対象外"
run_hook $H "$(edit "$R/src/app.ts" qa-engineer "$R")" "$R"; expect_silent "qa-engineer は対象外"
run_hook $H "$(edit "$R/docs/app/x/REQUIREMENTS.md" requirements-writer "$R")" "$R"; expect_silent "配っていない旧 writer の名前は対象外"

echo "[reviewer の書き込み]"
run_hook $H "$(edit "$R/src/app.ts" code-reviewer "$R")" "$R"; expect_warn "warn で知らせる"
expect_out_contains "メッセージに宛先が入る" "src/app.ts"
expect_out_contains "メッセージに対処法が入る" "レビュー結果として返して"
run_hook $H "$(edit "$B/docs/app/x/REQUIREMENTS.md" requirements-reviewer "$B")" "$B"; expect_deny "設計書でも書けない"
run_hook $H "$(edit "docs/app/x/TECH_DESIGN.md" tech-specs-reviewer "$B")" "$B"; expect_deny "相対パスも見る"
run_hook $H "$(edit "$O/src/app.ts" test-reviewer "$O")" "$O"; expect_silent "off では何もしない"
run_hook $H "$(hook_input NotebookEdit "{\"notebook_path\":\"$B/src/a.ipynb\"}" code-reviewer "$B")" "$B"; expect_deny "NotebookEdit も見る"
P=$(jq -cn --arg c $'*** Begin Patch\n*** Update File: docs/app/x/REQUIREMENTS.md\n*** End Patch' '{command:$c}')
run_hook $H "$(hook_input apply_patch "$P" requirements-reviewer "$B")" "$B"; expect_deny "apply_patch も見る"
run_hook $H "$(bash_in "git diff main" code-reviewer "$B")" "$B"; expect_silent "読み取りのシェルは通す"
run_hook $H "$(edit "$B/src/app.ts" code-reviewer-security "$B")" "$B"; expect_deny "agent の名前で始まるチームのメンバーも見る"
run_hook $H "$(bash_in "node -e 1" tech-specs-reviewer-common "$B")" "$B"; expect_deny "メンバーのシェルも見る"
run_hook $H "$(edit "$B/src/app.ts" code-reviewers "$B")" "$B"; expect_silent "「-」で続かない似た名前は対象外"

echo "[Bash の許可一覧]"
for c in "ls docs" "cat docs/app/x/REQUIREMENTS.md" "grep -rn 'UC-' docs" "grep -n 'end\$' a.md" "git log --oneline -20" \
         "git diff main...HEAD" "find docs -name '*.md'" "rg -n UC- docs" "pwd" "bash .claude/hooks/trace-audit.sh --changed docs/a.md"; do
    run_hook $H "$(bash_in "$c" tech-specs-reviewer "$B")" "$B"; expect_silent "許可: $c"
done
for c in "git log && rm -rf src" "git log & node -e 1" "cat a | sort -o b" "echo x > docs/a.md" "sed -i s/a/b/ docs/a.md" \
         "node -e 1" "git diff --output=/tmp/x" "git -c core.pager=sh log" "git checkout -- ." "find . -delete" \
         "find . -exec rm {} +" "rg --pre sh x" "cat \$(ls)" "cat \`ls\`" "cat \$HOME/x" "bash docs/run.sh" "sort -o x y" \
         $'ls\nrm x' "ls \\" "git grep -O x"; do
    run_hook $H "$(bash_in "$c" tech-specs-reviewer "$B")" "$B"; expect_deny "拒否: $c"
done
run_hook $H "$(bash_in "node -e 1" tech-specs-reviewer "$R")" "$R"; expect_warn "warn では知らせるだけ"

echo "[フェイルオープン]"
N="$TMP_ROOT/noconfig"; mkdir -p "$N"; ( cd "$N" && git init -q )
run_hook $H "$(edit "$N/src/a.ts" code-reviewer "$N")" "$N"; expect_silent "設定が無ければ通す"
run_hook $H "not json" "$B"; expect_silent "入力が読めなければ通す"

finish
