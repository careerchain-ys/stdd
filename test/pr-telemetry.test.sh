#!/bin/bash
# pr-telemetry.sh（create-pr 同梱）の振る舞いテスト。偽の gh と jq を使う。
#
#   bash test/pr-telemetry.test.sh
#
# このディレクトリ（test/）は配布対象外。

set -u
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$REPO_ROOT/packages/core/skills/create-pr/scripts/pr-telemetry.sh"
. "$REPO_ROOT/test/lib/common.sh"

run() { OUT=$(cd "$REPO_DIR" && bash "$SCRIPT" "$@" 2>&1); RC=$?; }
EV() { printf '%s/.git/stdd-telemetry/claude__test.tsv' "$REPO_DIR"; }
head_sha() { git -C "$REPO_DIR" rev-parse HEAD; }

# PR の fixture（head は手元の HEAD）。$1 = 既存のコメント（JSON 配列）
pr_fixture() {
    jq -n --arg h "${2:-$(head_sha)}" --argjson c "${1:-[]}" \
        '{number: 12, headRefOid: $h, baseRefName: "main", additions: 30, deletions: 5, changedFiles: 3, commits: [{}, {}], comments: $c}' \
        > "$FAKE_GH/pr-view.json"
}
# 投稿された payload（最後の pr comment の JSON）
posted() { awk '/^=== pr comment/{buf=""; next} {buf = buf $0 "\n"} END {printf "%s", buf}' "$FAKE_GH/bodies.log" | sed -n '/^```json$/,/^```$/p' | sed '1d;$d'; }

echo "== mark"
new_case mark
run mark nope start
assert_rc "定義に無い工程は拒否する" 1
run mark spec middle
assert_rc "start / end 以外は拒否する" 1
STDD_NOW=1000 run mark spec start
assert_rc "記録できる" 0
assert_file_contains "作業ツリーの外（git の共通ディレクトリ）に記録する" "$(EV)" "1000	start	spec"
( cd "$REPO_DIR" && git status --porcelain ) | grep -q stdd-telemetry && ng "記録はコミットの対象にならない" || ok "記録はコミットの対象にならない"
git -C "$REPO_DIR" worktree add -q "$TMP_ROOT/mark/wt" -b claude/other 2>/dev/null
OUT=$(cd "$TMP_ROOT/mark/wt" && STDD_NOW=2000 bash "$SCRIPT" mark plan start 2>&1); RC=$?
assert_file_contains "別の worktree からも同じ置き場（ブランチ別のファイル）に書く" "$REPO_DIR/.git/stdd-telemetry/claude__other.tsv" "2000	start	plan"

echo "== post: レビューの記録も免除も無い"
new_case norecord
pr_fixture
run post
assert_rc "レビューの記録も免除も無ければ止まる" 1
assert_contains "対処を示す" "--review-rounds"
assert_file_not_contains "投稿しない" "$FAKE_GH/calls.log" "pr comment"

echo "== post: 記録から集計する"
new_case post
pr_fixture
mkdir -p "$REPO_DIR/.git/stdd-telemetry"
# 最初のコミットは STDD_NOW - 3600 秒。記録はそれより 1800 秒前から始まる
B=$((STDD_NOW - 5400))
cat > "$(EV)" <<TSV
$B	start	spec
$((B + 600))	end	spec
$((B + 700))	start	implement
$((B + 1300))	end	implement
$((B + 1400))	start	review
$((B + 1700))	end	review
$((B + 1800))	start	review
$((B + 1900))	end	review
$((B + 2000))	start	qa
$((B + 2100))	feedback-filed	42
$((B + 2200))	feedback-recur	7
$((B + 2300))	feedback-triage	1
TSV
run post
assert_rc "投稿と確認が成功する" 0
assert_contains "読み直して確かめる" "pr-telemetry verify OK"
assert_not_contains "棚卸しの記録があれば警告しない" "警告"
P=$(posted)
OUT="$P"
[ "$(printf '%s' "$P" | jq -r .schema)" = "stdd-telemetry/1" ] && ok "schema の版を名乗る" || ng "schema の版を名乗る"
[ "$(printf '%s' "$P" | jq -r .head_sha)" = "$(head_sha)" ] && ok "head の SHA を持つ" || ng "head の SHA を持つ"
[ "$(printf '%s' "$P" | jq -c .size)" = '{"files":3,"additions":30,"deletions":5,"commits":2}' ] && ok "規模は PR から採る" || ng "規模は PR から採る"
[ "$(printf '%s' "$P" | jq -c .duration_min.steps)" = '{"spec":10,"implement":10,"review":7}' ] && ok "完了した工程だけを分で集計する（終わっていない qa は含めない）" || ng "工程別の所要"
[ "$(printf '%s' "$P" | jq -r .duration_min.lead_time)" = "90" ] && ok "所要は最初の記録から" || ng "所要は最初の記録から"
[ "$(printf '%s' "$P" | jq -c .review)" = '{"rounds":2,"exempt":null}' ] && ok "レビュー回数は完了した review の組の数" || ng "レビュー回数"
[ "$(printf '%s' "$P" | jq -c .feedback)" = '{"filed":1,"recurred":1,"skipped_by_cap":1}' ] && ok "棚卸しの件数を持つ" || ng "棚卸しの件数"
assert_file_contains "目印のコメントを付ける" "$FAKE_GH/bodies.log" "<!-- stdd-telemetry -->"

