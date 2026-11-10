#!/bin/bash
# emergency-debt.sh — 緊急モードで作った PR の負債を、機能ごとの GitHub issue に記録する。
#
# 使い方:
#   emergency-debt.sh [--root <dir>] [--repo <owner/name>] <command> [args]
#
#   record --feature <key>[,<key>...] [--pr <番号>] [--note <後追いが要るもの>]
#                         PR を機能ごとの負債 issue に積む。open な issue が無ければ作り、あればコメントで追記する。
#                         同じ PR を同じ issue に二度は積まない。--pr を省くと現在のブランチの PR を使う
#   list                  open な負債 issue を一覧する（読み取りのみ）
#   entries <issue>       issue に積まれた由来 PR と、その状態（MERGED / OPEN / CLOSED）を TSV で出す（読み取りのみ）
#   close <issue> --settled-by <PR> --handled <番号>[,<番号>...]
#                         解消した PR を添えて issue を閉じる。--handled に無い由来 PR のうち、マージ済みか open の
#                         ものが残っていれば閉じずに exit 2（解消に着手したあとで積まれた負債を取りこぼさない）
#
# 何を負債として記録し、どう解消するかの正本は ../SKILL.md と ../../choosing-work-mode/SKILL.md。
# このスクリプトは issue の読み書きだけを扱い、何を直すかの判断はしない。
#
# issue の本文には目印 <!-- stdd-emergency-debt: <機能キー> --> を置き、機能キーで issue を引く（題名は人が変えてよい）。
# 由来 PR は「- 由来 PR #<番号>（<記録日>）: <メモ>」の 1 行で、本文かコメントに書く。
#
# 設定: .stdd.config.yml の emergency_mode.debt_label（既定 emergency-debt）。emergency_mode.enabled が false なら
#       何もせず exit 0。
# 依存: bash 3.2 以上、git、gh（gh の --jq を使う。jq 単体は不要）。

set -u

ROOT=""
REPO=""
CMD=""
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --root) ROOT="${2:-}"; shift 2 ;;
        --repo) REPO="${2:-}"; shift 2 ;;
        --help|-h) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)
            if [ -z "$CMD" ]; then CMD="$1"; else ARGS+=("$1"); fi
            shift ;;
    esac
done

die()  { echo "emergency-debt: $*" >&2; exit 1; }
warn() { echo "emergency-debt: $*" >&2; }

[ -n "$CMD" ] || die "コマンドを指定してください（--help で一覧）"
case "$REPO" in --*) die "--repo には owner/name を渡してください: $REPO" ;; esac
[ -n "$REPO" ] && export GH_REPO="$REPO"

if [ -z "$ROOT" ]; then
    ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
CONFIG="$ROOT/.stdd.config.yml"

