#!/bin/bash
# UserPromptSubmit Hook: ユーザーが「緊急モード」と明示したことを記録する。
#
# 緊急モードはユーザーが選んだときだけ入る作業モード（skill choosing-work-mode）。宣言する
# work-mode.sh declare は、このフックが残した「ユーザーの申し出」の記録が無いと宣言しない。
# エージェントの発言やツールの出力ではこのフックは動かないので、AI が自分の判断で緊急モードに
# 切り替えることを仕組みの側でも防ぐ。
#
# 記録の置き場は作業ツリーの外（git の共通ディレクトリ配下の stdd-work-mode/request）。
# 形式は 1 行 1 項目の key=value（requested_at=<epoch> / request=<発言の抜粋>）。
# 読む側は packages/core/skills/choosing-work-mode/scripts/work-mode.sh。
#
# 発言に「緊急モード」が無ければ何もしない。記録を残したときは、skill に従うよう短い文脈を出力する
# （UserPromptSubmit の標準出力は、Claude Code と Codex のどちらでもエージェントへの文脈として渡る）。
#
# .stdd.config.yml の emergency_mode.enabled が false なら何もしない。設定が無くても既定（有効）で動く。
# 依存: bash 3.2 以上、git。jq があれば発言の本文だけを読み、無ければ入力全体から探す。
# 失敗しても発言の送信は止めない（常に exit 0）。

KEYWORD="緊急モード"
# JSON で \uXXXX にエスケープされた場合の表記（緊急モード）
KEYWORD_ESCAPED='\\u7dca\\u6025\\u30e2\\u30fc\\u30c9'

input=$(cat)

if command -v jq >/dev/null 2>&1; then
    prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null) || prompt="$input"
else
    prompt="$input"
fi

if ! printf '%s' "$prompt" | grep -qF -- "$KEYWORD" \
    && ! printf '%s' "$prompt" | grep -qiE -- "$KEYWORD_ESCAPED"; then
    exit 0
fi

ROOT_DIR=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
CONFIG="$ROOT_DIR/.stdd.config.yml"
if [ -f "$CONFIG" ]; then
    enabled=$(awk '
        /^[^[:space:]#]/ { inblk = ($1 == "emergency_mode:"); next }
        inblk && $1 == "enabled:" { print $2; exit }
    ' "$CONFIG" | tr -d "\"'")
    [ "$enabled" = "false" ] && exit 0
fi

common=$(cd "$ROOT_DIR" && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd) || exit 0
dir="$common/stdd-work-mode"
mkdir -p "$dir" 2>/dev/null || exit 0

# 抜粋は 1 行に畳み、400 バイトで切る（切れた多バイト文字は iconv があれば取り除く）
excerpt=$(printf '%s' "$prompt" | tr '\r\n\t' '   ' | sed 's/  */ /g; s/^ //; s/ $//' | head -c 400)
if command -v iconv >/dev/null 2>&1; then
    excerpt=$(printf '%s' "$excerpt" | iconv -c -f UTF-8 -t UTF-8 2>/dev/null || printf '%s' "$excerpt")
fi

{
    printf 'requested_at=%s\n' "${STDD_NOW:-$(date +%s)}"
    printf 'request=%s\n' "$excerpt"
} > "$dir/request" 2>/dev/null || exit 0

echo "STDD: ユーザーの発言に「${KEYWORD}」が含まれています。作業モードを選ぶときは choosing-work-mode skill の手順に従ってください（宣言の前に、緊急モードを選ぶ意図かをユーザーの言葉で確かめる）。"
exit 0
