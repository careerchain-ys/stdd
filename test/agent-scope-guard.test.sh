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
run_hook $H "$(edit "$R/src/app.ts" implementer "$R")" "$R"; expect_silent "implementer は対象外"
run_hook $H "$(edit "$R/src/app.ts" qa-engineer "$R")" "$R"; expect_silent "qa-engineer は対象外"

echo "[writer の書き込み]"
run_hook $H "$(edit "$R/docs/app/login/REQUIREMENTS.md" requirements-writer "$R")" "$R"; expect_silent "担当の設計書は通す"
run_hook $H "$(edit "docs/app/login/sub/TECH_DESIGN.md" tech-specs-writer "$R")" "$R"; expect_silent "相対パス・入れ子の機能パスも通す"
run_hook $H "$(edit "$R/docs/common/REQUIREMENTS.md" requirements-writer "$R")" "$R"; expect_silent "common の設計書は通す"
run_hook $H "$(edit "$R/plans/2026-01-01.md" plan-writer "$R")" "$R"; expect_silent "PLAN の場所（コメントつきの値）も通す"
run_hook $H "$(edit "$R/src/app.ts" requirements-writer "$R")" "$R"; expect_warn "範囲外は warn で知らせる"
expect_out_contains "メッセージに宛先が入る" "src/app.ts"
expect_out_contains "メッセージに対処法が入る" "呼び出し元に依頼"
run_hook $H "$(edit "$R/.stdd.config.yml" requirements-writer "$R")" "$R"; expect_warn "設定ファイルは範囲外"
run_hook $H "$(edit "$R/docs/../src/app.ts" requirements-writer "$R")" "$R"; expect_warn ".. で外へ出る形は範囲外"
run_hook $H "$(edit "$R/docs/README.md" requirements-writer "$R")" "$R"; expect_warn "docs 直下（テンプレートの外）は範囲外"
run_hook $H "$(edit "$B/src/app.ts" requirements-writer "$B")" "$B"; expect_deny "block では拒否する"
run_hook $H "$(edit "$O/src/app.ts" requirements-writer "$O")" "$O"; expect_silent "off では何もしない"
run_hook $H "$(hook_input NotebookEdit "{\"notebook_path\":\"$B/src/a.ipynb\"}" plan-writer "$B")" "$B"; expect_deny "NotebookEdit も見る"

echo "[apply_patch]"
P=$(jq -cn --arg c $'*** Begin Patch\n*** Update File: docs/app/x/REQUIREMENTS.md\n*** Add File: src/a.ts\n*** End Patch' '{command:$c}')
run_hook $H "$(hook_input apply_patch "$P" requirements-writer "$B")" "$B"; expect_deny "範囲外が 1 件でもあれば拒否する"
P=$(jq -cn --arg c $'*** Begin Patch\n*** Update File: docs/app/x/REQUIREMENTS.md\n*** End Patch' '{command:$c}')
run_hook $H "$(hook_input apply_patch "$P" requirements-writer "$B")" "$B"; expect_silent "範囲内だけなら通す"

echo "[reviewer]"
run_hook $H "$(edit "$B/docs/app/x/REQUIREMENTS.md" requirements-reviewer "$B")" "$B"; expect_deny "reviewer は設計書でも書けない"
run_hook $H "$(bash_in "git diff main" code-reviewer "$B")" "$B"; expect_silent "reviewer の読み取りは通す"

echo "[Bash の許可一覧]"
for c in "ls docs" "cat docs/app/x/REQUIREMENTS.md" "grep -rn 'UC-' docs" "grep -n 'end\$' a.md" "git log --oneline -20" \
         "git diff main...HEAD" "find docs -name '*.md'" "rg -n UC- docs" "pwd" "bash .claude/hooks/trace-audit.sh --changed docs/a.md"; do
    run_hook $H "$(bash_in "$c" tech-specs-writer "$B")" "$B"; expect_silent "許可: $c"
done
for c in "git log && rm -rf src" "git log & node -e 1" "cat a | sort -o b" "echo x > docs/a.md" "sed -i s/a/b/ docs/a.md" \
         "node -e 1" "git diff --output=/tmp/x" "git -c core.pager=sh log" "git checkout -- ." "find . -delete" \
         "find . -exec rm {} +" "rg --pre sh x" "cat \$(ls)" "cat \`ls\`" "cat \$HOME/x" "bash docs/run.sh" "sort -o x y" \
         $'ls\nrm x' "ls \\" "git grep -O x"; do
    run_hook $H "$(bash_in "$c" tech-specs-writer "$B")" "$B"; expect_deny "拒否: $c"
done
run_hook $H "$(bash_in "node -e 1" tech-specs-writer "$R")" "$R"; expect_warn "warn では知らせるだけ"

echo "[フェイルオープン]"
N="$TMP_ROOT/noconfig"; mkdir -p "$N"; ( cd "$N" && git init -q )
run_hook $H "$(edit "$N/src/a.ts" requirements-writer "$N")" "$N"; expect_silent "設定が無ければ通す"
run_hook $H "not json" "$B"; expect_silent "入力が読めなければ通す"

finish
