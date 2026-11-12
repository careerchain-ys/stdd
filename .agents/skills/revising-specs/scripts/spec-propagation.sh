#!/bin/bash
# spec-propagation.sh — 改修で直す文書を、文書間の依存関係と設定から決める。古い記述の残りを探す。
#
# 使い方:
#   spec-propagation.sh [--root <dir>] targets <文書のキー> [--feature <feature_path>] [--app <apps[].id>]
#       変更が属する文書から、依存の向きにたどれる文書をすべて、直す順に出す。
#       1 行 1 文書で「キー<TAB>パス<TAB>状態」。--feature を渡すとパスを解決し、状態に「あり / 無い」を出す。
#       最後にテストと実装の行を出す（文書の後に直す）。
#   spec-propagation.sh [--root <dir>] order
#       設定にある文書のキーを、直す順にすべて出す。
#   spec-propagation.sh [--root <dir>] search [--feature <feature_path>] [--also <path>]... [--expect-none] <語>...
#       設定にあるすべての Spec の文書（--also で足したファイル・ディレクトリを含む）から、語を固定文字列で探す。
#       ID と、変更前の説明文の語の両方を渡す。--feature を渡すと、feature 階層はその機能だけを探す（common は常に探す）。
#       --expect-none を付けると、1 件でも見つかったら exit 1（直し終えた後の残りの確認に使う）。
#
# 文書のキーは .stdd.config.yml の docs.layout のキー（requirements / api_design / common_table_definition など）。
# docs.lineup が single なら tech_design / test_plan を、layered なら api_design / screen_design /
# api_test_design / screen_test_design / test_design を feature の技術 spec として扱い、もう一方の構成のキーは無視する。
# layout に無いキーは依存関係から外す（その文書を使わない構成として扱う）。
#
# 依存関係の正本はこのスクリプトの EDGES。意味は packages/core/docs/spec-revision.md §3 と
# ../references/change-kinds.md にある。依存の向きは「上の文書の決定が変わると、下の文書が動きうる」。
# 出すのは動きうる文書の全体で、直すかどうかは skill の手順（変更の種類と検索の結果）で 1 件ずつ決める。
#
# 依存: bash 3.2 以上、awk、find、grep。

set -u

ROOT=""
CMD=""
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --root) ROOT="${2:-}"; shift 2 ;;
        --help|-h) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)
            if [ -z "$CMD" ]; then CMD="$1"; else ARGS+=("$1"); fi
            shift ;;
    esac
done

die() { echo "spec-propagation NG: $*" >&2; exit 2; }

[ -n "$CMD" ] || die "コマンドを指定してください（targets / order / search。--help で一覧）"
[ -n "$ROOT" ] || ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CONFIG="$ROOT/.stdd.config.yml"
[ -f "$CONFIG" ] || die ".stdd.config.yml が見つかりません（$CONFIG）"

