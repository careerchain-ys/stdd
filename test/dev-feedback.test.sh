#!/bin/bash
# dev-feedback.sh（recording-dev-feedback 同梱）の振る舞いテスト。偽の gh と jq を使う。
#
#   bash test/dev-feedback.test.sh
#
# このディレクトリ（test/）は配布対象外。

set -u
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$REPO_ROOT/packages/core/skills/recording-dev-feedback/scripts/dev-feedback.sh"
. "$REPO_ROOT/test/lib/common.sh"

run() { OUT=$(cd "$REPO_DIR" && bash "$SCRIPT" "$@" 2>&1); RC=$?; }
events() { cat "$REPO_DIR/.git/stdd-telemetry/claude__test.tsv" 2>/dev/null; }

body_file() {
    cat > "$REPO_DIR/../body.md" <<'MD'
## 現象

reviewer が同じ指摘を 2 回出した。

## なぜ問題か

次の機能でも繰り返す。

## 提案

skill に確認手順を足す。
MD
    printf '%s' "$REPO_DIR/../body.md"
}

echo "== setup / check"
new_case setup
echo '[{"name":"dev-feedback"},{"name":"bug"}]' > "$FAKE_GH/label-list.json"
run setup
assert_rc "setup は成功する" 0
assert_contains "既存のラベルは更新する" "updated  dev-feedback"
assert_contains "無いラベルは作る" "created  priority:high"
assert_contains "分類ラベルも作る" "created  category:automation"
assert_contains "件数を報告する" "新規 9 件 / 更新 1 件"
run check
assert_rc "ラベルが足りなければ check は失敗する" 1
assert_contains "check は setup を案内する" "setup を実行してください"
jq -n '[ "dev-feedback","priority:high","priority:medium","category:spec-format","category:skill","category:agent","category:automation","category:flow","category:coding-rules","category:other" ] | map({name: .})' > "$FAKE_GH/label-list.json"
run check
assert_rc "ラベルがそろえば check は成功する" 0

echo "== 設定でラベル名を変えられる"
new_case custom
write_config 'feedback:
  labels:
    base: "process-fb"   # コメント
    priority_high: "優先度:高"
    priority_medium: "優先度:中"
    category_prefix: "分類:"'
echo '[]' > "$FAKE_GH/label-list.json"
run setup
assert_contains "base ラベル名は設定から読む（行末コメントを除く）" "created  process-fb"
assert_contains "優先度ラベル名は設定から読む" "created  優先度:高"
assert_contains "分類の接頭辞は設定から読む" "created  分類:skill"

echo "== feedback.enabled: false"
new_case disabled
write_config 'feedback:
  enabled: false'
run setup
assert_rc "無効なら何もせず成功する" 0
assert_contains "無効であることを知らせる" "feedback.enabled が false"
[ ! -s "$FAKE_GH/calls.log" ] && ok "gh を呼ばない" || ng "gh を呼ばない"

echo "== file"
new_case file
echo '[]' > "$FAKE_GH/issue-list.json"
BF=$(body_file)
run file --title "t" --priority low --category skill --body-file "$BF"
assert_rc "低は起票しない" 1
assert_contains "低を拒否する理由を示す" "低のものは起票しません"
run file --title "t" --priority medium --category nope --body-file "$BF"
assert_rc "定義に無い分類は拒否する" 1
printf '## 現象\n\nx\n' > "$REPO_DIR/../bad.md"
run file --title "t" --priority medium --category skill --body-file "$REPO_DIR/../bad.md"
assert_rc "必須の見出しが無ければ拒否する" 1
assert_contains "足りない見出しを示す" "なぜ問題か"
FAKE_GH_NEXT=42 run file --title "指示が足りない" --priority medium --category skill,agent --target "skills/x/SKILL.md" --body-file "$BF"
assert_rc "起票できる" 0
assert_contains "番号と件数を報告する" "#42 指示が足りない（1/5 件目）"
assert_file_contains "ラベルを付けて作成する" "$FAKE_GH/calls.log" "--label dev-feedback --label priority:medium --label category:skill --label category:agent"
assert_file_contains "本文の先頭に発生源のブランチを付ける" "$FAKE_GH/bodies.log" '| 発生源 | ブランチ `claude/test` |'
assert_file_contains "反映先候補を付ける" "$FAKE_GH/bodies.log" "| 反映先候補 | skills/x/SKILL.md |"
assert_file_contains "本文を続ける" "$FAKE_GH/bodies.log" "reviewer が同じ指摘を 2 回出した。"
OUT=$(events); printf '%s' "$OUT" | grep -q "feedback-filed	42" && ok "起票を記録する" || ng "起票を記録する"

