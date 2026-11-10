#!/bin/bash
# 作業モード（緊急モード）の振る舞いテスト。
#   - hooks/work-mode-prompt.sh   ユーザーの申し出の記録（UserPromptSubmit）
#   - choosing-work-mode/scripts/work-mode.sh   宣言・確認・解除
#   - hooks/pre-push-check.sh     緊急モードの枝では検査の失敗を警告にとどめる
#
#   bash test/work-mode.test.sh
#
# このディレクトリ（test/）は配布対象外。

set -u
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOOK="$REPO_ROOT/packages/core/hooks/work-mode-prompt.sh"
WM="$REPO_ROOT/packages/core/skills/choosing-work-mode/scripts/work-mode.sh"
PREPUSH="$REPO_ROOT/packages/core/hooks/pre-push-check.sh"
. "$REPO_ROOT/test/lib/common.sh"

STATE() { printf '%s/.git/stdd-work-mode' "$REPO_DIR"; }
prompt() { OUT=$(cd "$REPO_DIR" && jq -n --arg p "$1" '{session_id: "s", cwd: ".", prompt: $p}' | bash "$HOOK" 2>&1); RC=$?; }
wm() { OUT=$(cd "$REPO_DIR" && bash "$WM" "$@" 2>&1); RC=$?; }

echo "== フック: ユーザーの申し出の記録"
new_case hook
prompt "ログインの不具合を急いで直して"
assert_rc "言及が無くても発言は止めない" 0
[ -f "$(STATE)/request" ] && ng "言及が無ければ記録しない" || ok "言及が無ければ記録しない"
assert_not_contains "言及が無ければ何も出力しない" "STDD:"
prompt "緊急モードで、ログインの不具合を
直して"
assert_rc "言及があっても発言は止めない" 0
assert_file_contains "申し出の時刻を記録する" "$(STATE)/request" "requested_at=$STDD_NOW"
assert_file_contains "発言の抜粋を 1 行で記録する" "$(STATE)/request" "request=緊急モードで、ログインの不具合を 直して"
assert_contains "skill に従うよう文脈を出す" "choosing-work-mode"
( cd "$REPO_DIR" && git status --porcelain ) | grep -q stdd-work-mode && ng "記録はコミットの対象にならない" || ok "記録はコミットの対象にならない"
rm -f "$(STATE)/request"
# JSON の \uXXXX エスケープ（jq があれば jq が戻し、無ければエスケープ表記のまま照合する）
OUT=$(cd "$REPO_DIR" && printf '%s' '{"prompt":"\u7dca\u6025\u30e2\u30fc\u30c9\u3067"}' | bash "$HOOK" 2>&1); RC=$?
[ -f "$(STATE)/request" ] && ok "\\uXXXX にエスケープされた言及も拾う" || ng "\\uXXXX にエスケープされた言及も拾う"
write_config "emergency_mode:
  enabled: false"
rm -f "$(STATE)/request"
prompt "緊急モードで"
[ -f "$(STATE)/request" ] && ng "emergency_mode.enabled が false なら記録しない" || ok "emergency_mode.enabled が false なら記録しない"

echo "== 宣言: ユーザーの申し出が無ければ宣言しない"
new_case declare
wm declare --reason "障害対応"
assert_rc "申し出の記録が無ければ拒否する" 1
assert_contains "エージェントの判断では宣言しないと伝える" "エージェントの判断では宣言しません"
wm active
assert_rc "宣言していなければ無効" 1
wm status
assert_contains "宣言していなければ通常モード" "通常モード"

prompt "緊急モードで進めて"
wm declare
assert_rc "理由が無ければ拒否する" 1
STDD_NOW=$((STDD_NOW + 121 * 60)) wm declare --reason "障害対応"
assert_rc "有効期限を過ぎた申し出では宣言しない" 1
assert_contains "古すぎると伝える" "古すぎます"
STDD_NOW=$((STDD_NOW + 60 * 60)) wm declare --reason "本番の障害対応
（今日中）"
assert_rc "有効期限内の申し出で宣言できる" 0
assert_file_contains "理由を 1 行で記録する" "$(STATE)/claude__test" "reason=本番の障害対応 （今日中）"
assert_file_contains "申し出の抜粋を宣言に残す" "$(STATE)/claude__test" "request=緊急モードで進めて"
[ -f "$(STATE)/request" ] && ng "宣言に使った申し出は消す" || ok "宣言に使った申し出は消す"
wm active
assert_rc "宣言したブランチで有効" 0
[ -z "$OUT" ] && ok "active は何も出力しない" || ng "active は何も出力しない"
wm status
assert_contains "status は緊急モードと理由を出す" "緊急モード（ブランチ claude/test"

