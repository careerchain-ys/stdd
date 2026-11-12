#!/bin/bash
# review-runner.sh — 並列のレビューを agent teams で起動するか、subagent で起動するかを判定する。
#
# 使い方:
#   review-runner.sh [--root <dir>]
#
#   標準出力の 1 行目に teams か subagents、2 行目に判定の理由を出す。
#
# 判定（packages/core/docs/skill-and-agent.md §2）:
#   - Codex のセッション（環境変数 CODEX_SESSION_ID / CODEX_THREAD_ID がある）は subagents。
#   - Claude Code では CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS の値で決める。1 なら teams、それ以外は subagents。
#     値は settings の env を優先し、.claude/settings.local.json → .claude/settings.json → ~/.claude/settings.json
#     の順に最初に見つかったものを使う。どこにも無ければ環境変数の値を使う。
#
# 限界: 非対話の実行（-p など）では、teams と判定してもチームは作られず、名前を付けた subagent は通常の
#   subagent として動く。実際にどちらで動いたかは、起動した側が完了報告と PR 本文に書く。
# 依存: bash 3.2 以上。設定ファイルは JSON を字面で読む（jq は使わない）。

set -u
ROOT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root) ROOT="${2:-}"; shift 2 ;;
        --help|-h) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "review-runner NG: 未知の引数: $1（--help で一覧）" >&2; exit 1 ;;
    esac
done
[ -n "$ROOT" ] || ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

if [ -n "${CODEX_SESSION_ID:-}${CODEX_THREAD_ID:-}" ]; then
    echo "subagents"
    echo "Codex のセッション（agent teams が無い）"
    exit 0
fi

KEY=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS

# settings ファイルの env にある値を取り出す（"KEY": "1" / "KEY": 1 の両方）
settings_value() {
    [ -f "$1" ] || return 1
    local v
    v=$(tr -d '\n' < "$1" | grep -o "\"$KEY\"[[:space:]]*:[[:space:]]*\"\{0,1\}[^\",}]*" | head -1 \
        | sed -E "s/^\"$KEY\"[[:space:]]*:[[:space:]]*\"?//; s/[[:space:]]+$//")
    [ -n "$v" ] || return 1
    printf '%s' "$v"
}

VALUE=""
SOURCE=""
for f in "$ROOT/.claude/settings.local.json" "$ROOT/.claude/settings.json" "${HOME:-}/.claude/settings.json"; do
    if v=$(settings_value "$f"); then VALUE="$v"; SOURCE="$f"; break; fi
done
if [ -z "$SOURCE" ] && [ -n "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS+x}" ]; then
    VALUE="$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"; SOURCE="環境変数"
fi

if [ "$VALUE" = "1" ]; then
    echo "teams"
    echo "$KEY=1（$SOURCE）"
else
    echo "subagents"
    if [ -n "$SOURCE" ]; then echo "$KEY=$VALUE（$SOURCE）"; else echo "$KEY が設定されていない"; fi
fi
