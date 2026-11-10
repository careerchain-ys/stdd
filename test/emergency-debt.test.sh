#!/bin/bash
# emergency-debt.sh（settling-emergency-debt 同梱）の振る舞いテスト。偽の gh と jq を使う。
#
#   bash test/emergency-debt.test.sh
#
# このディレクトリ（test/）は配布対象外。

set -u
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$REPO_ROOT/packages/core/skills/settling-emergency-debt/scripts/emergency-debt.sh"
. "$REPO_ROOT/test/lib/common.sh"

run() { OUT=$(cd "$REPO_DIR" && bash "$SCRIPT" "$@" 2>&1); RC=$?; }
MARK() { printf '<!-- stdd-emergency-debt: %s -->' "$1"; }

echo "== record: 新しい機能は issue を作る"
new_case create
echo '[]' > "$FAKE_GH/issue-list.json"
echo '{"number": 12}' > "$FAKE_GH/pr-view.json"
run record
assert_rc "--feature が無ければ拒否する" 1
run record --feature applies --note "e2e を実ブラウザで通していない
認可のテストが未レビュー"
assert_rc "記録できる" 0
assert_file_contains "ラベルを作成・更新する" "$FAKE_GH/calls.log" "label create emergency-debt"
assert_file_contains "機能キーの題名で issue を作る" "$FAKE_GH/calls.log" "issue create --title 緊急モードの負債: applies --label emergency-debt"
assert_file_contains "本文に機能キーの目印を置く" "$FAKE_GH/bodies.log" "$(MARK applies)"
assert_file_contains "現在のブランチの PR を由来 PR として 1 行で書く" "$FAKE_GH/bodies.log" "- 由来 PR #12（2026-01-01 記録）: e2e を実ブラウザで通していない 認可のテストが未レビュー"

echo "== record: 既存の issue には追記し、同じ PR は二度積まない"
new_case append
jq -n --arg m "$(MARK applies)" '[{number: 7, body: ("x\n" + $m)}, {number: 8, body: "<!-- stdd-emergency-debt: other -->"}]' > "$FAKE_GH/issue-list.json"
jq -n --arg m "$(MARK applies)" '{body: ($m + "\n- 由来 PR #10（2026-01-01 記録）: a"), comments: [{body: "- 由来 PR #11（2026-01-02 記録）: b"}]}' > "$FAKE_GH/issue-view-7.json"
run record --feature applies --pr 13
assert_rc "追記できる" 0
assert_file_contains "機能キーの issue にコメントする" "$FAKE_GH/calls.log" "issue comment 7"
assert_file_not_contains "issue は新しく作らない" "$FAKE_GH/calls.log" "issue create"
assert_file_contains "メモが無ければ PR 本文を参照するよう書く" "$FAKE_GH/bodies.log" "- 由来 PR #13（2026-01-01 記録）: （後追いのメモなし"
: > "$FAKE_GH/calls.log"
run record --feature applies --pr 11
assert_rc "記録済みの PR は成功として扱う" 0
assert_contains "記録済みと伝える" "記録済み"
assert_file_not_contains "記録済みならコメントしない" "$FAKE_GH/calls.log" "issue comment"
run record --feature applies --pr abc
assert_rc "番号でない PR は拒否する" 1

echo "== record: 複数の機能"
new_case multi
jq -n --arg m "$(MARK applies)" '[{number: 7, body: $m}]' > "$FAKE_GH/issue-list.json"
echo '{"body": "", "comments": []}' > "$FAKE_GH/issue-view-7.json"
run record --feature "applies, jobs" --pr 20
assert_rc "カンマ区切りで複数の機能に積める" 0
assert_file_contains "既存の機能には追記する" "$FAKE_GH/calls.log" "issue comment 7"
assert_file_contains "新しい機能には issue を作る" "$FAKE_GH/calls.log" "緊急モードの負債: jobs"

echo "== list / entries"
new_case read
jq -n '[{number: 7, title: "緊急モードの負債: applies"}]' > "$FAKE_GH/issue-list.json"
run list
assert_contains "open な負債 issue を一覧する" "#7	緊急モードの負債: applies"
assert_file_contains "ラベルで絞る" "$FAKE_GH/calls.log" "issue list --label emergency-debt --state open"
jq -n '{body: "- 由来 PR #10（2026-01-01 記録）: a\n- 由来 PR #11（2026-01-01 記録）: b", comments: [{body: "- 由来 PR #10（2026-01-03 記録）: 重複"}, {body: "関係ないコメント #99"}]}' > "$FAKE_GH/issue-view-7.json"
echo '{"state": "MERGED"}' > "$FAKE_GH/pr-view-10.json"
echo '{"state": "CLOSED"}' > "$FAKE_GH/pr-view-11.json"
run entries 7
assert_rc "読める" 0
assert_contains "由来 PR と状態を出す" "10	MERGED"
assert_contains "閉じた PR も状態つきで出す" "11	CLOSED"
[ "$(printf '%s\n' "$OUT" | grep -c '^10	')" -eq 1 ] && ok "同じ PR は 1 回だけ出す" || ng "同じ PR は 1 回だけ出す"
assert_not_contains "由来 PR の行以外は拾わない" "99"

echo "== close: 着手後に積まれた負債があれば閉じない"
new_case close
jq -n '{body: "- 由来 PR #10（2026-01-01 記録）: a\n- 由来 PR #11（2026-01-01 記録）: b", comments: [{body: "- 由来 PR #12（2026-01-05 記録）: c"}]}' > "$FAKE_GH/issue-view-7.json"
echo '{"state": "MERGED"}' > "$FAKE_GH/pr-view-10.json"
echo '{"state": "CLOSED"}' > "$FAKE_GH/pr-view-11.json"
echo '{"state": "OPEN"}' > "$FAKE_GH/pr-view-12.json"
run close 7 --handled 10
assert_rc "--settled-by が無ければ拒否する" 1
run close 7 --settled-by 30 --handled 10
assert_rc "対象に含めていない open な由来 PR があれば閉じない" 2
assert_contains "残っている PR を名前で示す" "#12(OPEN)"
assert_file_not_contains "閉じない" "$FAKE_GH/calls.log" "issue close"
run close 7 --settled-by 30 --handled 10,12
assert_rc "対象をすべて扱えば閉じる（マージされずに閉じた PR は数えない）" 0
assert_file_contains "解消した PR を添えて閉じる" "$FAKE_GH/calls.log" "issue close 7 --comment PR #30 で解消しました（対象の由来 PR: #10,#12）。"

echo "== 設定"
new_case config
write_config "emergency_mode:
  debt_label: \"urgent-debt\""
echo '[]' > "$FAKE_GH/issue-list.json"
run record --feature applies --pr 5
assert_file_contains "debt_label でラベルを変えられる" "$FAKE_GH/calls.log" "--label urgent-debt"
write_config "emergency_mode:
  enabled: false"
: > "$FAKE_GH/calls.log"
run record --feature applies --pr 5
assert_rc "emergency_mode.enabled が false なら何もしない" 0
[ -s "$FAKE_GH/calls.log" ] && ng "無効なら gh を呼ばない" || ok "無効なら gh を呼ばない"

finish
