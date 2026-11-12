#!/bin/bash
# worktree-lock.sh（宣言）と worktree-lock-guard.sh（突合）の振る舞いテスト。
#   bash test/worktree-lock.test.sh
set -u
. "$(dirname "$0")/lib/hook-common.sh"
H=worktree-lock-guard.sh
LOCK="$REPO_ROOT/packages/core/skills/auto-implement/scripts/worktree-lock.sh"

echo "worktree-lock tests"

M="$TMP_ROOT/main"; make_repo "$M" '  enforce_worktree_lock: "block"'
git -C "$M" worktree add -q -b claude/a "$M/.claude/worktrees/a" 2>/dev/null
git -C "$M" worktree add -q -b claude/b "$TMP_ROOT/b" 2>/dev/null
A="$M/.claude/worktrees/a"
WB="$TMP_ROOT/b"
SCRATCH="$TMP_ROOT/scratch"; mkdir -p "$SCRATCH"

edit() { hook_input Edit "{\"file_path\":\"$1\"}" "$2" "$3" "${4:-sess-1}"; }
bash_in() { hook_input Bash "$(jq -cn --arg c "$1" '{command:$c}')" "$2" "$3" "${4:-sess-1}"; }

echo "[宣言なし]"
run_hook $H "$(edit "$WB/src/a.ts" implementer "$A")" "$A"; expect_silent "宣言の無いセッションは通す"

echo "[宣言]"
OUT=$("$LOCK" lock 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok "セッション ID が無ければ宣言しない" || ng "セッション ID が無ければ宣言しない"
OUT=$("$LOCK" lock --session '../x' 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok "使えない文字のセッション ID は拒否する" || ng "使えない文字のセッション ID は拒否する"
OUT=$(cd "$A" && CLAUDE_CODE_SESSION_ID=sess-1 "$LOCK" lock --allow "$SCRATCH" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok "環境変数のセッション ID で宣言できる" || ng "環境変数のセッション ID で宣言できる"
F="$M/.git/stdd-worktree-lock/sess-1"
grep -qx "root=$A" "$F" && ok "宣言は共通ディレクトリに置く" || { OUT=$(cat "$F" 2>&1); ng "宣言は共通ディレクトリに置く"; }
OUT=$(cd "$A" && "$LOCK" status --session sess-1 2>&1); expect_out_contains "status で宣言を表示する" "root=$A"
OUT=$(cd "$M" && "$LOCK" lock --session sess-main 2>&1); expect_out_contains "メインの作業ツリーを宣言すると警告する" "警告"

echo "[書き込み]"
run_hook $H "$(edit "$A/src/a.ts" implementer "$A")" "$A"; expect_silent "宣言した作業ツリーの中は通す"
run_hook $H "$(edit "src/a.ts" implementer "$A")" "$A"; expect_silent "相対パスは cwd から解決する"
run_hook $H "$(edit "$SCRATCH/x.txt" implementer "$A")" "$A"; expect_silent "--allow のディレクトリは通す"
run_hook $H "$(edit "$WB/src/a.ts" implementer "$A")" "$A"; expect_deny "別の作業ツリーへの書き込みは拒否する"
expect_out_contains "メッセージに対処法が入る" "cd $A &&"
run_hook $H "$(edit "$M/src/a.ts" implementer "$A")" "$A"; expect_deny "メインの作業ツリーへの書き込みは拒否する"
run_hook $H "$(edit "$A/../b/x" implementer "$A")" "$A"; expect_deny ".. で外へ出る形は拒否する"
run_hook $H "$(edit "$WB/src/a.ts" "" "$A")" "$A"; expect_silent "メインのエージェントは対象外"
run_hook $H "$(edit "$WB/src/a.ts" implementer "$A" sess-2)" "$A"; expect_silent "別のセッションには効かない"
P=$(jq -cn --arg c $'*** Begin Patch\n*** Update File: src/a.ts\n*** End Patch' '{command:$c}')
run_hook $H "$(hook_input apply_patch "$P" implementer "$WB")" "$A"; expect_deny "apply_patch は cwd から宛先を解決する"

echo "[宣言の中に入れ子の作業ツリー]"
OUT=$("$LOCK" lock --root "$M" --session sess-3 2>&1)
run_hook $H "$(edit "$M/src/a.ts" implementer "$M" sess-3)" "$M"; expect_silent "メインを宣言したらメインの中は通す"
run_hook $H "$(edit "$A/src/a.ts" implementer "$M" sess-3)" "$M"; expect_deny "メインの中に入れ子の作業ツリーは外側とみなす"

echo "[Bash]"
run_hook $H "$(bash_in "npm test" implementer "$A")" "$A"; expect_silent "cwd が宣言の中なら通す"
run_hook $H "$(bash_in "npm test" implementer "$M")" "$M"; expect_deny "cwd が宣言の外なら拒否する"
run_hook $H "$(bash_in "cd $A && npm test" implementer "$M")" "$M"; expect_silent "先頭の cd で宣言の中へ入れば通す"
run_hook $H "$(bash_in "cd \"$WB\" && npm test" implementer "$A")" "$A"; expect_deny "先頭の cd で外へ出れば拒否する"
run_hook $H "$(bash_in "git -C $WB checkout -- ." implementer "$A")" "$A"; expect_deny "別の作業ツリーの絶対パスを含めば拒否する"
run_hook $H "$(bash_in "ls /usr/bin" implementer "$A")" "$A"; expect_silent "作業ツリーでない絶対パスは通す"

echo "[強さ]"
W="$TMP_ROOT/w"; make_repo "$W" ""
git -C "$W" worktree add -q -b claude/c "$TMP_ROOT/wc" 2>/dev/null
OUT=$("$LOCK" lock --root "$TMP_ROOT/wc" --session sess-4 2>&1)
run_hook $H "$(edit "$W/src/a.ts" implementer "$TMP_ROOT/wc" sess-4)" "$TMP_ROOT/wc"; expect_warn "既定の warn では知らせるだけ"
OUT=$("$LOCK" unlock --root "$TMP_ROOT/wc" --session sess-4 2>&1)
run_hook $H "$(edit "$W/src/a.ts" implementer "$TMP_ROOT/wc" sess-4)" "$TMP_ROOT/wc"; expect_silent "unlock の後は通す"

finish