echo "== post: 免除"
new_case exempt
pr_fixture
run post --exempt hurry
assert_rc "列挙に無い区分は拒否する" 1
run post --exempt user_waived
assert_rc "免除の申告で投稿できる" 0
assert_contains "棚卸しの記録が無ければ警告する" "フィードバックの棚卸しの記録がありません"
OUT=$(posted)
[ "$(printf '%s' "$OUT" | jq -c .review)" = '{"rounds":0,"exempt":"user_waived"}' ] && ok "免除の区分を持つ" || ng "免除の区分"
[ "$(printf '%s' "$OUT" | jq -c .feedback)" = 'null' ] && ok "棚卸しをしていなければ feedback は null" || ng "feedback は null"
[ "$(printf '%s' "$OUT" | jq -c .duration_min.steps)" = 'null' ] && ok "工程の記録が無ければ steps は null（0 にしない）" || ng "steps は null"
[ "$(printf '%s' "$OUT" | jq -r .duration_min.lead_time)" = 'null' ] && ok "起点が無ければ所要は null" || ng "所要は null"
run post --exempt typo_format_only --review-rounds 1
assert_rc "レビューをした PR に免除は使えない" 1

echo "== post: --review-rounds"
new_case rounds
pr_fixture
run post --review-rounds x
assert_rc "回数でない値は拒否する" 1
run post --review-rounds 3
assert_rc "回数の申告で投稿できる" 0
OUT=$(posted); [ "$(printf '%s' "$OUT" | jq -r .review.rounds)" = 3 ] && ok "申告した回数を持つ" || ng "申告した回数"

echo "== post: push していない"
new_case unpushed
pr_fixture '[]' 0000000000000000000000000000000000000000
run post --review-rounds 1
assert_rc "手元の HEAD が PR の head と違えば止まる" 1
assert_contains "push を促す" "push してから"

echo "== verify"
new_case verify
H=$(head_sha)
PAY="{\"schema\":\"stdd-telemetry/1\",\"head_sha\":\"$H\",\"feedback\":{\"filed\":0}}"
BODY=$(printf '<!-- stdd-telemetry -->\n```json\n%s\n```\n' "$PAY")
pr_fixture '[]'
run verify
assert_rc "payload が無ければ失敗する" 1
pr_fixture "$(jq -n --arg b "$BODY" '[{authorAssociation:"NONE", body:$b}]')"
run verify
assert_rc "リポジトリのメンバー以外の payload は数えない" 1
OLD=$(printf '<!-- stdd-telemetry -->\n```json\n{"schema":"stdd-telemetry/1","head_sha":"abc","feedback":null}\n```\n')
pr_fixture "$(jq -n --arg b "$OLD" '[{authorAssociation:"OWNER", body:$b}]')"
run verify
assert_rc "古い断面の payload しか無ければ失敗する" 1
pr_fixture "$(jq -n --arg b "$OLD" --arg c "$BODY" '[{authorAssociation:"OWNER", body:$b}, {authorAssociation:"MEMBER", body:"関係ないコメント"}, {authorAssociation:"COLLABORATOR", body:$c}]')"
run verify
assert_rc "head の断面の payload があれば成功する" 0

echo "== telemetry.enabled: false"
new_case disabled
write_config 'telemetry:
  enabled: false'
run post
assert_rc "無効なら何もせず成功する" 0
[ ! -s "$FAKE_GH/calls.log" ] && ok "gh を呼ばない" || ng "gh を呼ばない"
run mark spec start
[ ! -f "$(EV)" ] && ok "無効なら記録もしない" || ng "無効なら記録もしない"

finish