config_block() {
    [ -f "$CONFIG" ] || return 0
    awk -v blk="$1:" '
        /^[^[:space:]#]/ { inblk = ($1 == blk) ; next }
        inblk { print }
    ' "$CONFIG"
}
EM_BLOCK="$(config_block emergency_mode)"
cfg() {
    local v
    v=$(printf '%s\n' "$EM_BLOCK" | awk -v k="$1:" '
        $1 == k { sub(/^[[:space:]]*[^:]*:[[:space:]]*/, ""); print; exit }
    ')
    case "$v" in
        \"*) v="${v#\"}"; v="${v%%\"*}" ;;
        \'*) v="${v#\'}"; v="${v%%\'*}" ;;
        *)   v=$(printf '%s' "$v" | sed 's/[[:space:]]#.*$//; s/[[:space:]]*$//') ;;
    esac
    printf '%s' "${v:-$2}"
}

ENABLED=$(cfg enabled true)
LABEL=$(cfg debt_label emergency-debt)

if [ "$ENABLED" = "false" ]; then
    echo "emergency-debt: emergency_mode.enabled が false のため何もしません"
    exit 0
fi

require_gh() {
    command -v gh >/dev/null 2>&1 || die "gh コマンドがありません（https://cli.github.com/）"
}
today() {
    if [ -n "${STDD_NOW:-}" ]; then
        date -u -r "$STDD_NOW" +%F 2>/dev/null || date -u -d "@$STDD_NOW" +%F
    else
        date -u +%F
    fi
}
marker() { printf '<!-- stdd-emergency-debt: %s -->' "$1"; }
one_line() { printf '%s' "$1" | tr '\r\n\t' '   ' | sed 's/  */ /g; s/^ //; s/ $//'; }

# 機能キーの open な負債 issue の番号（無ければ空）
find_issue() {
    local m
    m=$(marker "$1")
    gh issue list --label "$LABEL" --state open --limit 200 --json number,body \
        --jq ".[] | select(.body | contains(\"$m\")) | .number" | head -1
}

# issue の本文とコメントから由来 PR の番号を出現順に一意に出す
issue_prs() {
    gh issue view "$1" --json body,comments --jq '[.body, (.comments[].body)] | join("\n")' \
        | sed -n 's/^- 由来 PR #\([0-9][0-9]*\)（.*/\1/p' | awk '!seen[$0]++'
}

cmd_record() {
    require_gh
    local features="" pr="" note=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --feature) features="${2:-}"; shift 2 ;;
            --pr) pr="${2:-}"; shift 2 ;;
            --note) note="${2:-}"; shift 2 ;;
            *) die "record: 知らない引数: $1" ;;
        esac
    done
    [ -n "$features" ] || die "record: --feature に機能キーを渡してください（docs.layout の feature_path。複数はカンマ区切り）"
    if [ -z "$pr" ]; then
        pr=$(gh pr view --json number --jq .number 2>/dev/null) || die "record: 現在のブランチの PR を取得できません（--pr で番号を渡してください）"
    fi
    case "$pr" in ''|*[!0-9]*) die "record: PR の番号が不正です: '$pr'" ;; esac
    note=$(one_line "$note")
    local line
    line="- 由来 PR #${pr}（$(today) 記録）: ${note:-（後追いのメモなし。PR 本文の「緊急モード」節を参照）}"

    gh label create "$LABEL" --color B60205 --description "緊急モードで作った PR の負債（機能ごと。open ＝ 未解消）" --force >/dev/null 2>&1 \
        || warn "ラベル $LABEL を作成・更新できませんでした（既にあれば問題ありません）"

    local key issue tmp rc=0 IFS_SAVE="$IFS"
    IFS=','
    set -- $features
    IFS="$IFS_SAVE"
    for key in "$@"; do
        key=$(one_line "$key")
        [ -n "$key" ] || continue
        issue=$(find_issue "$key") || { warn "issue を検索できません（$key）"; rc=1; continue; }
        tmp=$(mktemp "${TMPDIR:-/tmp}/emergency-debt.XXXXXX")
        if [ -n "$issue" ]; then
            if issue_prs "$issue" | grep -qx "$pr"; then
                echo "emergency-debt record: #$issue（$key）には PR #$pr が記録済みです"
                rm -f "$tmp"; continue
            fi
            printf '%s\n' "$line" > "$tmp"
            if gh issue comment "$issue" --body-file "$tmp" >/dev/null; then
                echo "emergency-debt record: #$issue（$key）に PR #$pr を追記しました"
            else
                warn "#$issue にコメントできません"; rc=1
            fi
        else
            {
                marker "$key"; echo
                echo "緊急モードで作った PR のうち、機能 \`$key\` に触れたものの負債です。"
                echo "通常のレビューと品質ゲートを通っていない差分が残っています。解消の手順は skill \`settling-emergency-debt\` を参照してください。"
                echo
                echo "## 由来 PR"
                echo
                printf '%s\n' "$line"
            } > "$tmp"
            local url
            if url=$(gh issue create --title "緊急モードの負債: $key" --label "$LABEL" --body-file "$tmp"); then
                echo "emergency-debt record: 負債 issue を作成しました（$key）: $url"
            else
                warn "負債 issue を作成できません（$key）"; rc=1
            fi
        fi
        rm -f "$tmp"
    done
    return $rc
}

cmd_list() {
    require_gh
    gh issue list --label "$LABEL" --state open --limit 200 --json number,title \
        --jq '.[] | "#\(.number)\t\(.title)"' || die "list: issue を取得できません"
}

# 由来 PR と状態の TSV
pr_states() {
    local n s
    for n in $(issue_prs "$1"); do
        s=$(gh pr view "$n" --json state --jq .state 2>/dev/null) || s="UNKNOWN"
        printf '%s\t%s\n' "$n" "$s"
    done
}

cmd_entries() {
    require_gh
    [ $# -ge 1 ] || die "entries: issue の番号を渡してください"
    pr_states "$1"
}

cmd_close() {
    require_gh
    local issue="${1:-}" settled="" handled=""
    [ -n "$issue" ] || die "close: issue の番号を渡してください"
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --settled-by) settled="${2:-}"; shift 2 ;;
            --handled) handled="${2:-}"; shift 2 ;;
            *) die "close: 知らない引数: $1" ;;
        esac
    done
    [ -n "$settled" ] || die "close: --settled-by に解消した PR の番号を渡してください"
    [ -n "$handled" ] || die "close: --handled に、解消の対象にした由来 PR の番号をカンマ区切りで渡してください"
    local remain="" n s
    while IFS="$(printf '\t')" read -r n s; do
        [ -n "$n" ] || continue
        case ",$handled," in *",$n,"*) continue ;; esac
        case "$s" in
            CLOSED) ;;   # マージされずに閉じた PR は負債にならない
            *) remain="$remain #$n($s)" ;;
        esac
    done <<EOF
$(pr_states "$issue")
EOF
    if [ -n "$remain" ]; then
        echo "emergency-debt close NG: 解消の対象に含めていない由来 PR が残っているので、#$issue は閉じません:$remain" >&2
        echo "  次の解消で扱うか、--handled に含めて扱い直してください" >&2
        exit 2
    fi
    gh issue close "$issue" --comment "PR #$settled で解消しました（対象の由来 PR: $(printf '%s' "$handled" | sed 's/\([0-9][0-9]*\)/#\1/g')）。" >/dev/null \
        || die "close: #$issue を閉じられません"
    echo "emergency-debt close OK: #$issue を閉じました"
}

case "$CMD" in
    record) cmd_record ${ARGS[@]+"${ARGS[@]}"} ;;
    list) cmd_list ;;
    entries) cmd_entries ${ARGS[@]+"${ARGS[@]}"} ;;
    close) cmd_close ${ARGS[@]+"${ARGS[@]}"} ;;
    *) die "知らないコマンド: $CMD（--help で一覧）" ;;
esac
