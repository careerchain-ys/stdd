#!/bin/bash
# PreToolUse Hook: PR を作る直前に、PR 前レビューの 3 条件を確かめる。
# 登録: Claude / Codex とも Bash（settings.json / .codex/hooks.json）。
#
# 規律（reviewing-changes skill・docs/review-process.md）: PR はレビューを通してから作る。ゲートはこの 1 か所だけで、
#   確かめるのは次の 3 条件に限る。テストと機械検査は CI に任せ、ローカルでの完走は条件にしない。
#   1. PR の中身がレビューされている（レビューした時点のコミットが HEAD の祖先で、その後のコミットは修正済みの指摘が指す修正だけ）
#   2. 直すべき指摘が残っていない（処置が「直す」はすべて修正済み、「起票」は issue がある）
#   3. 指摘が記録から漏れていない（reviewer の報告の末尾の指摘 ID がすべて台帳にある）
#   判定の本体は reviewing-changes/scripts/review-ledger.sh gate。このフックは呼ぶだけである。
#
# 判定: コマンドに `gh pr create` を含むときだけ動く。
# 通すもの:
#   - STDD_REVIEW_GATE_SKIP_REASON="<理由>" を前置した実行（理由が空なら通さない）。誤字の修正だけの PR など
#   - 緊急モードのブランチ（choosing-work-mode）。条件を満たさなくても警告にとどめる
# 強さ: .stdd.config.yml の workflow.enforce_review_gate = off | warn（既定）| block。
# 失敗時: 設定が無い・jq が無い・review-ledger.sh が見つからないときは通す（フックの故障で作業を止めない）。
# 限界: `gh pr create` 以外の方法（Web の画面、gh api）で作る PR は確かめられない。

command -v jq >/dev/null 2>&1 || exit 0
hook_input=$(cat)
jqr() { printf '%s' "$hook_input" | jq -r "$1 // empty" 2>/dev/null; }

[ "$(jqr '.tool_name')" = "Bash" ] || exit 0
CMD=$(jqr '.tool_input.command')
printf '%s' "$CMD" | grep -Eq '(^|[^[:alnum:]_-])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)' || exit 0
printf '%s' "$CMD" | grep -Eq "STDD_REVIEW_GATE_SKIP_REASON=(\"[^\"]+\"|'[^']+'|[^[:space:]\"']+)" && exit 0

INPUT_CWD=$(jqr '.cwd')
[ -n "$INPUT_CWD" ] && [ -d "$INPUT_CWD" ] || INPUT_CWD=$(pwd)
ROOT_DIR=$(git -C "$INPUT_CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
CONFIG="$ROOT_DIR/.stdd.config.yml"
[ -f "$CONFIG" ] || exit 0

MODE=$(awk '
    /^[^[:space:]#]/ { insec = ($1 == "workflow:"); next }
    insec && $1 == "enforce_review_gate:" { sub(/^[[:space:]]*[^:]*:[[:space:]]*/, ""); sub(/[[:space:]]+#.*$/, ""); print; exit }
' "$CONFIG" | tr -d "\"'")
case "$MODE" in
    off) exit 0 ;;
    block) ;;
    *) MODE=warn ;;
esac

find_skill_script() { # $1 = skill, $2 = スクリプト
    local d
    for d in .claude/skills .agents/skills; do
        [ -f "$ROOT_DIR/$d/$1/scripts/$2" ] && { printf '%s' "$ROOT_DIR/$d/$1/scripts/$2"; return 0; }
    done
    return 1
}
LEDGER=$(find_skill_script reviewing-changes review-ledger.sh) || exit 0

OUT=$(bash "$LEDGER" --root "$ROOT_DIR" gate 2>&1) && exit 0

WORK_MODE=$(find_skill_script choosing-work-mode work-mode.sh)
if [ -n "$WORK_MODE" ] && bash "$WORK_MODE" --root "$ROOT_DIR" active >/dev/null 2>&1; then
    MODE=warn
    SUFFIX="（緊急モードのブランチなので止めていません。PR 本文の「緊急モード」の節に、未レビューの範囲として書いてください）"
else
    SUFFIX="（enforce_review_gate=warn のため止めていません）"
fi

REASON="STDD review-gate: PR を作る前の条件を満たしていません。
$OUT
reviewing-changes skill の手順で、台帳を直すかラウンドを回してから PR を作ってください。
レビューの要らない PR（誤字の修正だけなど）は、理由を前置して実行してください（例: STDD_REVIEW_GATE_SKIP_REASON=\"誤字の修正だけ\" gh pr create ...）。"

if [ "$MODE" = "block" ]; then
    jq -n --arg r "$REASON" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
else
    jq -n --arg r "$REASON$SUFFIX" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$r}}'
fi
exit 0
