#!/bin/bash
# worktree-lock.sh — このセッションが作業する作業ツリーを 1 つ宣言する。
#
# 使い方:
#   worktree-lock.sh lock [--root <dir>] [--allow <dir>]... [--session <id>]
#   worktree-lock.sh status [--session <id>]
#   worktree-lock.sh unlock [--session <id>]
#
#   lock    --root（既定はカレントの作業ツリー）を宣言する。--allow は作業ツリーの外で書いてよい
#           ディレクトリ（一時ディレクトリなど。複数可）。宣言し直すと前の宣言を置き換える
#   status  宣言の内容を表示する。宣言時と現在のブランチが違えば警告する
#   unlock  宣言を外す
#
# 宣言すると、フック worktree-lock-guard.sh が、このセッションから起動した subagent の書き込み先と
# 実行先を宣言と突き合わせる。宣言するのは subagent を起動する側（メインのエージェント）で、
# subagent 自身ではない。宣言の無いセッションには何もしない。
#
# セッション ID は --session、無ければ環境変数 CLAUDE_CODE_SESSION_ID / CODEX_SESSION_ID /
# CODEX_THREAD_ID の順に使う（フックが受け取る session_id と同じ値）。
# 置き場は git の共通ディレクトリ配下の stdd-worktree-lock/<セッション ID>（作業ツリーの外。コミットに入らない）。
# 形式は 1 行 1 項目の key=value（root / allow / branch / declared_at）。root は字面と実体
# （シンボリックリンクを解決したもの）が違えば両方を書く。
# 依存: bash 3.2 以上、git。

set -u

CMD=""; ROOT=""; SESSION=""; ALLOWS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --root) ROOT="${2:-}"; shift 2 ;;
        --allow) ALLOWS+=("${2:-}"); shift 2 ;;
        --session) SESSION="${2:-}"; shift 2 ;;
        --help|-h) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        lock|status|unlock)
            [ -z "$CMD" ] || { echo "worktree-lock NG: コマンドは 1 つだけ指定してください" >&2; exit 1; }
            CMD="$1"; shift ;;
        *) echo "worktree-lock NG: 未知の引数: $1（--help で一覧）" >&2; exit 1 ;;
    esac
done

die() { echo "worktree-lock NG: $*" >&2; exit 1; }

[ -n "$CMD" ] || die "コマンドを指定してください（lock / status / unlock）"

[ -n "$SESSION" ] || SESSION="${CLAUDE_CODE_SESSION_ID:-${CODEX_SESSION_ID:-${CODEX_THREAD_ID:-}}}"
[ -n "$SESSION" ] || die "セッション ID を決められません。--session <id> を指定してください"
case "$SESSION" in
    *..*|*[!A-Za-z0-9._-]*) die "セッション ID にファイル名に使えない文字があります: $SESSION" ;;
esac

BASE="${ROOT:-.}"
[ -d "$BASE" ] || die "ディレクトリがありません: $BASE"
COMMON=$(git -C "$BASE" rev-parse --git-common-dir 2>/dev/null) || die "git リポジトリではありません: $BASE"
case "$COMMON" in
    /*) ;;
    *) COMMON="$(cd "$BASE" && cd "$COMMON" && pwd)" ;;
esac
LOCK_DIR="$COMMON/stdd-worktree-lock"
LOCK_FILE="$LOCK_DIR/$SESSION"

case "$CMD" in
    status)
        if [ ! -f "$LOCK_FILE" ]; then
            echo "worktree-lock: 宣言なし（セッション $SESSION）"
            exit 0
        fi
        cat "$LOCK_FILE"
        root=$(sed -n 's/^root=//p' "$LOCK_FILE" | head -n 1)
        branch=$(sed -n 's/^branch=//p' "$LOCK_FILE" | head -n 1)
        now=$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
        if [ -n "$branch" ] && [ -n "$now" ] && [ "$branch" != "$now" ]; then
            echo "警告: 宣言時のブランチ（$branch）と現在のブランチ（$now）が違います。作業先を確かめてください" >&2
        fi
        exit 0 ;;
    unlock)
        rm -f "$LOCK_FILE"
        echo "worktree-lock: 宣言を外しました（セッション $SESSION）"
        exit 0 ;;
esac

TOP=$(git -C "$BASE" rev-parse --show-toplevel 2>/dev/null) || die "作業ツリーのルートを決められません: $BASE"
REAL=$(cd "$TOP" && pwd -P)
BRANCH=$(git -C "$TOP" rev-parse --abbrev-ref HEAD 2>/dev/null || true)

mkdir -p "$LOCK_DIR" || die "置き場を作れません: $LOCK_DIR"
{
    echo "root=$TOP"
    [ "$REAL" != "$TOP" ] && echo "root=$REAL"
    for a in ${ALLOWS[@]+"${ALLOWS[@]}"}; do
        [ -d "$a" ] || die "--allow のディレクトリがありません: $a"
        a_abs=$(cd "$a" && pwd)
        a_real=$(cd "$a" && pwd -P)
        echo "allow=$a_abs"
        [ "$a_real" != "$a_abs" ] && echo "allow=$a_real"
    done
    echo "branch=$BRANCH"
    echo "declared_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$LOCK_FILE.tmp" && mv "$LOCK_FILE.tmp" "$LOCK_FILE" || die "宣言を書けません: $LOCK_FILE"

MAIN_TOP=$(git -C "$COMMON/.." rev-parse --show-toplevel 2>/dev/null || true)
if [ -n "$MAIN_TOP" ] && [ "$MAIN_TOP" = "$TOP" ]; then
    echo "警告: メインの作業ツリーを宣言しました。並行して作業するときは、作業ツリーを分けてから宣言してください" >&2
fi
echo "worktree-lock: $TOP を宣言しました（ブランチ $BRANCH / セッション $SESSION）"