# ---------------------------------------------------------------------------
# .stdd.config.yml（外部依存なしのパーサ）
# ---------------------------------------------------------------------------
unquote() {
    local v="$1"
    case "$v" in
        \"*) v="${v#\"}"; v="${v%%\"*}" ;;
        \'*) v="${v#\'}"; v="${v%%\'*}" ;;
        *)   v=$(printf '%s' "$v" | sed 's/[[:space:]]#.*$//; s/[[:space:]]*$//') ;;
    esac
    printf '%s' "$v"
}
docs_value() {  # $1=docs 直下のキー
    unquote "$(awk -v k="$1:" '
        /^[^[:space:]#]/ { indocs = ($1 == "docs:"); next }
        indocs && /^  [^[:space:]#]/ && $1 == k { sub(/^[[:space:]]*[^:]*:[[:space:]]*/, ""); print; exit }
    ' "$CONFIG")"
}
layout_value() {  # $1=docs.layout のキー
    unquote "$(awk -v k="$1:" '
        /^[^[:space:]#]/ { indocs = ($1 == "docs:"); inlayout = 0; next }
        indocs && /^  [^[:space:]#]/ { inlayout = ($1 == "layout:"); next }
        indocs && inlayout && $1 == k { sub(/^[[:space:]]*[^:]*:[[:space:]]*/, ""); print; exit }
    ' "$CONFIG")"
}
app_value() {  # $1=apps[].id $2=キー（id / path）
    unquote "$(awk -v want="$1" -v k="$2:" '
        /^[^[:space:]#]/ { inapps = ($1 == "apps:"); next }
        !inapps { next }
        /^[[:space:]]*-[[:space:]]/ { sub(/^[[:space:]]*-[[:space:]]*/, "  "); cur = "" }
        $1 == "id:" { v = $0; sub(/^[[:space:]]*id:[[:space:]]*/, "", v); gsub(/["\047]/, "", v); sub(/[[:space:]]#.*$/, "", v); cur = v }
        $1 == k && cur == want { sub(/^[[:space:]]*[^:]*:[[:space:]]*/, ""); print; exit }
    ' "$CONFIG")"
}

LINEUP=$(docs_value lineup)
[ -n "$LINEUP" ] || LINEUP=single
case "$LINEUP" in single|layered) ;; *) die "docs.lineup の値が不正です（$LINEUP）" ;; esac

# 直す順（依存の上から下へ）。plan は改修の対象の文書ではないので含めない。
ALL_KEYS="common_requirements requirements common_architecture common_table_definition common_api_spec common_design wireframes tech_design api_design screen_design test_plan api_test_design screen_test_design test_design"

# 依存関係（上の文書 → 下の文書）
EDGES="
common_requirements requirements
requirements common_table_definition
requirements common_api_spec
requirements common_design
requirements wireframes
requirements tech_design
requirements api_design
requirements screen_design
requirements test_plan
requirements test_design
common_architecture tech_design
common_architecture api_design
common_architecture screen_design
common_table_definition tech_design
common_table_definition api_design
common_api_spec tech_design
common_api_spec api_design
common_api_spec screen_design
common_design wireframes
common_design tech_design
common_design screen_design
wireframes tech_design
wireframes screen_design
tech_design test_plan
api_design screen_design
api_design api_test_design
screen_design screen_test_design
api_test_design test_design
screen_test_design test_design
"

key_in_lineup() {
    case "$LINEUP:$1" in
        single:api_design|single:screen_design|single:api_test_design|single:screen_test_design|single:test_design) return 1 ;;
        layered:tech_design|layered:test_plan) return 1 ;;
    esac
    return 0
}
key_active() { key_in_lineup "$1" && [ -n "$(layout_value "$1")" ]; }

ACTIVE=""
for k in $ALL_KEYS; do key_active "$k" && ACTIVE="$ACTIVE $k"; done

is_active() { case " $ACTIVE " in *" $1 "*) return 0 ;; esac; return 1; }

# 依存の向きにたどれるキー（自分を含む）。layout に無いキーは通り抜ける（その下は残す）。
closure() {
    local seen=" $1 " frontier="$1" next k from to
    while [ -n "$frontier" ]; do
        next=""
        for k in $frontier; do
            while read -r from to; do
                [ "$from" = "$k" ] || continue
                case "$seen" in *" $to "*) continue ;; esac
                seen="$seen$to "
                next="$next $to"
            done <<EOF
$EDGES
EOF
        done
        frontier="$next"
    done
    printf '%s' "$seen"
}

FEATURE=""
APP_ID=""
resolve_path() {  # $1=パステンプレート
    local p="$1" app_path=""
    [ -n "$APP_ID" ] && app_path=$(app_value "$APP_ID" path)
    p="${p//\{\{feature_path\}\}/$FEATURE}"
    p="${p//\{\{app.id\}\}/$APP_ID}"
    p="${p//\{\{app.path\}\}/$app_path}"
    printf '%s' "$p"
}

cmd_order() {
    for k in $ACTIVE; do printf '%s\t%s\n' "$k" "$(layout_value "$k")"; done
}

cmd_targets() {
    local start="" k tpl p state reach
    while [ ${#ARGS[@]} -gt 0 ]; do
        case "${ARGS[0]}" in
            --feature) FEATURE="${ARGS[1]:-}"; ARGS=("${ARGS[@]:2}") ;;
            --app) APP_ID="${ARGS[1]:-}"; ARGS=("${ARGS[@]:2}") ;;
            *) [ -z "$start" ] || die "文書のキーは 1 つだけ渡してください"; start="${ARGS[0]}"; ARGS=("${ARGS[@]:1}") ;;
        esac
    done
    [ -n "$start" ] || die "変更が属する文書のキーを渡してください（order で一覧）"
    case " $ALL_KEYS " in *" $start "*) ;; *) die "知らない文書のキーです（$start）" ;; esac
    key_in_lineup "$start" || die "$start は docs.lineup=$LINEUP の構成に無い文書です"
    is_active "$start" || die "$start は docs.layout にありません"

    reach=$(closure "$start")
    echo "# docs.lineup=$LINEUP / 起点=$start（上から順に直す。直さない文書は、変わらないと判断した根拠を残す）"
    for k in $ACTIVE; do
        case "$reach" in *" $k "*) ;; *) continue ;; esac
        tpl=$(layout_value "$k")
        state="-"
        if [ -n "$FEATURE" ] || ! printf '%s' "$tpl" | grep -q '{{'; then
            p=$(resolve_path "$tpl")
            if printf '%s' "$p" | grep -q '{{'; then
                state="-"
            elif [ -e "$ROOT/$p" ]; then state="あり"; else state="無い"; fi
        else
            p="$tpl"
        fi
        printf '%s\t%s\t%s\n' "$k" "$p" "$state"
    done
    printf 'tests\t%s\t-\n' "テスト設計に対応するテスト（Red を確かめてから実装へ）"
    printf 'impl\t%s\t-\n' "実装"
}