echo "== file の上限"
new_case cap
jq -n '[range(1;6) | {number: ., body: "| 項目 | 内容 |\n| 発生源 | ブランチ `claude/test` ／ PR #9 |\n"}] + [{number: 9, body: "| 発生源 | ブランチ `claude/test-other` |"}]' > "$FAKE_GH/issue-list.json"
BF=$(body_file)
run file --title "t" --priority high --category flow --body-file "$BF"
assert_rc "上限に達していたら exit 2" 2
assert_contains "上限の件数を示す" "既に 5 件起票しています（上限 5 件）"
assert_file_not_contains "上限に達したら作成しない" "$FAKE_GH/calls.log" "issue create"
new_case cap-config
write_config 'feedback:
  max_issues_per_pr: 1'
echo '[]' > "$FAKE_GH/issue-list.json"
BF=$(body_file)
run file --title "a" --priority high --category flow --body-file "$BF"
assert_rc "1 件目は起票できる" 0
run file --title "b" --priority high --category flow --body-file "$BF"
assert_rc "手元の記録でも数える（検索に反映される前でも上限が効く）" 2

echo "== recur"
new_case recur
cat > "$FAKE_GH/issue-view-7.json" <<JSON
{"state":"OPEN","stateReason":null,"labels":[{"name":"dev-feedback"},{"name":"priority:medium"}],
 "comments":[
   {"authorAssociation":"MEMBER","body":"再発 — 2025-12-01（x）: a","createdAt":"2025-12-01T00:00:00Z"},
   {"authorAssociation":"NONE","body":"再発 — 2025-12-02（x）: 外部の人","createdAt":"2025-12-02T00:00:00Z"},
   {"authorAssociation":"OWNER","body":" 再発 — 行頭に空白","createdAt":"2025-12-03T00:00:00Z"}
 ]}
JSON
run recur 7
assert_rc "--note が無ければ拒否する" 1
run recur 7 --note "また起きた"
assert_rc "再発コメントを追加できる" 0
assert_file_contains "書式は行頭の「再発 —」と日付・ブランチ" "$FAKE_GH/bodies.log" "再発 — $(date -u +%F)（claude/test）: また起きた"
assert_contains "信頼できる投稿者の行頭の書式だけを数える" "再発コメント: 1 本"
assert_file_not_contains "閾値に達しなければ昇格しない" "$FAKE_GH/calls.log" "--add-label priority:high"
OUT=$(events); printf '%s' "$OUT" | grep -q "feedback-recur	7" && ok "再発を記録する" || ng "再発を記録する"
# 投稿後の状態（2 本目）を fixture にして昇格を確かめる
jq '.comments += [{"authorAssociation":"OWNER","body":"再発 — 2026-01-01（y）: b","createdAt":"2026-01-01T00:00:00Z"}]' "$FAKE_GH/issue-view-7.json" > "$FAKE_GH/t" && mv "$FAKE_GH/t" "$FAKE_GH/issue-view-7.json"
run recur 7 --note "3 回目"
assert_contains "2 本に達したら昇格する" "promoted #7: priority:medium → priority:high"
assert_file_contains "high を付けてから medium を外す" "$FAKE_GH/calls.log" "issue edit 7 --add-label priority:high"
assert_file_contains "medium を外す" "$FAKE_GH/calls.log" "issue edit 7 --remove-label priority:medium"

