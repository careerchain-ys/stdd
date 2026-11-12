#!/bin/bash
# PreToolUse Hook: レビューする subagent が、レビューされる作業ツリーを書き換えないことを確かめる。
# 登録: Claude は Edit / Write / MultiEdit / NotebookEdit と Bash（settings.json）、
#       Codex は apply_patch|Edit|Write と Bash（.codex/hooks.json）。
#
# 規律（agents/*-reviewer.md）:
#   - reviewer（requirements-reviewer / tech-specs-reviewer / test-reviewer / code-reviewer）は、レビューされる作業ツリーを書き換えない。
#     書いた本人とは別の目で見る役割なので、指摘は結果として返し、直すのは呼び出し元に任せる。
#   - code-reviewer / test-reviewer は、自分の作業ツリー（isolation: worktree）でテストや再現のスクリプトを実行してよい。
#   tools の指定だけでは Bash 経由の書き込みを防げないため、ここで確かめる（方針は docs/discipline-automation.md §3.1）。
#
# 判定:
#   - 対象は subagent の呼び出しだけ（入力に agent_id があるもの）。メインのエージェントは通す。
#     agent_type が上の 4 種のどれか、またはその名前に「-」と続けたもの（agent teams のメンバーに付ける
#     code-reviewer-security など）でなければ通す（qa-engineer などは対象外）。
#   - 「分離されている」とは、subagent の cwd（入力の .cwd）の git toplevel が、レビューされる作業ツリー
#     （CLAUDE_PROJECT_DIR の toplevel）と違うこと。
#   - 分離されているとき:
#       Bash は通す。
#       書き込みは、書き込み先の git toplevel がレビューされる作業ツリーと同じときだけ違反。
#       まだ無いファイルは、存在する最も近い親ディレクトリで判定する。Claude の worktree は .claude/worktrees/ の下、
#       つまりレビューされる作業ツリーのパスの中にできるので、パスの前方一致では判定しない。
#   - 分離されていないとき、または CLAUDE_PROJECT_DIR が無いとき（Codex など）は、読み取りのみに制限する:
#       書き込みは宛先を問わず違反。
#       Bash は 1 回の呼び出しで 1 コマンドだけを許す。連結・パイプ・リダイレクト・置換・改行を含めば違反。
#       残った 1 コマンドが読み取りの許可一覧（下の is_read_only_command）に一致しなければ違反。
#       前方一致で許すと、連結や書き込み用のオプションで抜けられるため、完全一致で判定する。
#
# 強さ: .stdd.config.yml の workflow.enforce_agent_scope = off | warn（既定）| block。
#   warn は違反を文脈に知らせるだけで、操作は止めない。block は拒否する。
#   設定はレビューされる作業ツリーのものを読む（無ければ cwd の作業ツリーのもの）。
# 失敗時: 設定が無い・jq が無い・入力が読めないときは通す（フックの故障で作業を止めない）。
#
# 限界:
#   - 分離されたシェルから、絶対パスでレビューされる作業ツリーを書き換えることは防げない（コマンドの字面を解釈しない）。
#     統合のときに、メインのセッションが git status --porcelain と HEAD が変わっていないことを確かめて検出する
#     （auto-implement の phases.md「reviewer の使い方」）。
#   - 名前を付けて起動した subagent・agent teams のメンバーは、agent_type に付けた名前が入ることがある。
#     reviewer に名前を付けるときは agent の名前で始める（auto-implement の phases.md「起動の仕方」）。
#   - シンボリックリンクの先は追わない（読み取りのみの判定では字面で判定する）。

command -v jq >/dev/null 2>&1 || exit 0
hook_input=$(cat)

jqr() { printf '%s' "$hook_input" | jq -r "$1 // empty" 2>/dev/null; }

AGENT_ID=$(jqr '.agent_id')
[ -z "$AGENT_ID" ] && exit 0
AGENT_TYPE=$(jqr '.agent_type')
case "$AGENT_TYPE" in
    requirements-reviewer|tech-specs-reviewer|test-reviewer|code-reviewer) ;;
    requirements-reviewer-*|tech-specs-reviewer-*|test-reviewer-*|code-reviewer-*) ;;
    *) exit 0 ;;
esac

TOOL=$(jqr '.tool_name')
INPUT_CWD=$(jqr '.cwd')
[ -n "$INPUT_CWD" ] && [ -d "$INPUT_CWD" ] || INPUT_CWD=$(pwd)

toplevel_of() { git -C "$1" rev-parse --show-toplevel 2>/dev/null; }

CWD_TOP=$(toplevel_of "$INPUT_CWD") || exit 0
PROJECT_TOP=""
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
    PROJECT_TOP=$(toplevel_of "$CLAUDE_PROJECT_DIR") || PROJECT_TOP=""
fi
ISOLATED=0
[ -n "$PROJECT_TOP" ] && [ "$PROJECT_TOP" != "$CWD_TOP" ] && ISOLATED=1

CONFIG=""
[ -n "$PROJECT_TOP" ] && [ -f "$PROJECT_TOP/.stdd.config.yml" ] && CONFIG="$PROJECT_TOP/.stdd.config.yml"
[ -z "$CONFIG" ] && [ -f "$CWD_TOP/.stdd.config.yml" ] && CONFIG="$CWD_TOP/.stdd.config.yml"
[ -n "$CONFIG" ] || exit 0

# --- .stdd.config.yml パーサ（外部依存なし。spec-first-check.sh と同じ流儀） ---

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

