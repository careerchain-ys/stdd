#!/bin/bash
# work-overlap.sh — 並行作業の重なりの検出（依存なし。PR の確認にだけ gh を使う）
#
# 手を付ける（付けた）ファイルが、ほかの作業と重なっていないかを着手前に確かめる。
#   1. ほかの作業ツリー: 主ブランチからの差分（コミット済み）と、未コミットの変更（未追跡を含む）
#   2. 作成中の PR: open な PR の変更ファイル（いまのブランチの PR は除く）
# 規律の本文は STDD の方法論「並行作業の規律」（parallel-work.md）。
#
# 使い方:
#   work-overlap.sh                          いまの作業ツリーの変更（差分 + 未コミット）を対象にする
#   work-overlap.sh --path <p> [--path <p>]  触る予定のファイル・ディレクトリを対象にする（着手前）
#   オプション: --base <ref>（比較の基点。既定 origin/<project.primary_branch>）/ --no-pr（PR を確かめない）
#
# 終了コード: 0 = 重なりなし / 2 = 重なりあり / 1 = 引数の誤り・読み取りの失敗
#   どこか 1 か所でも読めなければ「重なりなし」とは言わない（重なりを見つけていても 1）。
#
# 参照する設定（.stdd.config.yml）: project.primary_branch（無ければ main）。設定が無くても動く。
# ほかの作業ツリーで動かす git には --no-optional-locks を付け、index を書き換えない。

set -u
set -o pipefail

PATHS=()
BASE=""
CHECK_PR=1
PR_LIMIT=200

usage() { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; }
fail() { echo "work-overlap NG: $1" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --path) [ $# -ge 2 ] && [ -n "$2" ] || fail "--path に値が無い"; PATHS+=("$2"); shift 2 ;;
        --base) [ $# -ge 2 ] && [ -n "$2" ] || fail "--base に値が無い"; BASE="$2"; shift 2 ;;
        --no-pr) CHECK_PR=0; shift ;;
        --help|-h) usage; exit 0 ;;
        *) fail "未知の引数: $1（--help を参照）" ;;
    esac
done

TOP=$(git rev-parse --show-toplevel 2>/dev/null) || fail "git の作業ツリーの中で実行してください"
PREFIX=$(git rev-parse --show-prefix 2>/dev/null)
TOP_REAL=$(cd "$TOP" && pwd -P)

