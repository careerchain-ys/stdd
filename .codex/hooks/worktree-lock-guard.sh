#!/bin/bash
# PreToolUse Hook: subagent の書き込み先と実行先を、セッションが宣言した作業ツリーと突き合わせる。
# 登録: Claude は Edit / Write / MultiEdit / NotebookEdit と Bash（settings.json）、
#       Codex は apply_patch|Edit|Write と Bash（.codex/hooks.json）。
#
# 規律（auto-implement）: 作業ツリーで作業するとき、subagent は指定された作業ツリーの中で作業する。
#   同じ名前のファイルはほかの作業ツリーにもあるので、宛先を取り違えても編集は成功してしまい、
#   成果物からは気づけない。依頼文で注意しても防げないため、ここで機械的に確かめる。
#
# 宣言: subagent を起動する側が skills/auto-implement/scripts/worktree-lock.sh lock で宣言する。
#   宣言は git の共通ディレクトリ配下 stdd-worktree-lock/<セッション ID> に置かれる。
#   宣言の無いセッションには何もしない（ほかのセッションや宣言しない運用を止めない）。
#
# 判定（subagent の呼び出し＝入力に agent_id があるものだけ。メインのエージェントは通す）:
#   - 書き込み（Edit / Write / MultiEdit / NotebookEdit / apply_patch）: 宛先が宣言した作業ツリー
#     （または --allow のディレクトリ）の内側か。宣言した作業ツリーの中に入れ子になった別の作業ツリーは外側とみなす。
#   - Bash: 実行先（先頭の「cd <dir> &&」があればその dir、無ければ入力の cwd）が宣言した作業ツリーの内側か。
#     あわせて、コマンドの中に「宣言していない作業ツリー」の絶対パスがあれば違反とする（git -C などで
#     実行先を差し替える形）。相対パスで外へ出る形（../other など）は見ない。
#
# 強さ: .stdd.config.yml の workflow.enforce_worktree_lock = off | warn（既定）| block。
# 失敗時: 設定が無い・jq が無い・入力が読めないときは通す。
# パスは字面で判定する（シンボリックリンクは宣言時に解決した形もあわせて記録してある）。

command -v jq >/dev/null 2>&1 || exit 0
hook_input=$(cat)

jqr() { printf '%s' "$hook_input" | jq -r "$1 // empty" 2>/dev/null; }

AGENT_ID=$(jqr '.agent_id')
[ -z "$AGENT_ID" ] && exit 0
AGENT_TYPE=$(jqr '.agent_type')
TOOL=$(jqr '.tool_name')
case "$TOOL" in
    Edit|Write|MultiEdit|NotebookEdit|apply_patch|Bash) ;;
    *) exit 0 ;;
esac

SESSION=$(jqr '.session_id')
[ -n "$SESSION" ] || SESSION="${CLAUDE_CODE_SESSION_ID:-${CODEX_SESSION_ID:-${CODEX_THREAD_ID:-}}}"
[ -z "$SESSION" ] && exit 0
case "$SESSION" in
    *..*|*[!A-Za-z0-9._-]*) exit 0 ;;
esac

INPUT_CWD=$(jqr '.cwd')
[ -n "$INPUT_CWD" ] && [ -d "$INPUT_CWD" ] || INPUT_CWD=$(pwd)

PROBE="${CLAUDE_PROJECT_DIR:-$INPUT_CWD}"
COMMON=$(git -C "$PROBE" rev-parse --git-common-dir 2>/dev/null) \
    || COMMON=$(git -C "$INPUT_CWD" rev-parse --git-common-dir 2>/dev/null) || exit 0
case "$COMMON" in
    /*) ;;
    *) COMMON="$(cd "$PROBE" 2>/dev/null && cd "$COMMON" 2>/dev/null && pwd)" || exit 0 ;;
esac
LOCK_FILE="$COMMON/stdd-worktree-lock/$SESSION"
[ -f "$LOCK_FILE" ] || exit 0

DECLARED=$(sed -n 's/^root=//p' "$LOCK_FILE")
ALLOWED=$(sed -n 's/^allow=//p' "$LOCK_FILE")
[ -z "$DECLARED" ] && exit 0
DECLARED_FIRST=$(printf '%s\n' "$DECLARED" | head -n 1)

CONFIG="$DECLARED_FIRST/.stdd.config.yml"
[ -f "$CONFIG" ] || exit 0

yaml_scalar() {
    awk -v sec="$1:" -v k="$2:" '
        /^[^[:space:]]/ { insec = ($1 == sec) }
        insec && $1 == k {
            sub(/^[[:space:]]*[^:]*:[[:space:]]*/, "", $0)
            sub(/[[:space:]]+#.*$/, "", $0)
            print $0
            exit
        }
    ' "$CONFIG"
}

strip_quotes() {
    local v="$1"
    v="${v%\"}"; v="${v#\"}"
    v="${v%\'}"; v="${v#\'}"
    printf '%s' "$v"
}

