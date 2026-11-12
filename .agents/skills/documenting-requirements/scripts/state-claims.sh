#!/bin/bash
# state-claims.sh — ほかの文書の作成状況や件数を断定する記述（転記）を探す。
#
# 使い方:
#   state-claims.sh [--root <dir>] [<ファイルかディレクトリ>...]
#       パスを渡さなければ、.stdd.config.yml の docs.layout にあるすべての Spec の文書を見る。
#       見つかったら 1 件ずつ「パス:行: 文」を出して exit 1、無ければ exit 0。
#
# 見るのは、1 つの文の中に次の 2 つが両方ある形だけである。
#   (a) 件数の句 … 数字 + 成果物の名詞（「3 画面」「4 機能」）、または名詞 + 数字 + 助数詞（「画面 3 件」）
#   (b) 状態の語 … 「未作成」「実装済み」など、いまの作成状況を断定する語
# 片方だけの文は出さない。「行が 0 件のとき」のようなデータの状態の記述や、見出しの番号に当たって、
# 誤検出が多くなるためである。したがって、合格は「転記が無い」ことの証明にならない。残りはレビューで読む。
#
# 見ない部分: コードブロック（``` で囲んだ範囲）、見出しの行、更新履歴の章（見出しに「更新履歴」
# または "Change history" を含む章）より後ろ。インラインのコード（`...`）の中は見る。
#
# 語彙は .stdd.config.yml の docs.state_claims で上書きできる（書いたほうの一覧で既定を置き換える）。
#   nouns: 成果物の名詞の一覧
#   words: 状態の語の一覧
# 既定は project.language（ja / en。省略時は ja）で選ぶ。規律の正本は packages/core/docs/spec-revision.md §6。
#
# 依存: bash 3.2 以上、awk、find、grep。

set -u

ROOT=""
PATHS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --root) ROOT="${2:-}"; shift 2 ;;
        --help|-h) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) PATHS+=("$1"); shift ;;
    esac
done

