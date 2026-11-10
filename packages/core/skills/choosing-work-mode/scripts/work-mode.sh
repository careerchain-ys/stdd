#!/bin/bash
# work-mode.sh — 作業モード（通常 / 緊急）の宣言・確認・解除。
#
# 使い方:
#   work-mode.sh [--root <dir>] <command> [args]
#
#   declare --reason <理由>  現在のブランチで緊急モードを宣言する。ユーザーの申し出の記録
#                            （フック work-mode-prompt.sh が残すもの）が有効期限内に無ければ宣言しない。
#                            宣言に使った申し出の記録は消す（1 回の申し出で宣言できるのは 1 回）
#   active                   現在のブランチで緊急モードが有効なら exit 0、無効なら exit 1（何も出さない）
#   status                   現在のブランチの作業モードを表示する
#   clear                    現在のブランチの宣言を消す（通常モードに戻す）
#
# 緊急モードで何を緩め、何を守るかの正本は ../SKILL.md。このスクリプトは宣言の記録だけを扱う。
#
# 宣言はブランチごとで、別のブランチには効かない。置き場は作業ツリーの外（git の共通ディレクトリ配下の
# stdd-work-mode/<ブランチ名の / を __ に置き換えたもの>）なので、コミットにも差分にも入らない。
# 形式は 1 行 1 項目の key=value（mode / branch / reason / declared_at / requested_at / request）。
#
# 改ざん耐性は持たない。置き場は誰でも書けるので、記録の意味は「ユーザーが選んだことの控え」である。
# エージェントが申し出や宣言のファイルを直接書くことは skill と規約で禁じる。
#
# 設定: .stdd.config.yml の emergency_mode
#   enabled              false なら declare を拒否し、active は常に無効を返す（既定 true）
#   request_ttl_minutes  申し出の記録の有効期限（分。既定 120）
# 依存: bash 3.2 以上、git。

set -u

ROOT=""
CMD=""
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --root) ROOT="${2:-}"; shift 2 ;;
        --help|-h) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)
            if [ -z "$CMD" ]; then CMD="$1"; else ARGS+=("$1"); fi
            shift ;;
    esac
done

die() { echo "work-mode NG: $*" >&2; exit 1; }

[ -n "$CMD" ] || die "コマンドを指定してください（declare / active / status / clear。--help で一覧）"

if [ -z "$ROOT" ]; then
    ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
CONFIG="$ROOT/.stdd.config.yml"

# ---------------------------------------------------------------------------
# .stdd.config.yml（外部依存なしのパーサ）
# ---------------------------------------------------------------------------
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
primary_branch() {
    [ -f "$CONFIG" ] || { echo main; return; }
    local v
    v=$(awk '
        /^[^[:space:]#]/ { insec = ($1 == "project:"); next }
        insec && $1 == "primary_branch:" { sub(/^[[:space:]]*[^:]*:[[:space:]]*/, ""); print; exit }
    ' "$CONFIG" | tr -d "\"'" | sed 's/[[:space:]]#.*$//; s/[[:space:]]*$//')
    printf '%s' "${v:-main}"
}

ENABLED=$(cfg enabled true)
TTL_MIN=$(cfg request_ttl_minutes 120)
case "$TTL_MIN" in ''|*[!0-9]*) TTL_MIN=120 ;; esac

now_epoch() { printf '%s' "${STDD_NOW:-$(date +%s)}"; }
current_branch() { git -C "$ROOT" branch --show-current 2>/dev/null; }

state_dir() {
    local common
    common=$(cd "$ROOT" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd) || return 1
    printf '%s/stdd-work-mode' "$common"
}
declaration_file() {
    local d
    d=$(state_dir) || return 1
    printf '%s/%s' "$d" "$(printf '%s' "$1" | sed 's|/|__|g')"
}

# key=value の値を読む: $1 = ファイル, $2 = key
field() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1; }

# 宣言が現在のブランチで有効か。読めない・欄が欠ける・ブランチが違う宣言は無効として扱う
#   ブランチ名の / → __ の置き換えは一対一ではないので、ファイル名ではなく中の branch で照合する
is_active() {
    local branch="$1" f
    [ "$ENABLED" = "false" ] && return 1
    [ -n "$branch" ] || return 1
    f=$(declaration_file "$branch") || return 1
    [ -f "$f" ] || return 1
    [ "$(field "$f" mode)" = "emergency" ] || return 1
    [ "$(field "$f" branch)" = "$branch" ] || return 1
    [ -n "$(field "$f" reason)" ] || return 1
    case "$(field "$f" declared_at)" in ''|*[!0-9]*) return 1 ;; esac
    return 0
}