MODE=$(strip_quotes "$(yaml_scalar workflow enforce_worktree_lock)")
case "$MODE" in
    off) exit 0 ;;
    block) ;;
    *) MODE=warn ;;
esac

# 登録済みの作業ツリー（宣言したもの以外）
OTHER_TREES=""
while IFS= read -r t; do
    [ -z "$t" ] && continue
    printf '%s\n' "$DECLARED" | grep -qxF -- "$t" && continue
    OTHER_TREES="$OTHER_TREES
$t"
done <<EOF
$(git -C "$DECLARED_FIRST" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
EOF

normalize_abs() {
    local p="$1" out="" seg
    local IFS='/'
    for seg in $p; do
        case "$seg" in
            ''|.) ;;
            ..) out="${out%/*}" ;;
            *) out="$out/$seg" ;;
        esac
    done
    printf '%s' "${out:-/}"
}

under() { # $1=path $2=dir
    [ "$1" = "$2" ] && return 0
    case "$1" in "$2"/*) return 0 ;; esac
    return 1
}

under_any() { # $1=path, $2=改行区切りのディレクトリ
    local d
    while IFS= read -r d; do
        [ -z "$d" ] && continue
        under "$1" "$d" && return 0
    done <<EOF
$2
EOF
    return 1
}

# 宣言の内側か（宣言の中に入れ子になった別の作業ツリーは外側）
inside_declared() {
    local p="$1"
    under_any "$p" "$ALLOWED" && return 0
    under_any "$p" "$DECLARED" || return 1
    local o
    while IFS= read -r o; do
        [ -z "$o" ] && continue
        if under "$p" "$o" && under_any "$o" "$DECLARED"; then
            return 1
        fi
    done <<EOF
$OTHER_TREES
EOF
    return 0
}

to_abs() {
    case "$1" in
        /*) normalize_abs "$1" ;;
        *) normalize_abs "$2/$1" ;;
    esac
}

violation() {
    local reason="STDD worktree-lock: ${AGENT_TYPE:-subagent} が宣言した作業ツリー（$DECLARED_FIRST）の外を$1。\
宣言した作業ツリーの中で作業してください（Bash は「cd $DECLARED_FIRST && <コマンド>」の形で実行する）。\
宣言が誤っているなら、呼び出し元が worktree-lock.sh lock で宣言し直します。"
    if [ "$MODE" = "block" ]; then
        jq -n --arg r "$reason" \
            '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    else
        jq -n --arg r "$reason（enforce_worktree_lock=warn のため操作は止めていません）" \
            '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$r}}'
    fi
    exit 0
}

check_target() {
    local abs
    abs=$(to_abs "$1" "$INPUT_CWD")
    inside_declared "$abs" || violation "編集しようとしています（$abs）"
}

case "$TOOL" in
    Edit|Write|MultiEdit|NotebookEdit)
        P=$(jqr '.tool_input.file_path')
        [ -z "$P" ] && P=$(jqr '.tool_input.notebook_path')
        [ -n "$P" ] && check_target "$P"
        exit 0 ;;
    apply_patch)
        CMD=$(jqr '.tool_input.command')
        FILES=$(printf '%s\n' "$CMD" | sed -n -E 's/^\*\*\* (Add|Update|Delete) File: (.+)$/\2/p; s/^\*\*\* Move to: (.+)$/\1/p')
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            check_target "$f"
        done <<EOF
$FILES
EOF
        exit 0 ;;
esac

# --- Bash ---
CMD=$(jqr '.tool_input.command')
[ -z "$CMD" ] && exit 0

# 実行先: 先頭の cd <dir> &&（引用符つきも可）
RUN_DIR="$INPUT_CWD"
CD_TARGET=$(printf '%s' "$CMD" | sed -n -E '1s/^[[:space:]]*cd[[:space:]]+("([^"]+)"|'"'"'([^'"'"']+)'"'"'|([^[:space:];&|]+))[[:space:]]*&&.*$/\2\3\4/p')
[ -n "$CD_TARGET" ] && RUN_DIR=$(to_abs "$CD_TARGET" "$INPUT_CWD")
RUN_DIR=$(normalize_abs "$RUN_DIR")
inside_declared "$RUN_DIR" || violation "実行先にしてコマンドを実行しようとしています（実行先 $RUN_DIR）"

# コマンドの中の絶対パスのうち、宣言していない作業ツリーを指すもの（glob は展開しない）
set -f
for tok in $(printf '%s' "$CMD" | tr '"'"'"'=:;&|<>()`' '            '); do
    case "$tok" in
        /*) ;;
        *) continue ;;
    esac
    p=$(normalize_abs "$tok")
    inside_declared "$p" && continue
    under_any "$p" "$OTHER_TREES" && violation "指すパスを含むコマンドを実行しようとしています（$p）"
done
exit 0