MODE=$(strip_quotes "$(yaml_scalar workflow enforce_agent_scope)")
case "$MODE" in
    off) exit 0 ;;
    block) ;;
    *) MODE=warn ;;
esac

# --- パスの扱い ---

# 字面で正規化する（. と .. を畳む。シンボリックリンクは追わない）
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

# --- 違反の通知 ---

violation() {
    local reason="STDD agent-scope: $1"
    if [ "$MODE" = "block" ]; then
        jq -n --arg r "$reason" \
            '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    else
        jq -n --arg r "$reason（enforce_agent_scope=warn のため操作は止めていません）" \
            '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$r}}'
    fi
    exit 0
}

# --- 書き込みの判定 ---

check_write_target() {
    local p="$1" abs
    case "$p" in
        /*) abs="$p" ;;
        *) abs="$INPUT_CWD/$p" ;;
    esac
    abs=$(normalize_abs "$abs")
    if [ "$ISOLATED" = 1 ]; then
        # まだ無いファイルは、存在する最も近い親ディレクトリで判定する
        local d="$abs" top
        [ -d "$d" ] || d=$(dirname "$d")
        while [ ! -d "$d" ] && [ "$d" != "/" ]; do d=$(dirname "$d"); done
        top=$(toplevel_of "$d") || return 0
        [ "$top" = "$PROJECT_TOP" ] || return 0
        violation "$AGENT_TYPE はレビューされる作業ツリー（$PROJECT_TOP）を書き換えない担当ですが、$abs を編集しようとしています。再現用のファイルは自分の作業ツリー（$CWD_TOP）に置き、指摘はレビュー結果として返してください。"
    fi
    violation "$AGENT_TYPE はファイルを書き換えない担当ですが、$abs を編集しようとしています。指摘はレビュー結果として返してください。"
}

case "$TOOL" in
    Edit|Write|MultiEdit|NotebookEdit)
        P=$(jqr '.tool_input.file_path')
        [ -z "$P" ] && P=$(jqr '.tool_input.notebook_path')
        [ -z "$P" ] && exit 0
        check_write_target "$P"
        exit 0
        ;;
    apply_patch)
        CMD=$(jqr '.tool_input.command')
        FILES=$(printf '%s\n' "$CMD" | sed -n -E 's/^\*\*\* (Add|Update|Delete) File: (.+)$/\2/p; s/^\*\*\* Move to: (.+)$/\1/p')
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            check_write_target "$f"
        done <<EOF
$FILES
EOF
        exit 0
        ;;
    Bash) ;;
    *) exit 0 ;;
esac

# --- Bash の判定 ---

# 分離されていれば通す（自分の作業ツリーでテストや再現を実行する。限界はヘッダーのコメント）
[ "$ISOLATED" = 1 ] && exit 0

CMD=$(jqr '.tool_input.command')
[ -z "$CMD" ] && exit 0

READ_ONLY_HINT="作業ツリーが分かれていないので、使えるのは読み取りのコマンド（ls / cat / head / tail / wc / grep / rg / find / pwd、git の log / show / diff / status / blame / ls-files / rev-parse / grep、bash .claude/hooks/trace-audit.sh）を 1 回に 1 つだけです。ファイルの編集は Edit / Write で行ってください。"

# シェルの制御文字（連結・パイプ・リダイレクト・置換・グループ・行継続・改行）
# （$ は展開につながる形だけを拒否する。正規表現の行末の $ は通す）
case "$CMD" in
    *';'*|*'&'*|*'|'*|*'>'*|*'<'*|*'`'*|*'$('*|*'${'*|*'$'[A-Za-z_0-9@*#?!-]*|*'('*|*')'*|*'{'*|*'}'*|*'\'*)
        violation "$AGENT_TYPE のシェル実行に、連結・パイプ・リダイレクト・置換のいずれかが含まれています（$CMD）。$READ_ONLY_HINT" ;;
esac
NL='
'
case "$CMD" in
    *"$NL"*) violation "$AGENT_TYPE のシェル実行が複数行です。$READ_ONLY_HINT" ;;
esac

# 読み取りの許可一覧。1 語目（と git はサブコマンド）で決め、書き込みや外部コマンドの起動につながる
# オプションを個別に拒否する。
is_read_only_command() {
    # shellcheck disable=SC2086
    set -- $1
    local head="$1" a
    shift
    case "$head" in
        ls|cat|head|tail|wc|grep|pwd) return 0 ;;
        rg)
            for a in "$@"; do
                case "$a" in --pre|--pre=*|--pre-glob*) return 1 ;; esac
            done
            return 0 ;;
        find)
            for a in "$@"; do
                case "$a" in -exec|-execdir|-ok|-okdir|-delete|-fprint|-fprint0|-fprintf|-fls) return 1 ;; esac
            done
            return 0 ;;
        git)
            case "$1" in
                log|show|diff|status|blame|ls-files|rev-parse|grep) ;;
                *) return 1 ;;
            esac
            shift
            for a in "$@"; do
                case "$a" in
                    --output|--output=*|-O*|--open-files-in-pager*|--ext-diff|-c|--exec-path*) return 1 ;;
                esac
            done
            return 0 ;;
        bash|sh)
            case "$1" in
                .claude/hooks/trace-audit.sh|./.claude/hooks/trace-audit.sh) return 0 ;;
            esac
            return 1 ;;
    esac
    return 1
}

is_read_only_command "$CMD" && exit 0
violation "$AGENT_TYPE が読み取りの許可一覧にないコマンドを実行しようとしています（$CMD）。$READ_ONLY_HINT"
