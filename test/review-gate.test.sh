#!/bin/bash
# PR 前レビューの台帳とゲートの振る舞いテスト。
#   - reviewing-changes/scripts/review-ledger.sh   担当の決定・処置の導出・台帳・ゲートの 3 条件
#   - hooks/review-gate.sh                          gh pr create の直前にゲートを呼ぶフック
#
#   bash test/review-gate.test.sh
#
# このディレクトリ（test/）は配布対象外。

set -u
. "$(dirname "$0")/lib/hook-common.sh"
LEDGER_SRC="$REPO_ROOT/packages/core/skills/reviewing-changes/scripts/review-ledger.sh"
WM_SRC="$REPO_ROOT/packages/core/skills/choosing-work-mode/scripts/work-mode.sh"
PROMPT_HOOK="$REPO_ROOT/packages/core/hooks/work-mode-prompt.sh"
H=review-gate.sh

# 作業用のリポジトリ: main にハーネス（skill のスクリプト）を置き、ブランチ claude/test で src/a.ts を足す
#   $1 = ディレクトリ、$2 = workflow: の下に足す行、$3 = 末尾に足す YAML
new_repo() {
    D="$1"
    make_repo "$D" "${2:-}"
    (
        cd "$D" || exit 1
        [ -n "${3:-}" ] && printf '%s\n' "$3" >> .stdd.config.yml
        mkdir -p .claude/skills/reviewing-changes/scripts .claude/skills/choosing-work-mode/scripts
        cp "$LEDGER_SRC" .claude/skills/reviewing-changes/scripts/
        cp "$WM_SRC" .claude/skills/choosing-work-mode/scripts/
        git add -A && git commit -qm harness
        git checkout -qb claude/test
        mkdir -p src && echo 'export const a = 1' > src/a.ts
        git add -A && git commit -qm feat
    )
}
L() { OUT=$(cd "$D" && bash .claude/skills/reviewing-changes/scripts/review-ledger.sh "$@" 2>&1); RC=$?; }
commit() { ( cd "$D" && f="${2:-src/a.ts}" && mkdir -p "$(dirname "$f")" && echo "$1" >> "$f" && git add -A && git commit -qm "$1" ); }
assert_rc()       { [ "$RC" -eq "$2" ] && ok "$1" || ng "$1 (want rc=$2)"; }
assert_contains() { printf '%s' "$OUT" | grep -qF -- "$2" && ok "$1" || ng "$1"; }
# 担当の報告をすべて「指摘なし」で記録する
report_all_none() { for r in $(lines_of launch); do L report --role "$r" --ids none; done; }
lines_of() { awk -F'\t' -v t="$1" -v n="$(awk -F'\t' '$1=="round"{n=$2} END{print n}' "$D"/.git/stdd-review/*.tsv)" '$1 == t && $2 == n { print $3 }' "$D"/.git/stdd-review/*.tsv; }

echo "review-gate tests"

echo "[処置の導出]"
new_repo "$TMP_ROOT/derive"
L derive --role cross --frequency 常時 --impact 支障 --target "src/a.ts"
assert_contains "常時 × 単一 → 中、プロダクト × 中 × 支障 → 直す" "範囲 単一 / 起こりやすさ 中 / 処置: 直す"
L derive --role cross --frequency 条件付き --impact 支障 --target "src/a.ts"
assert_contains "条件付き × 単一 → 低、プロダクト × 低 × 支障 → 起票" "起こりやすさ 低 / 処置: 起票"
L derive --role cross --frequency 条件付き --impact 支障 --target "src/a.ts, src/b.ts"
assert_contains "影響先が 2 つ以上なら範囲は複数" "範囲 複数 / 起こりやすさ 中 / 処置: 直す"
L derive --role cross --frequency 稀 --impact 軽微 --target "認可の判定"
assert_contains "全体の語を含めば範囲は全体（稀 × 全体 → 中 → 見送り可）" "範囲 全体 / 起こりやすさ 中 / 処置: 見送り可"
L derive --role cross --frequency 常時 --impact 軽微 --target "docs/common/REQUIREMENTS.md"
assert_contains "全体のパスを含めば範囲は全体（高 × 軽微 → 起票）" "範囲 全体 / 起こりやすさ 高 / 処置: 起票"
L derive --role cross --frequency 稀 --impact 致命 --target "src/a.ts"
assert_contains "致命は起こりやすさに関わらず直す" "処置: 直す"
L derive --role security --impact 軽微 --target "src/a.ts"
assert_contains "セキュリティは頻度を見ず、軽微でも起票" "起こりやすさ - / 処置: 起票"
L add --id X --role security --frequency 稀 --impact 軽微 --trigger t --target src/a.ts --evidence 4
assert_rc "セキュリティの指摘に頻度を書けば拒否する" 1

H2="$TMP_ROOT/harness"; new_repo "$H2"
( cd "$H2" && git checkout -q main && git checkout -qb claude/harness && mkdir -p .claude/skills/x && echo a > .claude/skills/x/SKILL.md && git add -A && git commit -qm harness-only )
D="$H2"; L derive --role cross --frequency 条件付き --impact 支障 --target "src/a.ts, src/b.ts"
assert_contains "差分がハーネスだけなら種別はハーネス（中 × 支障 → 見送り可）" "種別 ハーネス / 範囲 複数 / 起こりやすさ 中 / 処置: 見送り可"

C="$TMP_ROOT/config"; new_repo "$C" "" $'review:\n  global_words: "決済"\n  harness_paths: "^src/"'
D="$C"; L derive --role cross --frequency 稀 --impact 支障 --target "決済の画面"
assert_contains "設定の global_words で範囲を決める" "範囲 全体"
L derive --role cross --frequency 稀 --impact 支障 --target "認可の判定"
assert_contains "設定で上書きした既定の語は使わない" "範囲 単一"
L derive --role cross --frequency 稀 --impact 支障 --target "x"
assert_contains "設定の harness_paths で種別を決める" "種別 ハーネス"

echo "[担当の決定]"
D="$TMP_ROOT/derive"
L plan
assert_contains "横断は常に起動する" "cross             qa-engineer"
assert_contains "コードの差分でセキュリティを起動する" "security          code-reviewer"
assert_contains "要件の差分が無ければ起動しない" "起動しない requirements"
P="$TMP_ROOT/plan"; new_repo "$P" "" $'review:\n  triggers:\n    code: never'
D="$P"; commit "# 要件" docs/app/x/REQUIREMENTS.md
L plan
assert_contains "要件の差分で requirements-reviewer を起動する" "requirements      requirements-reviewer"
assert_contains "triggers の never で起動しない" "起動しない code-quality  設定で起動しない"
L round start --skip "requirements=auto-implement の Phase 1a で承認済み"
assert_contains "起動しない担当と理由を記録する" "起動しない requirements  auto-implement の Phase 1a で承認済み"
L round start --skip "nope=x"
assert_rc "知らない担当は拒否する" 1

echo "[台帳への記録]"
D="$TMP_ROOT/derive"
L round start --independent yes
L add --id R1-cq-1 --role code-quality --trigger "空の入力" --frequency 常時 --impact 支障 --target src/a.ts --evidence 3
assert_contains "コードの担当の「直す」は、実行で確かめていなければ（段 3 以下）未確認にする" "処置: 未確認"
L raise --id R1-cq-1 --evidence 2
assert_rc "確信の段階は下げられない" 1
L raise --id R1-cq-1 --evidence 4
assert_contains "実行で確かめたら（段 4）直すになる" "処置: 直す"
L add --id R1-cq-2 --role code-quality --trigger "空の入力" --frequency 条件付き --impact 支障 --target src/a.ts --evidence 2
assert_contains "コードの担当でも「直す」以外は段 2 のまま載せる" "処置: 起票"
L derive --role test --frequency 常時 --impact 支障 --target src/a.ts --evidence 3
assert_contains "derive も同じ規則で未確認を出す（Phase 2.5 のレビュー）" "処置: 未確認"
L derive --role requirements --frequency 常時 --impact 支障 --target docs/a/REQUIREMENTS.md --evidence 2
assert_contains "Spec の担当は段 2 でも直すになる" "処置: 直す"
L add --id R1-cross-1 --role cross --trigger "空の入力" --frequency 条件付き --impact 軽微 --target src/a.ts --evidence 2
assert_rc "横断の担当は段 2 でも載せられる" 0
assert_contains "処置を表示する" "処置: 見送り可"
L add --id R1-cross-1 --role cross --trigger x --frequency 常時 --impact 軽微 --target src/a.ts --evidence 2
assert_rc "同じ ID は二重に載せない" 1
L raise --id R1-cross-1 --impact 軽微 --frequency 稀
assert_rc "4 項目は下げられない" 1
L raise --id R1-cross-1 --impact 致命
assert_contains "4 項目を上げると処置を導き直す" "処置: 直す"
L defer --id R1-cross-1 --reason "後で"
assert_rc "処置が直すの指摘は見送れない" 1

echo "[ゲート: 条件 1 レビューされている]"
G="$TMP_ROOT/g1"; new_repo "$G"; D="$G"
L gate
assert_rc "記録が無ければ不合格" 1
assert_contains "条件 1 として知らせる" "条件 1: レビューの記録がありません"
L round start; report_all_none; L round end
L gate
assert_rc "全担当が指摘なしで報告すれば合格" 0
commit "unreviewed"
L gate
assert_rc "レビューの後の、修正でないコミットは不合格" 1
assert_contains "どのコミットかを知らせる" "unreviewed"
G2="$TMP_ROOT/g1b"; new_repo "$G2"; D="$G2"
L round start
L add --id R1-sec-1 --role security --trigger "未認証の要求" --impact 支障 --target src/a.ts --evidence 4
for r in $(lines_of launch); do [ "$r" = security ] && L report --role security --ids R1-sec-1 || L report --role "$r" --ids none; done
L round end
commit "fix"
L gate
assert_rc "修正を対応づけていなければ不合格" 1
L fixed --id R1-sec-1 --commit HEAD
L gate
assert_rc "修正済みの指摘が指す修正だけなら合格" 0
( cd "$D" && git checkout -q main && echo b > b.txt && git add -A && git commit -qm main-change && git checkout -q claude/test && git merge -q --no-edit main )
L gate
assert_rc "主ブランチの取り込みは修正でなくても通す" 0
( cd "$D" && git reset -q --hard HEAD~1 && git commit -q --amend -m "fix (amended)" )
L gate
assert_rc "レビューした時点のコミットを書き換えたら（修正の amend でも）不合格" 1
( cd "$D" && git rebase -q main 2>/dev/null )
L gate
assert_rc "rebase でレビューした時点が祖先でなくなれば不合格" 1
assert_contains "回し直しを促す" "祖先ではありません"

echo "[ゲート: 条件 2 直すべき指摘が残っていない]"
G="$TMP_ROOT/g2"; new_repo "$G"; D="$G"
L round start
L add --id R1-cross-1 --role cross --trigger t --frequency 常時 --impact 支障 --target src/a.ts --evidence 2
L add --id R1-cross-2 --role cross --trigger t --frequency 条件付き --impact 支障 --target src/a.ts --evidence 2
L add --id R1-cross-3 --role cross --trigger t --frequency 稀 --impact 軽微 --target src/a.ts --evidence 2
for r in $(lines_of launch); do [ "$r" = cross ] && L report --role cross --ids "R1-cross-1, R1-cross-2、R1-cross-3" || L report --role "$r" --ids none; done
L round end
L gate
assert_rc "直す・起票が残っていれば不合格" 1
assert_contains "直すの指摘を知らせる" "条件 2: R1-cross-1 は処置が「直す」"
assert_contains "起票の指摘を知らせる" "条件 2: R1-cross-2 は処置が「起票」"
printf '%s' "$OUT" | grep -q "R1-cross-3" && ng "見送り可は条件にしない" || ok "見送り可は条件にしない"
L filed --id R1-cross-2 --issue 12
commit "fix"; L fixed --id R1-cross-1 --commit HEAD
L gate
assert_rc "直すを修正し、起票を issue にすれば合格" 0

echo "[ゲート: 条件 3 指摘が記録から漏れていない]"
G="$TMP_ROOT/g3"; new_repo "$G"; D="$G"
L round start
L add --id R1-cp-1 --role code-performance --trigger t --frequency 常時 --impact 致命 --target src/a.ts --evidence 3
for r in $(lines_of launch); do
    case "$r" in
        code-performance) L report --role "$r" --ids "R1-cp-1" ;;
        code-quality) printf '## 指摘\n...\n\n指摘 ID: R1-cq-9\n' > "$TMP_ROOT/report.md"; L report --role "$r" --file "$TMP_ROOT/report.md" ;;
        security) ;;
        *) L report --role "$r" --ids none ;;
    esac
done
L round end
L gate
assert_rc "報告の ID が台帳に無ければ不合格" 1
assert_contains "載っていない ID を知らせる" "R1-cq-9 が台帳にありません"
assert_contains "報告の無い担当を知らせる" "起動した security の報告が記録されていません"
printf '%s' "$OUT" | grep -q "R1-cp-1" && ng "未確認の指摘は終わりの条件に数えない" || ok "未確認の指摘は終わりの条件に数えない"
printf 'no ids\n' > "$TMP_ROOT/bad.md"; L report --role security --file "$TMP_ROOT/bad.md"
assert_rc "報告の末尾に ID の一覧が無ければ記録しない" 1

echo "[集計]"
L summary --json
printf '%s' "$OUT" | jq -e '.rounds == 1 and .independent == false and .unconfirmed["code-performance"] == 1 and .findings.unconfirmed == 1' >/dev/null \
    && ok "テレメトリ用の集計にラウンド・独立性・未確認の件数が入る" || ng "テレメトリ用の集計"

echo "[フック]"
pr() { hook_input Bash "$(jq -cn --arg c "$1" '{command:$c}')" "" "$D"; }
B="$TMP_ROOT/hb"; new_repo "$B" '  enforce_review_gate: "block"'; D="$B"
run_hook $H "$(pr "gh pr view")" "$D"; expect_silent "gh pr create 以外は見ない"
run_hook $H "$(pr "gh pr create --title x --body-file b.md")" "$D"; expect_deny "block では条件を満たさない PR 作成を止める"
expect_out_contains "理由に条件を書く" "条件 1"
expect_out_contains "例外の前置を案内する" "STDD_REVIEW_GATE_SKIP_REASON="
run_hook $H "$(pr "git push && gh pr create --fill")" "$D"; expect_deny "連結したコマンドの中の gh pr create も見る"
run_hook $H "$(pr "STDD_REVIEW_GATE_SKIP_REASON=\"誤字の修正だけ\" gh pr create --fill")" "$D"; expect_silent "理由を前置すれば通す"
run_hook $H "$(pr "STDD_REVIEW_GATE_SKIP_REASON= gh pr create --fill")" "$D"; expect_deny "空の理由では通さない"
L round start; report_all_none; L round end
run_hook $H "$(pr "gh pr create --fill")" "$D"; expect_silent "条件を満たせば通す"
W="$TMP_ROOT/hw"; new_repo "$W"; D="$W"
run_hook $H "$(pr "gh pr create --fill")" "$D"; expect_warn "既定の warn では知らせるだけ"
O="$TMP_ROOT/ho"; new_repo "$O" '  enforce_review_gate: "off"'; D="$O"
run_hook $H "$(pr "gh pr create --fill")" "$D"; expect_silent "off では何もしない"
E="$TMP_ROOT/he"; new_repo "$E" '  enforce_review_gate: "block"'; D="$E"
( cd "$D" && jq -n '{session_id: "s", cwd: ".", prompt: "緊急モードで進めて"}' | bash "$PROMPT_HOOK" >/dev/null 2>&1 \
    && bash .claude/skills/choosing-work-mode/scripts/work-mode.sh declare --reason "障害対応" >/dev/null )
run_hook $H "$(pr "gh pr create --fill")" "$D"; expect_warn "緊急モードのブランチでは block でも警告にとどめる"
expect_out_contains "緊急モードの節への記載を促す" "緊急モード"
NC="$TMP_ROOT/hnc"; mkdir -p "$NC"; ( cd "$NC" && git init -q ); D="$NC"
run_hook $H "$(pr "gh pr create --fill")" "$D"; expect_silent "設定が無ければ通す"

echo "[表は 1 か所だけ]"
C1='\|[[:space:]]*(常時|条件付き|稀)[[:space:]]*\|[[:space:]]*(高|中|低)[[:space:]]*\|'
C2='\|[[:space:]]*(直す|起票|見送り可)[[:space:]]*\|[[:space:]]*(直す|起票|見送り可)[[:space:]]*\|'
FOUND=$(grep -rnE "$C1|$C2" \
    "$REPO_ROOT/packages/core/skills" "$REPO_ROOT/packages/core/agents" "$REPO_ROOT/packages/core/docs" --include='*.md')
OUT="$FOUND"; RC=0
[ -z "$FOUND" ] && ok "処置の表と起こりやすさの表を文書に転記していない（正本は review-ledger.sh）" || ng "表の転記"

finish