if [ -z "$BASE" ]; then
    BRANCH=""
    if [ -f "$TOP/.stdd.config.yml" ]; then
        BRANCH=$(awk '
            /^[^[:space:]]/ { insec = ($1 == "project:") }
            insec && $1 == "primary_branch:" { sub(/^[[:space:]]*primary_branch:[[:space:]]*/, ""); print; exit }
        ' "$TOP/.stdd.config.yml" | sed -e 's/[[:space:]]*#.*$//' -e 's/^["'\'']//' -e 's/["'\'']$//')
    else
        echo "work-overlap: .stdd.config.yml が無いので主ブランチを main とみなします" >&2
    fi
    BASE="origin/${BRANCH:-main}"
fi
git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null || fail "比較の基点 $BASE が見つからない（git fetch するか --base で指定する）"

# --- 対象のパス（リポジトリ相対） ------------------------------------------------
TARGETS_FILE=$(mktemp "${TMPDIR:-/tmp}/work-overlap.XXXXXX")
FOUND_FILE=$(mktemp "${TMPDIR:-/tmp}/work-overlap.XXXXXX")
trap 'rm -f "$TARGETS_FILE" "$FOUND_FILE"' EXIT

normalize() {
    local p="$1"
    case "$p" in
        "$TOP") echo ""; return ;;
        "$TOP"/*) p="${p#"$TOP"/}" ;;
        /*) return 1 ;;
        *) p="$PREFIX$p" ;;
    esac
    while [ "${p#./}" != "$p" ]; do p="${p#./}"; done
    p="${p//\/.\//\/}"
    while [ "${p%/}" != "$p" ] || [ "${p%/.}" != "$p" ]; do p="${p%/}"; p="${p%/.}"; done
    [ "$p" = "." ] && p=""
    case "/$p/" in */../*) return 1 ;; esac
    printf '%s\n' "$p"
}

# git status --porcelain -z の出力からパスを取り出す（改名は新旧の両方）
status_paths() {
    local rec code
    while IFS= read -r -d '' rec; do
        code="${rec:0:2}"
        printf '%s\n' "${rec:3}"
        case "$code" in
            R*|C*|?R|?C) IFS= read -r -d '' rec && printf '%s\n' "$rec" ;;
        esac
    done
}

# $1 = 作業ツリーのパス。主ブランチからの差分と未コミットの変更のパスを出す。
changed_paths() {
    local wt="$1" diff status
    diff=$(git -C "$wt" --no-optional-locks diff --name-only "$BASE...HEAD" 2>/dev/null) || return 1
    status=$(git -C "$wt" --no-optional-locks status --porcelain -z --untracked-files=all 2>/dev/null | status_paths) || return 1
    printf '%s\n%s\n' "$diff" "$status" | grep -v '^$' | sort -u || true
}

if [ ${#PATHS[@]} -gt 0 ]; then
    for raw in "${PATHS[@]}"; do
        n=$(normalize "$raw") || fail "--path がリポジトリの外を指している: $raw"
        [ -n "$n" ] || fail "--path がリポジトリ全体を指している（何とでも重なる）: $raw"
        printf '%s\n' "$n" >> "$TARGETS_FILE"
    done
else
    changed_paths "$TOP" > "$TARGETS_FILE" || fail "いまの作業ツリーの変更を読めない"
fi
sort -u "$TARGETS_FILE" -o "$TARGETS_FILE"
TARGET_COUNT=$(grep -c . "$TARGETS_FILE")
if [ "$TARGET_COUNT" -eq 0 ]; then
    fail "対象のファイルが無い（着手前なら --path で触る予定のファイルを指定する）"
fi

# 同じパス、またはどちらかがもう一方のディレクトリの配下なら重なる
overlaps() {
    local a="$1" b="$2"
    [ "$a" = "$b" ] && return 0
    case "$b" in "$a"/*) return 0 ;; esac
    case "$a" in "$b"/*) return 0 ;; esac
    return 1
}

# $1 = 相手の説明、標準入力 = 相手のパス
match_against() {
    local who="$1" theirs mine
    while IFS= read -r theirs; do
        [ -n "$theirs" ] || continue
        while IFS= read -r mine; do
            if overlaps "$mine" "$theirs"; then
                printf '%s\t%s\t%s\n' "$mine" "$theirs" "$who" >> "$FOUND_FILE"
            fi
        done < "$TARGETS_FILE"
    done
}

FAILED=0

# --- 1. ほかの作業ツリー ---------------------------------------------------------
WT_COUNT=0
wt_path=""; wt_branch=""; wt_skip=0
flush_worktree() {
    if [ -n "$wt_path" ] && [ "$wt_skip" -eq 0 ] && [ "$wt_path" != "$TOP_REAL" ]; then
        local files
        if files=$(changed_paths "$wt_path"); then
            WT_COUNT=$((WT_COUNT + 1))
            printf '%s\n' "$files" | match_against "作業ツリー $wt_path（ブランチ ${wt_branch:-detached}）"
        else
            echo "work-overlap: 作業ツリーを読めない: $wt_path" >&2
            FAILED=1
        fi
    fi
    wt_path=""; wt_branch=""; wt_skip=0
}
WT_LIST=$(git worktree list --porcelain 2>/dev/null) || fail "git worktree list を読めない"
while IFS= read -r line; do
    case "$line" in
        "worktree "*) flush_worktree; wt_path="${line#worktree }"
            # 比較のため実体のパスにそろえる（/tmp と /private/tmp など）
            [ -d "$wt_path" ] && wt_path=$(cd "$wt_path" && pwd -P) ;;
        "branch "*) wt_branch="${line#branch refs/heads/}" ;;
        bare|prunable*) wt_skip=1 ;;
        "") flush_worktree ;;
    esac
done <<EOF
$WT_LIST
EOF
flush_worktree

# --- 2. 作成中の PR ---------------------------------------------------------------
PR_COUNT=0
if [ "$CHECK_PR" -eq 1 ]; then
    if ! command -v gh >/dev/null 2>&1; then
        echo "work-overlap: gh が無いので作成中の PR を確かめられない（確かめないなら --no-pr）" >&2
        FAILED=1
    else
        CURRENT=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        if PR_LINES=$(gh pr list --state open --limit "$PR_LIMIT" --json number,headRefName,files \
            --jq '.[] | "PR\t\(.number)\t\(.headRefName)", (.number as $n | .headRefName as $h | .files[]? | "F\t\($n)\t\($h)\t\(.path)")' 2>/dev/null); then
            PR_COUNT=$(printf '%s\n' "$PR_LINES" | grep -c '^PR	')
            if [ "$PR_COUNT" -ge "$PR_LIMIT" ]; then
                echo "work-overlap: open な PR が $PR_LIMIT 本に達した（打ち切られている可能性がある）" >&2
                FAILED=1
            fi
            printf '%s\n' "$PR_LINES" | while IFS="$(printf '\t')" read -r kind num head file; do
                [ "$kind" = "F" ] || continue
                [ "$head" = "$CURRENT" ] && continue
                printf '%s\n' "$file" | match_against "PR #$num（ブランチ $head）"
            done
        else
            echo "work-overlap: gh pr list を読めない（gh auth status を確かめる。確かめないなら --no-pr）" >&2
            FAILED=1
        fi
    fi
fi

# --- 結果 ------------------------------------------------------------------------
FOUND=$(grep -c . "$FOUND_FILE")
if [ "$FOUND" -gt 0 ]; then
    echo "重なりがあります。着手する前に、相手の作業の担当者と分担を決めてください:"
    sort -u "$FOUND_FILE" | while IFS="$(printf '\t')" read -r mine theirs who; do
        if [ "$mine" = "$theirs" ]; then
            echo "  - $mine  ← $who"
        else
            echo "  - $mine（相手は $theirs）  ← $who"
        fi
    done
fi
PR_NOTE="作成中の PR ${PR_COUNT} 本"
[ "$CHECK_PR" -eq 1 ] || PR_NOTE="作成中の PR は未確認"
echo "work-overlap: 対象 ${TARGET_COUNT} 件、ほかの作業ツリー ${WT_COUNT} 本、${PR_NOTE}。重なり ${FOUND} 件（基点 $BASE）"

[ "$FAILED" -eq 1 ] && exit 1
[ "$FOUND" -gt 0 ] && exit 2
exit 0