fmt_time() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '%s' "$1"; }

cmd_active() {
    is_active "$(current_branch)" && exit 0
    exit 1
}

cmd_status() {
    local branch f
    branch=$(current_branch)
    [ -n "$branch" ] || die "ブランチを解決できません（git の作業ツリーでないか detached HEAD: $ROOT）"
    if is_active "$branch"; then
        f=$(declaration_file "$branch")
        echo "作業モード: 緊急モード（ブランチ $branch ・ 宣言 $(fmt_time "$(field "$f" declared_at)") ・ 理由: $(field "$f" reason)）"
        echo "  ユーザーの申し出: $(field "$f" request)"
    else
        echo "作業モード: 通常モード（ブランチ $branch）"
    fi
}

cmd_clear() {
    local branch f
    branch=$(current_branch)
    [ -n "$branch" ] || die "ブランチを解決できません（git の作業ツリーでないか detached HEAD: $ROOT）"
    f=$(declaration_file "$branch") || die "宣言の置き場を決められません"
    if [ -f "$f" ]; then
        rm -f "$f" || die "宣言を消せません: $f"
        echo "work-mode OK: 緊急モードの宣言を消しました（ブランチ $branch）。以降は通常モードです"
    else
        echo "work-mode OK: 宣言はありません（ブランチ $branch は通常モード）"
    fi
}

cmd_declare() {
    local reason=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --reason) reason="${2:-}"; shift 2 ;;
            *) die "declare: 知らない引数: $1" ;;
        esac
    done
    [ "$ENABLED" = "false" ] && die "emergency_mode.enabled が false のため、このプロジェクトでは緊急モードを使えません"
    reason=$(printf '%s' "$reason" | tr '\r\n\t' '   ' | sed 's/  */ /g; s/^ //; s/ $//')
    [ -n "$reason" ] || die "--reason に理由がありません（ユーザーが述べた理由を 1 行で書く）"

    local branch
    branch=$(current_branch)
    [ -n "$branch" ] || die "ブランチを解決できません（detached HEAD では宣言しない: $ROOT）"
    [ "$branch" = "$(primary_branch)" ] && die "主ブランチ（$branch）では宣言しません。作業用のブランチを作ってから宣言してください"

    local dir req requested_at request now age
    dir=$(state_dir) || die "宣言の置き場を決められません（git の作業ツリーではない: $ROOT）"
    req="$dir/request"
    if [ ! -f "$req" ]; then
        echo "work-mode NG: ユーザーの申し出の記録がありません" >&2
        echo "  緊急モードは、ユーザーが発言で「緊急モード」と明示したときだけ宣言できます（フック work-mode-prompt.sh が記録する）" >&2
        echo "  エージェントの判断では宣言しません。必要ならユーザーに作業モードを尋ねてください" >&2
        exit 1
    fi
    requested_at=$(field "$req" requested_at)
    request=$(field "$req" request)
    case "$requested_at" in ''|*[!0-9]*) die "申し出の記録が読めません: $req" ;; esac
    now=$(now_epoch)
    age=$(( (now - requested_at) / 60 ))
    if [ "$age" -gt "$TTL_MIN" ]; then
        echo "work-mode NG: ユーザーの申し出の記録が古すぎます（${age} 分前。有効期限 ${TTL_MIN} 分）" >&2
        echo "  緊急モードで進めるかを、もう一度ユーザーに確かめてください" >&2
        exit 1
    fi

    local f
    f=$(declaration_file "$branch") || die "宣言の置き場を決められません"
    mkdir -p "$dir" || die "宣言の置き場を作れません: $dir"
    {
        printf 'mode=emergency\n'
        printf 'branch=%s\n' "$branch"
        printf 'reason=%s\n' "$reason"
        printf 'declared_at=%s\n' "$now"
        printf 'requested_at=%s\n' "$requested_at"
        printf 'request=%s\n' "$request"
    } > "$f" || die "宣言を書けません: $f"
    rm -f "$req"
    echo "work-mode OK: 緊急モードを宣言しました（ブランチ $branch）"
    echo "  PR 本文の冒頭に「## 緊急モード」の節を書き、工程テレメトリは --exempt emergency で投稿してください"
}

case "$CMD" in
    declare) cmd_declare ${ARGS[@]+"${ARGS[@]}"} ;;
    active) cmd_active ;;
    status) cmd_status ;;
    clear) cmd_clear ;;
    *) die "知らないコマンド: $CMD（declare / active / status / clear）" ;;
esac
