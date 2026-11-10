#!/bin/bash
# collect.sh（measuring-dev-process 同梱）の振る舞いテスト。偽の gh と jq を使う。
#
#   bash test/collect.test.sh
#
# このディレクトリ（test/）は配布対象外。

set -u
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$REPO_ROOT/packages/core/skills/measuring-dev-process/scripts/collect.sh"
. "$REPO_ROOT/test/lib/common.sh"

run() { OUT=$(cd "$REPO_DIR" && bash "$SCRIPT" "$@" 2>&1); RC=$?; }

tel() {  # $1 = payload の JSON
    printf '<!-- stdd-telemetry -->\n**工程テレメトリ**\n\n```json\n%s\n```\n' "$1"
}

new_case collect
P1=$(tel '{"schema":"stdd-telemetry/1","pr":1,"head_sha":"a","size":{"files":2,"additions":10,"deletions":0,"commits":1},"duration_min":{"lead_time":30,"steps":{"spec":10,"review":5}},"review":{"rounds":1,"exempt":null},"feedback":{"filed":1,"recurred":0,"skipped_by_cap":0}}')
P1OLD=$(tel '{"schema":"stdd-telemetry/1","pr":1,"head_sha":"0","size":{"files":99,"additions":999,"deletions":0,"commits":1},"duration_min":{"lead_time":999,"steps":null},"review":{"rounds":9,"exempt":null},"feedback":null}')
P2=$(tel '{"schema":"stdd-telemetry/1","pr":2,"head_sha":"b","size":{"files":4,"additions":50,"deletions":10,"commits":3},"duration_min":{"lead_time":90,"steps":{"spec":20}},"review":{"rounds":3,"exempt":null},"feedback":{"filed":5,"recurred":2,"skipped_by_cap":3}}')
P3=$(tel '{"schema":"stdd-telemetry/1","pr":3,"head_sha":"c","size":{"files":1,"additions":1,"deletions":1,"commits":1},"duration_min":{"lead_time":null,"steps":null},"review":{"rounds":0,"exempt":"typo_format_only"},"feedback":null}')
FAKE=$(tel '{"schema":"stdd-telemetry/1","pr":4,"head_sha":"d","size":{"files":1,"additions":1,"deletions":0,"commits":1},"duration_min":{"lead_time":1,"steps":null},"review":{"rounds":1,"exempt":null},"feedback":null}')
jq -n --arg p1 "$P1" --arg p1old "$P1OLD" --arg p2 "$P2" --arg p3 "$P3" --arg fake "$FAKE" '[
  {number:1, mergedAt:"2026-01-02T00:00:00Z", author:{login:"a"}, comments:[{authorAssociation:"OWNER",body:$p1old},{authorAssociation:"OWNER",body:$p1}]},
  {number:2, mergedAt:"2026-01-03T00:00:00Z", author:{login:"b"}, comments:[{authorAssociation:"MEMBER",body:$p2}]},
  {number:3, mergedAt:"2026-01-04T00:00:00Z", author:{login:"a"}, comments:[{authorAssociation:"COLLABORATOR",body:$p3}]},
  {number:4, mergedAt:"2026-01-05T00:00:00Z", author:{login:"c"}, comments:[{authorAssociation:"NONE",body:$fake}]},
  {number:5, mergedAt:"2026-01-06T00:00:00Z", author:{login:"c"}, comments:[{authorAssociation:"OWNER",body:"```json\n{\"schema\":\"other/1\"}\n```"}]}
]' > "$FAKE_GH/pr-list-merged.json"

echo "== 引数"
run --since 2026-01-01
assert_rc "--until が無ければ拒否する" 1
run --since 2026/01/01 --until 2026-01-31
assert_rc "日付の形が違えば拒否する" 1

echo "== 集計"
run --since 2026-01-01 --until 2026-01-31
assert_rc "集計できる" 0
assert_file_contains "窓を GitHub の検索に渡す" "$FAKE_GH/calls.log" "merged:2026-01-01..2026-01-31"
assert_contains "母集団を数える" "マージ済み PR: 5 本（テレメトリあり 3 本）"
assert_contains "メンバー以外の payload と別の schema は数えない" "テレメトリの無い PR: #4, #5"
assert_contains "PR ごとに最後の payload を採る（規模）" "| 変更ファイル数 | 3 | 2 | 4 |"
assert_contains "測れない所要は数から外す" "| 所要（分。最初の記録か最初のコミットから投稿まで） | 2 | 30 | 90 |"
assert_contains "工程別の合計と中央値" "| spec | 2 | 30 | 10 | 20 |"
assert_contains "レビュー回数の分布" "| レビュー 3 回以上 | 1 |"
assert_contains "免除の区分" "| 免除: typo_format_only | 1 |"
assert_contains "棚卸しの有無" "棚卸しの記録あり: 2 本 ／ 記録なし: 1 本"
assert_contains "起票・再発・上限" "起票 6 件 ／ 再発コメント 2 件 ／ 上限で起票しなかったもの 3 件"
assert_contains "上限まで起票した PR" "上限（5 件）まで起票した PR: 1 本"
assert_not_contains "取得の上限に達していなければ警告しない" "--limit（"