git -C "$REPO_DIR" worktree add -q "$TMP_ROOT/declare/wt" -b claude/other 2>/dev/null
OUT=$(cd "$TMP_ROOT/declare/wt" && bash "$WM" active 2>&1); RC=$?
assert_rc "別のブランチには効かない" 1
OUT=$(cd "$TMP_ROOT/declare/wt" && bash "$WM" declare --reason "x" 2>&1); RC=$?
assert_rc "申し出 1 回で宣言できるのは 1 回" 1

printf 'mode=emergency\nbranch=claude/other\nreason=x\ndeclared_at=1\n' > "$(STATE)/claude__test"
wm active
assert_rc "中のブランチ名が違う宣言は無効" 1
printf 'mode=emergency\nbranch=claude/test\nreason=x\ndeclared_at=abc\n' > "$(STATE)/claude__test"
wm active
assert_rc "宣言時刻が読めない宣言は無効" 1
printf 'mode=emergency\nbranch=claude/test\nreason=x\ndeclared_at=1\n' > "$(STATE)/claude__test"
wm active
assert_rc "欄がそろった宣言は有効" 0
write_config "emergency_mode:
  enabled: false"
wm active
assert_rc "emergency_mode.enabled が false なら宣言があっても無効" 1
rm -f "$REPO_DIR/.stdd.config.yml"

wm clear
assert_rc "解除できる" 0
wm active
assert_rc "解除したら無効" 1
wm clear
assert_contains "宣言が無くても解除は失敗しない" "宣言はありません"

echo "== 宣言: 主ブランチ・設定"
new_case primary
git -C "$REPO_DIR" checkout -q main
prompt "緊急モードで"
wm declare --reason "x"
assert_rc "主ブランチでは宣言しない" 1
assert_contains "主ブランチと伝える" "主ブランチ"
git -C "$REPO_DIR" checkout -q claude/test
write_config "emergency_mode:
  request_ttl_minutes: 5"
STDD_NOW=$((STDD_NOW + 6 * 60)) wm declare --reason "x"
assert_rc "request_ttl_minutes で有効期限を変えられる" 1
wm nope
assert_rc "知らないコマンドは拒否する" 1

echo "== pre-push: 緊急モードでは検査の失敗を警告にとどめる"
new_case prepush
(
    cd "$REPO_DIR" || exit 1
    git init -q --bare "$TMP_ROOT/prepush/remote.git"
    git remote add origin "$TMP_ROOT/prepush/remote.git"
    git push -q origin main 2>/dev/null
    git fetch -q origin
    mkdir -p .claude/skills/choosing-work-mode/scripts
    cp "$WM" .claude/skills/choosing-work-mode/scripts/work-mode.sh
    echo y > app.txt
    git add app.txt && git commit -q -m change
)
cat > "$REPO_DIR/.stdd.config.yml" <<'YML'
version: 1
project:
  name: "tmp"
  primary_branch: "main"
commands:
  test: "false"
YML
push() { OUT=$(cd "$REPO_DIR" && printf '%s' '{"tool_input":{"command":"git push origin claude/test"}}' | bash "$PREPUSH" 2>&1); RC=$?; }
push
assert_rc "通常モードではテストが失敗したら push を止める" 2
prompt "緊急モードで"
wm declare --reason "障害対応"
push
assert_rc "緊急モードではテストが失敗しても push を止めない" 0
assert_contains "緊急モードであることを出す" "緊急モードのブランチです"
assert_contains "テストは実行して失敗を伝える" "テスト失敗"
assert_contains "PR 本文に残すよう促す" "赤のまま残した検査"

finish