new_case recur-closed
mk_closed() {  # $1=番号 $2=stateReason $3=追加コメント(JSON 配列)
    jq -n --arg r "$2" --argjson c "$3" '{state:"CLOSED",stateReason:$r,labels:[{name:"dev-feedback"},{name:"priority:medium"}],comments:$c}' > "$FAKE_GH/issue-view-$1.json"
}
mk_closed 11 COMPLETED '[]'
mk_closed 12 NOT_PLANNED '[{"authorAssociation":"OWNER","body":"見送り — 2025-12-10\n\n- 基準","createdAt":"2025-12-10T00:00:00Z"}]'
echo '[{"event":"reopened","created_at":"2025-11-01T00:00:00Z"}]' > "$FAKE_GH/timeline-12.json"
mk_closed 13 NOT_PLANNED '[]'
mk_closed 14 NOT_PLANNED '[{"authorAssociation":"OWNER","body":"見送り — 2025-10-01","createdAt":"2025-10-01T00:00:00Z"}]'
echo '[{"event":"reopened","created_at":"2025-11-01T00:00:00Z"}]' > "$FAKE_GH/timeline-14.json"
mk_closed 15 DUPLICATE '[]'
run recur 11 --note x; assert_file_contains "反映済みで閉じたものは reopen する" "$FAKE_GH/calls.log" "issue reopen 11"
run recur 12 --note x; assert_file_contains "見送りで閉じたものは reopen する" "$FAKE_GH/calls.log" "issue reopen 12"
run recur 13 --note x; assert_contains "人の判断の not planned は reopen しない" "人の判断で not planned"
run recur 14 --note x; assert_file_not_contains "見送りの後に reopen を挟んで人が閉じたものは reopen しない" "$FAKE_GH/calls.log" "issue reopen 14"
run recur 15 --note x; assert_file_not_contains "duplicate は reopen しない" "$FAKE_GH/calls.log" "issue reopen 15"
echo '{"state":"OPEN","stateReason":null,"labels":[{"name":"bug"}],"comments":[]}' > "$FAKE_GH/issue-view-16.json"
run recur 16 --note x; assert_rc "dev-feedback ではない issue は拒否する" 1

echo "== triage"
new_case triage
run triage
assert_rc "--skipped が無ければ拒否する（0 件でも渡す）" 1
mkdir -p "$REPO_DIR/.git/stdd-telemetry"
printf '1\tfeedback-filed\t42\n2\tfeedback-recur\t7\n' > "$REPO_DIR/.git/stdd-telemetry/claude__test.tsv"
run triage --skipped 2
assert_rc "triage は成功する" 0
assert_contains "備考の行を出す" "開発フィードバック: 起票 #42 ／ 再発 #7 ／ 上限で起票しなかったもの 2 件（反映は別 PR）"
OUT=$(events); printf '%s' "$OUT" | grep -q "feedback-triage	2" && ok "棚卸しの終了を記録する" || ng "棚卸しの終了を記録する"