# 設定にある Spec の文書のファイルを列挙する（--feature があれば feature 階層はその機能だけ）
spec_files() {
    local k tpl pat
    for k in $ACTIVE; do
        tpl=$(layout_value "$k")
        if [ -n "$FEATURE" ]; then tpl=$(resolve_path "$tpl"); fi
        pat=$(printf '%s' "$tpl" | sed 's/{{[^}]*}}/*/g')
        case "$pat" in
            *.md|*.html|*.yml|*.yaml|*.json)
                find "$ROOT" -path "$ROOT/$pat" -type f 2>/dev/null ;;
            *)
                find "$ROOT" -path "$ROOT/${pat%/}/*" -type f 2>/dev/null ;;
        esac
    done | sort -u
}

# --also で足したファイル・ディレクトリの中のファイル
extra_files() {
    local f
    for f in "$@"; do
        [ -n "$f" ] || continue
        if [ "${f#/}" = "$f" ]; then f="$ROOT/$f"; fi
        if [ -d "$f" ]; then
            find "$f" -type f -not -path '*/.git/*' -not -path '*/node_modules/*'
        elif [ -f "$f" ]; then
            echo "$f"
        fi
    done
}

cmd_search() {
    local expect_none=0 terms=() also=() f t hits total=0 files
    while [ ${#ARGS[@]} -gt 0 ]; do
        case "${ARGS[0]}" in
            --feature) FEATURE="${ARGS[1]:-}"; ARGS=("${ARGS[@]:2}") ;;
            --also) also+=("${ARGS[1]:-}"); ARGS=("${ARGS[@]:2}") ;;
            --expect-none) expect_none=1; ARGS=("${ARGS[@]:1}") ;;
            *) terms+=("${ARGS[0]}"); ARGS=("${ARGS[@]:1}") ;;
        esac
    done
    [ ${#terms[@]} -gt 0 ] || die "探す語（ID・変更前の説明文の語）を 1 つ以上渡してください"

    files=$( { spec_files; extra_files "${also[@]+"${also[@]}"}"; } | sed '/^$/d' | sort -u)
    [ -n "$files" ] || { echo "spec-propagation: 探す文書がありません（docs.layout のパスに一致するファイルが無い）"; exit 0; }

    for t in "${terms[@]}"; do
        hits=$(printf '%s\n' "$files" | while IFS= read -r f; do grep -nF -- "$t" "$f" 2>/dev/null | sed "s|^|${f#"$ROOT"/}:|"; done)
        if [ -n "$hits" ]; then
            n=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
            total=$((total + n))
            echo "## $t（$n 件）"
            printf '%s\n' "$hits"
        else
            echo "## $t（0 件）"
        fi
    done
    echo "spec-propagation: 探した文書 $(printf '%s\n' "$files" | wc -l | tr -d ' ') 件 / 見つかった行 $total 件"
    if [ "$expect_none" -eq 1 ] && [ "$total" -gt 0 ]; then
        echo "spec-propagation NG: 古い記述が残っています（--expect-none）" >&2
        exit 1
    fi
    exit 0
}

case "$CMD" in
    order) cmd_order ;;
    targets) cmd_targets ;;
    search) cmd_search ;;
    *) die "知らないコマンドです（$CMD）" ;;
esac