run --since 2026-01-01 --until 2026-01-31 --limit 5
assert_contains "取得の上限に達したら警告する" "--limit（5）に達しました"

run --since 2026-01-01 --until 2026-01-31 --raw
assert_contains "--raw は見出し行を出す" "number	merged_at	author	has_telemetry"
assert_contains "--raw は PR ごとの行を出す" "2	2026-01-03T00:00:00Z	b	1	4	50	10	3	90	3		1	5	2	3	spec=20"

echo "== 開発フィードバック"
write_config 'feedback:
  labels:
    base: "process-fb"
    priority_high: "prio-high"
    priority_medium: "prio-medium"'
jq -n '[
  {number:10, title:"窓の中で起票", state:"OPEN", stateReason:null, createdAt:"2026-01-05T00:00:00Z", closedAt:null, labels:[{name:"process-fb"},{name:"prio-high"}],
   comments:[{authorAssociation:"OWNER",body:"再発 — 2026-01-10: a",createdAt:"2026-01-10T00:00:00Z"},{authorAssociation:"OWNER",body:"再発 — 2025-12-01: 窓の外",createdAt:"2025-12-01T00:00:00Z"},{authorAssociation:"NONE",body:"再発 — 外部",createdAt:"2026-01-11T00:00:00Z"}]},
  {number:11, title:"見送り", state:"CLOSED", stateReason:"NOT_PLANNED", createdAt:"2025-11-01T00:00:00Z", closedAt:"2026-01-20T00:00:00Z", labels:[{name:"process-fb"},{name:"prio-medium"}], comments:[]},
  {number:12, title:"反映", state:"CLOSED", stateReason:"COMPLETED", createdAt:"2026-01-02T00:00:00Z", closedAt:"2026-01-03T00:00:00Z", labels:[{name:"process-fb"},{name:"prio-medium"}], comments:[]},
  {number:13, title:"在庫", state:"OPEN", stateReason:null, createdAt:"2025-10-01T00:00:00Z", closedAt:null, labels:[{name:"process-fb"},{name:"prio-medium"}],
   comments:[{authorAssociation:"MEMBER",body:"再発 — x",createdAt:"2026-01-12T00:00:00Z"},{authorAssociation:"MEMBER",body:"再発 — y",createdAt:"2026-01-13T00:00:00Z"}]},
  {number:14, title:"優先度なし", state:"OPEN", stateReason:null, createdAt:"2025-10-01T00:00:00Z", closedAt:null, labels:[{name:"process-fb"}], comments:[]}
]' > "$FAKE_GH/issue-list.json"
run --since 2026-01-01 --until 2026-01-31 --issues
assert_rc "--issues を集計できる" 0
assert_file_contains "ラベル名は設定から読む" "$FAKE_GH/calls.log" "issue list --label process-fb"
assert_contains "窓の中の起票" "窓の中の起票: 2 件"
assert_contains "窓の中の close を理由ごとに数える" "NOT_PLANNED 1 件"
assert_contains "在庫を優先度ごとに数える" "open の在庫: 3 件（high 1 ／ medium 1 ／ 優先度が不正 1）"
assert_contains "窓の中の再発（メンバーのものだけ）を多い順に出す" "- 再発 2 本: #13 在庫 (OPEN)"
assert_contains "窓の外の再発は数えない" "- 再発 1 本: #10 窓の中で起票 (OPEN)"

echo "== open の PR の滞留"
jq -n --arg old "$(iso_days -10)" --arg new "$(iso_days -1)" '[
  {number:20, title:"止まっている", updatedAt:$old, isDraft:false, mergeable:"MERGEABLE"},
  {number:21, title:"衝突", updatedAt:$new, isDraft:true, mergeable:"CONFLICTING"},
  {number:22, title:"動いている", updatedAt:$new, isDraft:false, mergeable:"MERGEABLE"}
]' > "$FAKE_GH/pr-list-open.json"
run --since 2026-01-01 --until 2026-01-31 --open
assert_contains "更新の止まった PR" "- #20 止まっている（10 日更新なし）"
assert_contains "衝突している PR" "- #21 衝突（衝突・draft）"
assert_not_contains "動いている PR は出さない" "#22"
assert_contains "件数をまとめる" "open の PR: 3 本のうち滞留 2 本"

finish