echo "== audit / close-stale / promote"
new_case audit
OLD=$(iso_days -20); NEW=$(iso_days -3)
jq -n --arg old "$OLD" --arg new "$NEW" '[
  {number:1, title:"静かな medium", labels:[{name:"dev-feedback"},{name:"priority:medium"},{name:"category:skill"}], assignees:[], updatedAt:$old, comments:[]},
  {number:2, title:"担当者あり", labels:[{name:"dev-feedback"},{name:"priority:medium"},{name:"category:skill"}], assignees:[{login:"a"}], updatedAt:$old, comments:[]},
  {number:3, title:"優先度が 2 つ", labels:[{name:"dev-feedback"},{name:"priority:medium"},{name:"priority:high"},{name:"category:skill"}], assignees:[], updatedAt:$new, comments:[]},
  {number:4, title:"再発が多い", labels:[{name:"dev-feedback"},{name:"priority:medium"},{name:"category:flow"}], assignees:[], updatedAt:$old,
   comments:[{authorAssociation:"OWNER",body:"再発 — a"},{authorAssociation:"COLLABORATOR",body:"再発 — b"}]},
  {number:5, title:"リポジトリから参照", labels:[{name:"dev-feedback"},{name:"priority:medium"},{name:"category:skill"}], assignees:[], updatedAt:$old, comments:[]},
  {number:6, title:"最近動いた", labels:[{name:"dev-feedback"},{name:"priority:medium"}], assignees:[], updatedAt:$new, comments:[]},
  {number:8, title:"open の PR から参照", labels:[{name:"dev-feedback"},{name:"priority:medium"},{name:"category:skill"}], assignees:[], updatedAt:$old, comments:[]},
  {number:9, title:"high は見送らない", labels:[{name:"dev-feedback"},{name:"priority:high"},{name:"category:skill"}], assignees:[], updatedAt:$old, comments:[]}
]' > "$FAKE_GH/issue-list.json"
echo '[{"event":"cross-referenced","source":{"issue":{"number":77,"state":"open","pull_request":{}}}}]' > "$FAKE_GH/timeline-8.json"
echo '[{"event":"cross-referenced","source":{"issue":{"number":78,"state":"closed","pull_request":{}}}}]' > "$FAKE_GH/timeline-1.json"
( cd "$REPO_DIR" && echo "TODO: #5 を参照" > notes.md && git add notes.md && git commit -q -m notes )
run audit
assert_rc "audit は成功する" 0
assert_contains "優先度ラベルの数の不整合を出す" "#3	優先度ラベルが 2 個"
assert_contains "分類ラベルの欠けを出す" "#6	分類ラベルがない"
assert_contains "昇格の候補を出す" "#4	再発 2 本"
assert_contains "見送りの候補を出す（closed の PR からの参照は妨げない）" "#1	20 日	静かな medium"
assert_contains "担当者がいれば見送らない" "#2	20 日	assignee が付いている"
assert_contains "リポジトリから参照されていれば見送らない" "#5	20 日	リポジトリ内のファイルから参照されている"
assert_contains "open の PR から参照されていれば見送らない" "#8	20 日	open の PR から参照されている（#77）"
assert_not_contains "最近動いたものは候補にしない" "#6	3 日"
assert_not_contains "high は見送りの候補にしない" "high は見送らない"

for n in 1 6; do
    jq --argjson n "$n" '.[] | select(.number == $n) | {state:"OPEN", labels, assignees, updatedAt}' "$FAKE_GH/issue-list.json" > "$FAKE_GH/issue-view-$n.json"
done
run close-stale 1 6
assert_contains "条件を満たすものを閉じる" "closed #1"
assert_contains "取り直して条件を満たさないものは閉じない" "skip   #6: 動きのない期間が 3 日"
assert_file_contains "not planned で閉じる" "$FAKE_GH/calls.log" "issue close 1 --reason not planned"
assert_file_contains "コメントの 1 行目は「見送り —」" "$FAKE_GH/bodies.log" "見送り — $(date -u +%F)"
assert_file_not_contains "閉じないものには触らない" "$FAKE_GH/calls.log" "issue close 6"

jq '.[] | select(.number == 4) | {labels}' "$FAKE_GH/issue-list.json" > "$FAKE_GH/issue-view-4.json"
jq '.[] | select(.number == 9) | {labels}' "$FAKE_GH/issue-list.json" > "$FAKE_GH/issue-view-9.json"
run promote 4 9
assert_contains "medium を high に上げる" "promoted #4"
assert_contains "既に high なら何もしない" "skip   #9: 既に priority:high"

finish