[ -n "$ROOT" ] || ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CONFIG="$ROOT/.stdd.config.yml"

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
language() {
    [ -f "$CONFIG" ] || { echo ja; return; }
    local v
    v=$(awk '
        /^[^[:space:]#]/ { insec = ($1 == "project:"); next }
        insec && $1 == "language:" { sub(/^[[:space:]]*[^:]*:[[:space:]]*/, ""); print; exit }
    ' "$CONFIG")
    v=$(unquote "$v")
    echo "${v:-ja}"
}
# docs.state_claims.<key> の一覧（[a, b] の形と、- a の形の両方）を 1 行 1 語で出す
claims_list() {
    [ -f "$CONFIG" ] || return 0
    awk -v k="$1:" '
        function emit(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); gsub(/^["\047]|["\047]$/, "", s); if (s != "") print s }
        /^[^[:space:]#]/ { indocs = ($1 == "docs:"); insc = 0; inkey = 0; next }
        !indocs { next }
        /^  [^[:space:]#]/ { insc = ($1 == "state_claims:"); inkey = 0; next }
        !insc { next }
        /^    [^[:space:]#-]/ {
            inkey = ($1 == k)
            if (inkey) {
                v = $0; sub(/^[[:space:]]*[^:]*:[[:space:]]*/, "", v)
                if (v ~ /^\[/) { sub(/^\[/, "", v); sub(/\].*$/, "", v); n = split(v, a, ","); for (i = 1; i <= n; i++) emit(a[i]); inkey = 0 }
            }
            next
        }
        inkey && /^[[:space:]]*-[[:space:]]/ { v = $0; sub(/^[[:space:]]*-[[:space:]]*/, "", v); sub(/[[:space:]]#.*$/, "", v); emit(v) }
    ' "$CONFIG"
}
layout_templates() {
    [ -f "$CONFIG" ] || return 0
    awk '
        /^[^[:space:]#]/ { indocs = ($1 == "docs:"); inlayout = 0; next }
        indocs && /^  [^[:space:]#]/ { inlayout = ($1 == "layout:"); next }
        indocs && inlayout && /^    [^[:space:]#]/ && $1 != "plan:" && $1 != "wireframes:" {
            v = $0; sub(/^[[:space:]]*[^:]*:[[:space:]]*/, "", v); gsub(/["\047]/, "", v); sub(/[[:space:]]#.*$/, "", v); print v
        }
    ' "$CONFIG"
}

LANG_CODE=$(language)
NOUNS=$(claims_list nouns)
WORDS=$(claims_list words)
if [ -z "$NOUNS" ]; then
    if [ "$LANG_CODE" = "en" ]; then
        NOUNS=$(printf '%s\n' features screens endpoints operations tables documents specs files tests "use cases" skills agents rules)
    else
        NOUNS=$(printf '%s\n' 機能 画面 API 操作 エンドポイント テーブル 文書 設計書 ファイル テスト ユースケース skill agent 規約)
    fi
fi
if [ -z "$WORDS" ]; then
    if [ "$LANG_CODE" = "en" ]; then
        WORDS=$(printf '%s\n' "not yet created" "not yet implemented" "already created" "already implemented" "currently" "so far")
    else
        WORDS=$(printf '%s\n' 未作成 作成済み 未実装 実装済み 未対応 対応済み 未着手 まだ無い まだない 現時点で 現在は)
    fi
fi

# 対象のファイル
collect() {
    local p pat
    if [ ${#PATHS[@]} -gt 0 ]; then
        for p in "${PATHS[@]}"; do
            if [ "${p#/}" = "$p" ]; then p="$ROOT/$p"; fi
            if [ -d "$p" ]; then find "$p" -type f -name '*.md' -not -path '*/node_modules/*' -not -path '*/.git/*'
            elif [ -f "$p" ]; then echo "$p"; fi
        done
    else
        layout_templates | while IFS= read -r p; do
            [ -n "$p" ] || continue
            pat=$(printf '%s' "$p" | sed 's/{{[^}]*}}/*/g')
            find "$ROOT" -path "$ROOT/$pat" -type f 2>/dev/null
        done
    fi
}
FILES=$(collect | sed '/^$/d' | sort -u)
if [ -z "$FILES" ]; then
    echo "state-claims: 見る文書がありません"
    exit 0
fi

# 正規表現の特殊文字を逃がして | でつなぐ
alt() { printf '%s\n' "$1" | sed '/^$/d; s/[][\.*^$+?(){}|/]/\\&/g' | paste -sd'|' -; }
NOUN_RE=$(alt "$NOUNS")
WORD_RE=$(alt "$WORDS")

FOUND=0
COUNT=0
while IFS= read -r f; do
    out=$(awk -v nre="$NOUN_RE" -v wre="$WORD_RE" -v en="$([ "$LANG_CODE" = en ] && echo 1 || echo 0)" '
        BEGIN {
            c1 = "[0-9]+[[:space:]]*(" nre ")"
            c2 = "(" nre ")[[:space:]]*[0-9]+[[:space:]]*(件|本|つ|個|種類)"
        }
        /^[[:space:]]*(```|~~~)/ { infence = !infence; next }
        infence { next }
        /^#/ { if ($0 ~ /更新履歴|[Cc]hange history/) stop = 1; next }
        stop { next }
        {
            line = $0
            if (en) gsub(/\. /, ".\n", line); else gsub(/。/, "。\n", line)
            n = split(line, s, "\n")
            for (i = 1; i <= n; i++) {
                if ((s[i] ~ c1 || s[i] ~ c2) && s[i] ~ ("(" wre ")")) {
                    t = s[i]; gsub(/^[[:space:]]+/, "", t)
                    print NR ": " t
                }
            }
        }
    ' "$f")
    if [ -n "$out" ]; then
        FOUND=1
        rel="${f#"$ROOT"/}"
        printf '%s\n' "$out" | sed "s|^|$rel:|"
        COUNT=$((COUNT + $(printf '%s\n' "$out" | wc -l | tr -d ' ')))
    fi
done <<EOF
$FILES
EOF

if [ "$FOUND" -eq 1 ]; then
    echo "state-claims NG: ほかの文書の作成状況や件数を断定する記述が $COUNT 件あります。正本を参照する形に書き直してください" >&2
    exit 1
fi
echo "state-claims OK: $(printf '%s\n' "$FILES" | wc -l | tr -d ' ') 件の文書"
exit 0
