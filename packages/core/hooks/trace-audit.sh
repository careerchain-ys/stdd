#!/bin/bash
# trace-audit.sh — ID ベース・トレーサビリティ監査（依存なしスキャナ）
#
# 要件（ユースケース）に振った安定 ID を、技術設計・テスト・実装へ貫通させ、
#   要件 → 技術設計 → テスト → 実装
# の対応関係と抜け漏れを機械的に検知する。verifying-consistency スキルと
# pre-push フックの共通スキャナ（二重実装を防ぐ単一の正典）。
#
# 使い方:
#   trace-audit.sh [--root <dir>]                 順方向監査（トレーサビリティ行列＋抜け漏れ）
#   trace-audit.sh --impact <ID> [<ID>...]        逆方向: 指定 ID の影響範囲（全リンク先）
#   trace-audit.sh --changed <file> [<file>...]   逆方向: 変更ファイルの影響範囲＋追跡不能変更
#
# このフックは下流プロジェクト固有の値をハードコードせず、リポジトリルートの
# .stdd.config.yml を実行時に読み取って動作する（設定駆動）。参照する設定:
#   traceability.enabled                 : 監査の有効化（既定 true）
#   traceability.enforce                 : off | warn | block（既定 warn）。exit code を左右する
#   traceability.id_prefixes.{use_case,flow,acceptance} : ID 接頭辞（既定 UC / FL / AC）
#   traceability.patterns.{test_tag,impl_annotation}    : テストタグ・実装注釈の正規表現
#   traceability.scan.{tests,impl}       : テスト・実装のスキャン glob
#   traceability.require_impl_annotation : 実装注釈の欠落を抜け漏れ扱いにするか（既定 false）
#   docs.layout.*                        : Spec のファイル名（要件・設計・テスト計画の見分けに使う。キーが無ければ既定の名前）
#   docs.lineup / docs.structure / project.language : 設計書の表の突合（layered）で章名・列名・行 ID を読む
#   response_codes.{feature_code_pattern,common_codes} : レスポンスコードの形式と共通コード
#
# layered の構成では、ID の追跡に加えて設計書の表どうしを突き合わせる（要件 ⇄ API 設計 ⇄ 画面設計 ⇄
# テスト設計、レスポンスコード）。章名・列名は documenting-tech-specs/references/doc-structure.json から
# 読む（jq を使う。無ければ突合は「未実施」と表示する）。突合の一覧は packages/core/docs/id-chain.md。
#
# 設定が無い / traceability セクションが無い場合は監査をスキップする（exit 0）。
# 詳細な記述規約は docs/config-driven-authoring.md を参照。

set -u

# ---------------------------------------------------------------------------
# 引数
# ---------------------------------------------------------------------------
MODE="audit"      # audit | impact | changed
ROOT=""
ARGS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --impact)  MODE="impact"; shift ;;
        --changed) MODE="changed"; shift ;;
        --root)    ROOT="$2"; shift 2 ;;
        --help|-h)
            sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) ARGS+=("$1"); shift ;;
    esac
done

if [ -z "$ROOT" ]; then
    ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
CONFIG="$ROOT/.stdd.config.yml"

if [ ! -f "$CONFIG" ]; then
    echo "trace-audit: .stdd.config.yml が見つからないためスキップします"
    exit 0
fi

# ---------------------------------------------------------------------------
# .stdd.config.yml パーサ（外部依存なし・traceability ブロックに特化）
# ---------------------------------------------------------------------------

# traceability: 直下（インデントされた行）のブロックだけを抜き出す
config_block() {
    awk '
        /^[^[:space:]]/ { inblk = ($1 == "traceability:") }
        inblk && $0 !~ /^traceability:/ { print }
    ' "$CONFIG"
}
BLOCK="$(config_block)"

strip_quotes() {
    local v="$1"
    v="${v%\"}"; v="${v#\"}"
    v="${v%\'}"; v="${v#\'}"
    printf '%s' "$v"
}

# ブロック内の leaf キーのスカラー値（キー名はブロック内で一意な前提）
block_scalar() {
    printf '%s\n' "$BLOCK" | awk -v k="$1:" '
        $1 == k { sub(/^[[:space:]]*[^:]*:[[:space:]]*/, ""); print; exit }
    '
}

# ブロック内の list キーの項目（"- item" 形式）
block_list() {
    printf '%s\n' "$BLOCK" | awk -v k="$1:" '
        $1 == k { inlist = 1; next }
        inlist && $1 == "-" { print $2; next }
        inlist && $1 != "-" { inlist = 0 }
    '
}

ENABLED=$(strip_quotes "$(block_scalar enabled)")
ENFORCE=$(strip_quotes "$(block_scalar enforce)")
REQ_IMPL=$(strip_quotes "$(block_scalar require_impl_annotation)")
UCP=$(strip_quotes "$(block_scalar use_case)");   UCP=${UCP:-UC}
FLP=$(strip_quotes "$(block_scalar flow)");        FLP=${FLP:-FL}
ACP=$(strip_quotes "$(block_scalar acceptance)");  ACP=${ACP:-AC}
TEST_RE=$(strip_quotes "$(block_scalar test_tag)")
IMPL_RE=$(strip_quotes "$(block_scalar impl_annotation)")

ENABLED=${ENABLED:-true}
ENFORCE=${ENFORCE:-warn}
REQ_IMPL=${REQ_IMPL:-false}

if [ "$ENABLED" = "false" ]; then
    echo "trace-audit: traceability.enabled=false のためスキップします"
    exit 0
fi

# ID トークン（抽出用）: 接頭辞 ＋ -<feature>-NN（AC は末尾に -k を許す）
ID_TOKEN="($UCP|$FLP|$ACP)-[a-z0-9]+-[0-9]+(-[0-9]+)?"

# テストタグ・実装注釈の既定パターン（設定があれば上書き）
: "${TEST_RE:=\\[(($UCP|$FLP)-[a-z0-9]+-[0-9]+)\\]}"
: "${IMPL_RE:=@stdd[[:space:]]+(($UCP|$FLP)-[a-z0-9]+-[0-9]+)}"

# スキャン glob（設定があれば上書き）
TEST_GLOBS=$(block_list tests)
IMPL_GLOBS=$(block_list impl)
[ -z "$TEST_GLOBS" ] && TEST_GLOBS=$'**/*.test.ts\n**/*.test.tsx\n**/*.spec.ts\ne2e/**/*.spec.ts'
[ -z "$IMPL_GLOBS" ] && IMPL_GLOBS=$'app/**\ncomponents/**\nlib/**\nactions/**\ndomain/**'

# ---------------------------------------------------------------------------
# ファイル収集
# ---------------------------------------------------------------------------
shopt -s nullglob 2>/dev/null

# ルート配下の全ファイル（ROOT 相対）。dot ディレクトリ / node_modules は除外。
ALL_FILES=$(cd "$ROOT" && find . -type f \
    -not -path '*/node_modules/*' -not -path '*/.*' 2>/dev/null | sed 's#^\./##')

# glob → 正規表現。`**/` は 0 個以上のディレクトリ、`**` は任意、`*` は / を跨がない。
# bash の globstar (4.0+) には依存しない — macOS 既定の bash 3.2 では未対応のため。
glob_to_regex() {
    local g="$1" out="" n=${#g} i=0 c
    while [ "$i" -lt "$n" ]; do
        c=${g:$i:1}
        case "$c" in
            '*')
                if [ "${g:$i:3}" = "**/" ]; then out="$out(.*/)?"; i=$((i+3)); continue; fi
                if [ "${g:$i:2}" = "**" ];  then out="$out.*";     i=$((i+2)); continue; fi
                out="$out[^/]*" ;;
            '?') out="$out[^/]" ;;
            '.'|'+'|'^'|'$'|'('|')'|'['|']'|'{'|'}'|'|'|'\\') out="$out\\$c" ;;
            *) out="$out$c" ;;
        esac
        i=$((i+1))
    done
    printf '%s' "$out"
}

# glob 群 → リポジトリルート相対のファイル一覧（重複除去）
expand_globs() {
    local globs="$1" g re pats=""
    while IFS= read -r g; do
        [ -z "$g" ] && continue
        g=$(strip_quotes "$g")
        re=$(glob_to_regex "$g")
        pats="$pats${pats:+|}^$re\$"
    done <<< "$globs"
    [ -z "$pats" ] && return 0
    printf '%s\n' "$ALL_FILES" | grep -E "$pats" | LC_ALL=C sort -u
}

TEST_FILES=$(expand_globs "$TEST_GLOBS")
IMPL_FILES=$(expand_globs "$IMPL_GLOBS")

# Spec ファイルのファイル名を docs.layout から読む（キーが無ければ既定のファイル名）。
#   要件     : requirements
#   設計     : tech_design（single）/ api_design・screen_design（layered）
#   テスト計画: test_plan（single）/ test_design・api_test_design・screen_test_design（layered）
layout_basename() {  # $1=docs.layout のキー $2=既定のファイル名
    local v
    v=$(awk -v k="$1:" '
        /^[^[:space:]]/ { indocs = ($1 == "docs:"); inlayout = 0; next }
        indocs && $1 == "layout:" { inlayout = 1; next }
        indocs && inlayout && $1 == k { sub(/^[[:space:]]*[^:]*:[[:space:]]*/, ""); print; exit }
    ' "$CONFIG")
    v=$(strip_quotes "$v")
    v=${v##*/}
    printf '%s\n' "${v:-$2}"
}
REQ_NAMES=$(layout_basename requirements REQUIREMENTS.md)
DESIGN_NAMES=$(layout_basename tech_design TECH_DESIGN.md; layout_basename api_design API_DESIGN.md; layout_basename screen_design SCREEN_DESIGN.md)
PLAN_NAMES=$(layout_basename test_plan TEST_PLAN.md; layout_basename test_design TEST_DESIGN.md
    layout_basename api_test_design API_TEST_DESIGN.md; layout_basename screen_test_design SCREEN_TEST_DESIGN.md)
spec_layer() {  # $1=ファイル名 → req | design | plan（該当しなければ空）
    if   printf '%s\n' "$REQ_NAMES"    | grep -qxF "$1"; then echo req
    elif printf '%s\n' "$DESIGN_NAMES" | grep -qxF "$1"; then echo design
    elif printf '%s\n' "$PLAN_NAMES"   | grep -qxF "$1"; then echo plan
    fi
}
NAME_ARGS=()
while IFS= read -r n; do
    [ -z "$n" ] && continue
    [ "${#NAME_ARGS[@]}" -gt 0 ] && NAME_ARGS+=(-o)
    NAME_ARGS+=(-name "$n")
done <<< "$(printf '%s\n%s\n%s\n' "$REQ_NAMES" "$DESIGN_NAMES" "$PLAN_NAMES" | LC_ALL=C sort -u)"
SPEC_FILES=$(cd "$ROOT" && find . -type f \( "${NAME_ARGS[@]}" \) \
    -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | sed 's#^\./##')

# ---------------------------------------------------------------------------
# レコード生成: ID<TAB>layer<TAB>file:line
#   layer = req | design | plan | test | impl
# ---------------------------------------------------------------------------
RECORDS=$(mktemp)
trap 'rm -f "$RECORDS"' EXIT

emit_from_file() {  # $1=relfile $2=layer $3=match-regex(空なら ID_TOKEN 全体)
    local rel="$1" layer="$2" re="$3" abs="$ROOT/$1"
    [ -f "$abs" ] || return 0
    local line rest id
    if [ -z "$re" ]; then
        grep -noE "$ID_TOKEN" "$abs" 2>/dev/null | while IFS= read -r m; do
            line=${m%%:*}; id=${m#*:}
            printf '%s\t%s\t%s:%s\n' "$id" "$layer" "$rel" "$line"
        done
    else
        # パターンに一致する箇所から ID トークンを取り出す
        grep -noE "$re" "$abs" 2>/dev/null | while IFS= read -r m; do
            line=${m%%:*}; rest=${m#*:}
            id=$(printf '%s' "$rest" | grep -oE "$ID_TOKEN" | head -1)
            [ -n "$id" ] && printf '%s\t%s\t%s:%s\n' "$id" "$layer" "$rel" "$line"
        done
    fi
}

while IFS= read -r f; do
    [ -z "$f" ] && continue
    layer=$(spec_layer "${f##*/}")
    [ -n "$layer" ] && emit_from_file "$f" "$layer" ""
done <<< "$SPEC_FILES" >> "$RECORDS"

while IFS= read -r f; do
    [ -z "$f" ] && continue
    emit_from_file "$f" test "$TEST_RE"
done <<< "$TEST_FILES" >> "$RECORDS"

while IFS= read -r f; do
    [ -z "$f" ] && continue
    emit_from_file "$f" impl "$IMPL_RE"
done <<< "$IMPL_FILES" >> "$RECORDS"

# ---------------------------------------------------------------------------
# 設計書の表どうしの突合（layered の構成）
#   要件 → API 設計 → 画面設計 → テスト設計を、表の行の ID とレスポンスコードで突き合わせる。
#   章名・列名・行 ID の接頭辞は documenting-tech-specs/references/doc-structure.json（言語は project.language）
#   から読み、docs.structure の上書きを優先する。スクリプトは日本語の章名・列名を持たない。
#   doc-structure.json を読むのに jq を使う。jq が無いときは突合を「未実施」と表示する（合格とは表示しない）。
# ---------------------------------------------------------------------------
TABLE_FACTS=$(mktemp)
TABLE_NAMES=$(mktemp)
trap 'rm -f "$RECORDS" "$TABLE_FACTS" "$TABLE_NAMES"' EXIT
TABLES_STATUS=""   # 空: 実施 / それ以外: 未実施の理由

# 設定全体を「ドット区切りのキー<TAB>値」に平らにする。マップだけを読み、リストの項目は読まない。
config_flat() {
    awk '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        {
            line = $0; sub(/[[:space:]]+#.*$/, "", line)
            match(line, /^ */); ind = RLENGTH; s = substr(line, ind + 1)
            if (s ~ /^-/) next
            if (s !~ /^[A-Za-z0-9_.-]+:/) next
            k = s; sub(/:.*/, "", k)
            v = s; sub(/^[^:]*:[[:space:]]*/, "", v)
            while (n > 0 && ind <= ind_[n]) n--
            n++; key_[n] = k; ind_[n] = ind
            if (v != "") {
                gsub(/^["\047]|["\047]$/, "", v)
                p = key_[1]; for (i = 2; i <= n; i++) p = p "." key_[i]
                print p "\t" v
            }
        }
    ' "$CONFIG"
}
CONFIG_FLAT=$(config_flat)
cfg() { printf '%s\n' "$CONFIG_FLAT" | awk -F'\t' -v k="$1" '$1 == k { v = $2 } END { print v }'; }

LINEUP=$(cfg docs.lineup); LINEUP=${LINEUP:-single}
DOC_LANG=$(cfg project.language); DOC_LANG=${DOC_LANG:-ja}

# レスポンスコードの機能略号（^ と $ は外して埋め込む）と共通コードの一覧（NAME<TAB>帯＋連番）
FEATURE_CODE_RE=$(cfg response_codes.feature_code_pattern)
FEATURE_CODE_RE=${FEATURE_CODE_RE:-'^[A-Z]{3,4}$'}
FEATURE_CODE_RE=${FEATURE_CODE_RE#^}; FEATURE_CODE_RE=${FEATURE_CODE_RE%\$}
COMMON_CODES=$(awk '
    function flush() { if (nm != "" && cd != "") print nm "\t" cd; nm = ""; cd = "" }
    /^[^[:space:]#]/ { flush(); inrc = ($1 == "response_codes:"); incc = 0; next }
    inrc && $1 == "common_codes:" { incc = 1; match($0, /^ */); ccind = RLENGTH; next }
    inrc && incc {
        if ($0 ~ /^[[:space:]]*(#.*)?$/) next
        match($0, /^ */)
        if (RLENGTH <= ccind && $0 !~ /^[[:space:]]*-/) { flush(); incc = 0; next }
        s = $0
        if (s ~ /^[[:space:]]*-/) { flush(); sub(/^[[:space:]]*-[[:space:]]*/, "", s) }
        gsub(/[{}]/, "", s)
        np = split(s, parts, ",")
        for (i = 1; i <= np; i++) {
            k = parts[i]; v = parts[i]
            sub(/:.*/, "", k); gsub(/[[:space:]]/, "", k)
            if (v !~ /:/) continue
            sub(/^[^:]*:[[:space:]]*/, "", v); gsub(/["\047]|[[:space:]]+$/, "", v)
            if (k == "name") nm = v
            if (k == "code") cd = v
        }
    }
    END { flush() }
' "$CONFIG")
# 既定の一覧は documenting-tech-specs/guides/response-codes.md §4 と同じ（一致は test/trace-audit.test.sh が確かめる）
[ -z "$COMMON_CODES" ] && COMMON_CODES=$'VALIDATION_ERROR\t1800\nAUTH_REQUIRED\t9800\nNOT_FOUND\t9820\nINTERNAL_ERROR\t9900'

# 構造定義の場所: hooks から見た skills（Claude ビュー・正本）→ Codex ビュー
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
STRUCT_JSON=""
for c in "$SCRIPT_DIR/../skills/documenting-tech-specs/references/doc-structure.json" \
         "$ROOT/.claude/skills/documenting-tech-specs/references/doc-structure.json" \
         "$ROOT/.agents/skills/documenting-tech-specs/references/doc-structure.json" \
         "$ROOT/packages/core/skills/documenting-tech-specs/references/doc-structure.json"; do
    [ -f "$c" ] && { STRUCT_JSON="$c"; break; }
done

# 突合の対象（layered の文書と要件）: kind<TAB>dir<TAB>file
TABLE_DOCS=""
add_table_docs() {  # $1=kind $2=docs.layout のキー $3=既定のファイル名
    local name f
    name=$(layout_basename "$2" "$3")
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        [ "${f##*/}" = "$name" ] || continue
        TABLE_DOCS="$TABLE_DOCS$1	$(dirname "$f")	$f
"
    done <<< "$SPEC_FILES"
}
add_table_docs requirements       requirements       REQUIREMENTS.md
add_table_docs api_design         api_design         API_DESIGN.md
add_table_docs api_test_design    api_test_design    API_TEST_DESIGN.md
add_table_docs screen_design      screen_design      SCREEN_DESIGN.md
add_table_docs screen_test_design screen_test_design SCREEN_TEST_DESIGN.md
add_table_docs test_design        test_design        TEST_DESIGN.md
N_LAYERED=$(printf '%s' "$TABLE_DOCS" | awk -F'\t' '$1 != "requirements"' | grep -c . )

if [ "$LINEUP" != "layered" ] && [ "$N_LAYERED" -eq 0 ]; then
    TABLES_STATUS="single"
elif ! command -v jq >/dev/null 2>&1; then
    TABLES_STATUS="jq が見つからないため、設計書の表の突合を実施していません"
elif [ -z "$STRUCT_JSON" ]; then
    TABLES_STATUS="doc-structure.json が見つからないため、設計書の表の突合を実施していません"
fi

if [ -z "$TABLES_STATUS" ]; then
    # 名前の表: <doc>.<sections|ids|tables.<t>.columns>.<key><TAB>名前（既定 → 設定の上書きの順。後に書いた値が勝つ）
    {
        jq -r --arg l "$DOC_LANG" '
            .documents | to_entries[] | .key as $d | .value as $v |
            ( ($v.sections // {}) | to_entries[] | "\($d).sections.\(.key)\t\(.value[$l] // .value.ja)" ),
            ( ($v.ids // {}) | to_entries[] | "\($d).ids.\(.key)\t\(.value)" ),
            ( ($v.tables // {}) | to_entries[] | .key as $t |
                ((.value.columns // {}) | to_entries[] | "\($d).tables.\($t).columns.\(.key)\t\(.value[$l] // .value.ja)") )
        ' "$STRUCT_JSON"
        printf '%s\n' "$CONFIG_FLAT" | awk -F'\t' '$1 ~ /^docs\.structure\./ { sub(/^docs\.structure\./, "", $1); print $1 "\t" $2 }'
    } > "$TABLE_NAMES"
fi

# 1 つの文書から事実（fact）を取り出す。出力は 1 行 1 件、タブ区切り。先頭の語が種類:
#   chap <doc> <dir> <chapter> <loc>            見つかった章
#   unreadable <loc> <説明>                      章はあるが表を読めない（列名の不一致など）
#   op <dir> <op> <loc> / optable <dir> <op>     API 設計の操作 / その操作のレスポンスコード表
#   code <dir> <op> <code> <commonCode> <loc>    API 設計のコード表の行
#   badcode <loc> <セルの内容>                   コード表の行にコードが無い
#   def <dir> <file> <scope> <kind> <id> <loc>   行 ID の定義（kind: TR AT ST、画面は item option button validation event response）
#   brdesign / fldesign <dir> <id> <loc>         API 設計の機能ルールの節 / その他処理フロー
#   tgt <dir> <testdoc> <kind> <key> <rowid> <loc>  テスト設計の行の対象（kind: code の key は op|code）
#   evop <dir> <ev> <op> <loc> / rsop <dir> <op> <loc>  画面が呼ぶ操作 / レスポンス処理の操作の節
#   rscode / rsband / rscommon <dir> <op> <値> <loc>     レスポンス処理が受けるコード / 帯 / 共通コード名
#   rsev <dir> <ev> <loc>                        レスポンス処理の行のイベント
#   requc / reqbr <dir> <id> <loc> / reqac <dir> <uc> <件数>  要件のユースケース / 業務ルール / 受入基準の件数
#   tduc <dir> <uc> <loc> / tdac <dir> <uc> <k> <loc>    統括テスト設計のユースケースの行 / 受入基準の行
#   tdcov <dir> <AT|ST> <rowid> <loc> / nocov <loc>      受入基準の担保先の行 ID / 担保先が読めない
#   tref <loc> <path>                            テスト参照（ファイルのパス::テスト名）のパス
extract_facts() {  # $1=kind $2=dir $3=file
    awk -v doc="$1" -v dir="$2" -v file="$3" -v names="$TABLE_NAMES" \
        -v ucp="$UCP" -v flp="$FLP" -v acp="$ACP" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function norm(h) { sub(/^#+[ \t]*/, "", h); sub(/^[0-9]+(\.[0-9]+)*\.?[ \t]+/, "", h); return trim(h) }
    function nm(k) { return (k in NM) ? NM[k] : "\001" }
    function loc() { return file ":" NR }
    function emit(s) { print s }
    function ticks(s, arr,   n) { n = 0
        while (match(s, /`[^`]+`/)) { arr[++n] = substr(s, RSTART + 1, RLENGTH - 2); s = substr(s, RSTART + RLENGTH) }
        return n }
    function tokens(s, re, arr,   n) { n = 0
        while (match(s, re)) { arr[++n] = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH) }
        return n }
    function cells(line, arr,   n, i) { sub(/^[ \t]*\|/, "", line); sub(/\|[ \t]*$/, "", line)
        n = split(line, arr, "|"); for (i = 1; i <= n; i++) arr[i] = trim(arr[i]); return n }
    function col(name,   i) { for (i = 1; i <= hn; i++) if (H[i] == name) return i; return 0 }
    function ischap(key) { return norm(htext) == nm(doc ".sections." key) }
    function rowid(prefix, s,   a) { return (tokens(s, "(^|[^A-Za-z])" prefix "-[0-9]+", a) > 0) ? strip(a[1]) : "" }
    function strip(s) { sub(/^[^A-Za-z]/, "", s); return s }
    function unreadable(what) { emit("unreadable\t" loc() "\t" what) }
    function trefs(s,   n, a, i, p) {
        n = tokens(s, "[A-Za-z0-9_./@+-]+::", a)
        for (i = 1; i <= n; i++) { p = a[i]; sub(/::$/, "", p); emit("tref\t" loc() "\t" p) } }
    function codecell(s, op, mode,   n, a, i, t, found) { found = 0
        n = ticks(s, a)
        if (n == 0 && mode == "design") n = tokens(s, "[A-Z][A-Z0-9]*-[0-9]+", a)
        for (i = 1; i <= n; i++) { t = a[i]
            if (t ~ /^[A-Z][A-Z0-9]*-[0-9]+$/) { found++
                if (mode == "rs") emit("rscode\t" dir "\t" op "\t" t "\t" loc()); else CODES[++nc] = t }
            else if (mode == "rs" && t ~ /^[019]$/) emit("rsband\t" dir "\t" op "\t" t "\t" loc())
            else if (mode == "rs" && t ~ /^[A-Z][A-Z0-9_]+$/) emit("rscommon\t" dir "\t" op "\t" t "\t" loc())
        }
        return found }
    BEGIN {
        while ((getline l < names) > 0) { split(l, kv, "\t"); NM[kv[1]] = kv[2] }
        P_TR = nm("api_design.ids.transition"); P_AT = nm("api_test_design.ids.row"); P_ST = nm("screen_test_design.ids.row")
        P_BR = nm("requirements.ids.rule")
        split("screen item option button validation event response", sk, " ")
        P_SCR = ""
        for (i = 2; i <= 7; i++) { SP[i] = nm("screen_design.ids." sk[i]); P_SCR = P_SCR (P_SCR ? "|" : "") SP[i]; KIND[SP[i]] = sk[i] }
        P_UI = nm("screen_design.ids.screen")
        P_VA = SP[5]; P_EV = SP[6]; P_RS = SP[7]
        ID_UC = ucp "-[a-z0-9]+-[0-9]+"; ID_FL = flp "-[a-z0-9]+-[0-9]+"; ID_BR = P_BR "-[a-z0-9]+-[0-9]+"
        ch = ""; sub3 = ""; op = ""; screen = ""; tbl = 0; mode = ""; nrows = 0; cur_uc = ""
    }
    /^[ \t]*(```|~~~)/ { infence = !infence; tbl = 0; next }
    infence {
        if (doc == "requirements" && cur_uc != "" && $0 ~ /^[ \t]*\[[^]]+\]/) AC[cur_uc]++
        next
    }
    /^#+[ \t]/ {
        tbl = 0; mode = ""; inresp = 0; htext = $0; match($0, /^#+/); lv = RLENGTH
        if (doc == "requirements") { cur_uc = ""; next }
        if (lv == 1) { screen = (tokens($0, P_UI "-[a-z0-9]+-[0-9]+", a) > 0) ? a[1] : norm($0); ch = ""; sub3 = "" }
        if (lv == 2) { ch = ""; sub3 = ""; op = ""; inh3 = 0
            n = split("operations state_transitions rules flows items ui_logic catalog use_cases", cand, " ")
            for (i = 1; i <= n; i++) if (ischap(cand[i])) ch = cand[i]
            if (ch != "") emit("chap\t" doc "\t" dir "\t" ch "\t" loc()) }
        if (lv == 3) { sub3 = ""; op = ""; inh3 = 1
            n = split("validations events responses acceptance", cand, " ")
            for (i = 1; i <= n; i++) if (ischap(cand[i])) sub3 = cand[i]
            if (sub3 != "") emit("chap\t" doc "\t" dir "\t" sub3 "\t" loc())
            if (ch == "operations") { op = (ticks($0, a) > 0) ? a[1] : norm($0)
                if (doc == "api_design") emit("op\t" dir "\t" op "\t" loc()) }
            if (doc == "api_design" && ch == "rules" && tokens($0, ID_BR, a) > 0) emit("brdesign\t" dir "\t" a[1] "\t" loc()) }
        if (lv == 4) {
            inresp = (doc == "api_design" && ch == "operations" && norm($0) == nm("api_design.sections.response_codes"))
            if (doc == "screen_design" && sub3 == "responses") { op = (ticks($0, a) > 0) ? a[1] : norm($0); emit("rsop\t" dir "\t" op "\t" loc()) } }
        next
    }
    /^[ \t]*\|/ {
        if (tbl == 0) { hn = cells($0, H); tbl = 1; mode = ""; header() ; next }
        if (tbl == 1) { tbl = 2; next }
        rn = cells($0, R); row(); next
    }
    { tbl = 0
      if (doc == "requirements" && $0 ~ /\*\*ID\*\*/) {
          if (tokens($0, ID_UC, a) > 0) { cur_uc = a[1]; emit("requc\t" dir "\t" a[1] "\t" loc()) }
          if (tokens($0, ID_BR, a) > 0) { cur_uc = ""; emit("reqbr\t" dir "\t" a[1] "\t" loc()) } }
      if (doc == "api_design" && ch == "flows" && tokens($0, ID_FL, a) > 0) emit("fldesign\t" dir "\t" a[1] "\t" loc())
    }
    function header() {
        if (doc == "api_design") {
            if (inresp) { ci = col(nm("api_design.tables.response_codes.columns.code")); cc = col(nm("api_design.tables.response_codes.columns.common_code"))
                if (ci == 0) unreadable("レスポンスコードの表に「" nm("api_design.tables.response_codes.columns.code") "」の列が無い")
                else { mode = "resp"; emit("optable\t" dir "\t" op) }
                inresp = 0 }
            else if (ch == "state_transitions") { ti = col(nm("api_design.tables.transitions.columns.id"))
                if (ti == 0) unreadable("状態遷移の表に「" nm("api_design.tables.transitions.columns.id") "」の列が無い"); else mode = "tr" }
        } else if (doc == "api_test_design" || doc == "screen_test_design") {
            ii = col(nm(doc ".tables.test_rows.columns.id")); ti = col(nm(doc ".tables.test_rows.columns.target")); ri = col(nm(doc ".tables.test_rows.columns.test_ref"))
            if (ii == 0 || ti == 0) unreadable("テスト設計の表に「" nm(doc ".tables.test_rows.columns.id") "」「" nm(doc ".tables.test_rows.columns.target") "」の列が無い")
            else mode = "rows"
        } else if (doc == "screen_design") {
            if (ch == "items" || ch == "ui_logic") mode = "sdef"
            if (sub3 == "events") { ei = col(nm("screen_design.tables.events.columns.operation"))
                if (ei == 0) unreadable("イベント処理の表に「" nm("screen_design.tables.events.columns.operation") "」の列が無い"); else mode = "events" }
            if (sub3 == "responses") { ei = col(nm("screen_design.tables.responses.columns.event")); ci = col(nm("screen_design.tables.responses.columns.code"))
                if (ci == 0) unreadable("レスポンス処理の表に「" nm("screen_design.tables.responses.columns.code") "」の列が無い"); else mode = "responses" }
        } else if (doc == "test_design") {
            if (ch == "use_cases" && !inh3) { ui = col(nm("test_design.tables.use_cases.columns.use_case")); ri = col(nm("test_design.tables.use_cases.columns.test_ref"))
                if (ui == 0) unreadable("ユースケースの表に「" nm("test_design.tables.use_cases.columns.use_case") "」の列が無い"); else mode = "tduc" }
            if (sub3 == "acceptance") { ci = col(nm("test_design.tables.acceptance.columns.criterion")); bi = col(nm("test_design.tables.acceptance.columns.covered_by"))
                if (ci == 0 || bi == 0) unreadable("受入基準の担保先の表に「" nm("test_design.tables.acceptance.columns.criterion") "」「" nm("test_design.tables.acceptance.columns.covered_by") "」の列が無い"); else mode = "tdac" }
        }
    }
    function row(   n, a, i, id, t, k, rest, cnt) {
        if (mode == "resp") {
            nc = 0
            if (codecell(R[ci], op, "design") == 0) { emit("badcode\t" loc() "\t" R[ci]); return }
            t = (cc > 0) ? R[cc] : ""; gsub(/`/, "", t); t = trim(t); if (t == "" || t == "-" || t == "–" || t == "—") t = ""
            for (i = 1; i <= nc; i++) emit("code\t" dir "\t" op "\t" CODES[i] "\t" t "\t" loc())
        } else if (mode == "tr") {
            id = rowid(P_TR, R[ti]); if (id != "") emit("def\t" dir "\t" file "\t-\tTR\t" id "\t" loc())
        } else if (mode == "rows") {
            id = rowid(doc == "api_test_design" ? P_AT : P_ST, R[ii]); if (id == "") return
            nrows++
            emit("def\t" dir "\t" file "\t-\t" (doc == "api_test_design" ? "AT" : "ST") "\t" id "\t" loc())
            if (ri > 0) trefs(R[ri])
            if (doc == "api_test_design") {
                if (ch == "operations") { nc = 0; codecell(R[ti], op, "design")
                    for (i = 1; i <= nc; i++) emit("tgt\t" dir "\tapi\tcode\t" op "|" CODES[i] "\t" id "\t" loc()) }
                n = tokens(R[ti], "(^|[^A-Za-z])" P_TR "-[0-9]+", a); for (i = 1; i <= n; i++) emit("tgt\t" dir "\tapi\tTR\t" strip(a[i]) "\t" id "\t" loc())
                n = tokens(R[ti], ID_BR, a); for (i = 1; i <= n; i++) emit("tgt\t" dir "\tapi\tBR\t" a[i] "\t" id "\t" loc())
                n = tokens(R[ti], ID_FL, a); for (i = 1; i <= n; i++) emit("tgt\t" dir "\tapi\tFL\t" a[i] "\t" id "\t" loc())
            } else {
                n = tokens(R[ti], "(^|[^A-Za-z])(" P_SCR ")-[0-9]+", a)
                for (i = 1; i <= n; i++) { t = strip(a[i]); k = t; sub(/-.*/, "", k); emit("tgt\t" dir "\tscreen\t" KIND[k] "\t" t "\t" id "\t" loc()) }
            }
        } else if (mode == "sdef" || mode == "events" || mode == "responses") {
            n = tokens(R[1], "^(" P_SCR ")-[0-9]+$", a)
            if (n > 0) { k = a[1]; sub(/-.*/, "", k); emit("def\t" dir "\t" file "\t" screen "\t" KIND[k] "\t" a[1] "\t" loc()) }
            if (mode == "events") { n = ticks(R[ei], a); for (i = 1; i <= n; i++) if (a[i] ~ /^[A-Za-z_][A-Za-z0-9_.]*$/) emit("evop\t" dir "\t" R[1] "\t" a[i] "\t" loc()) }
            if (mode == "responses") { codecell(R[ci], op, "rs")
                if (ei > 0) { n = tokens(R[ei], "(^|[^A-Za-z])" P_EV "-[0-9]+", a); for (i = 1; i <= n; i++) emit("rsev\t" dir "\t" strip(a[i]) "\t" loc()) } }
        } else if (mode == "tduc") {
            n = tokens(R[ui], ID_UC, a); for (i = 1; i <= n; i++) emit("tduc\t" dir "\t" a[i] "\t" loc())
            if (ri > 0) trefs(R[ri])
        } else if (mode == "tdac") {
            if (tokens(R[ci], acp "-[a-z0-9]+-[0-9]+-[0-9]+", a) > 0) {
                t = a[1]; k = t; sub(/.*-/, "", k); sub(/-[0-9]+$/, "", t); sub("^" acp, ucp, t)
                emit("tdac\t" dir "\t" t "\t" k "\t" loc())
            } else if (tokens(R[ci], ID_UC, a) > 0) {
                rest = R[ci]; sub(".*" a[1], "", rest)
                if (match(rest, /[0-9]+/)) emit("tdac\t" dir "\t" a[1] "\t" substr(rest, RSTART, RLENGTH) "\t" loc())
                else emit("unreadable\t" loc() "\t受入基準の番号を読めない: " R[ci])
            } else emit("unreadable\t" loc() "\t受入基準のユースケース ID を読めない: " R[ci])
            cnt = 0
            n = tokens(R[bi], "(^|[^A-Za-z])(" P_AT "|" P_ST ")-[0-9]+", a); for (i = 1; i <= n; i++) { t = strip(a[i]); k = t; sub(/-.*/, "", k); emit("tdcov\t" dir "\t" (k == P_AT ? "AT" : "ST") "\t" t "\t" loc()); cnt++ }
            if (R[bi] ~ /::/) { trefs(R[bi]); cnt++ }
            if (cnt == 0) emit("nocov\t" loc() "\t" R[ci])
        }
    }
    END {
        if (doc == "requirements") for (u in AC) emit("reqac\t" dir "\t" u "\t" AC[u])
        if ((doc == "api_test_design" || doc == "screen_test_design") && nrows == 0) emit("unreadable\t" file "\tテスト設計の行（" (doc == "api_test_design" ? P_AT : P_ST) "-NN）が 1 行も読めない")
    }
    ' "$ROOT/$3"
}

if [ -z "$TABLES_STATUS" ]; then
    while IFS=$'\t' read -r kind dir f; do
        [ -z "$kind" ] && continue
        printf 'doc\t%s\t%s\t%s\n' "$kind" "$dir" "$f"
        extract_facts "$kind" "$dir" "$f"
    done <<< "$TABLE_DOCS" > "$TABLE_FACTS"
fi

# 事実どうしを突き合わせ、抜け漏れを 1 行ずつ出す（「[分類] 内容」）
check_tables() {
    STDD_COMMON_CODES="$COMMON_CODES" awk -F'\t' -v lineup="$LINEUP" '
    function add(s) { G[++ng] = s }
    function band(c) { return substr(c, length(c) - 3, 1) }
    function serial(c) { return substr(c, length(c) - 2) + 0 }
    BEGIN { n = split(ENVIRON["STDD_COMMON_CODES"], cl, "\n"); for (i = 1; i <= n; i++) { split(cl[i], kv, "\t"); CC_CODE[kv[1]] = kv[2]; CC_NAME[kv[2]] = kv[1] } }
    $1 == "doc"        { DOC[$2, $3] = 1; DOCS[$3] = 1; if ($2 == "api_design") napi++ }
    $1 == "chap"       { CHAP[$2, $3, $4] = 1 }
    $1 == "unreadable" { add("[表を読めない] " $2 " : " $3) }
    $1 == "op"         { OP[$2, $3] = $4; OPS[++nop] = $2 SUBSEP $3 }
    $1 == "optable"    { OPT[$2, $3] = 1 }
    $1 == "code"       { k = $2 SUBSEP $3 SUBSEP $4
                         if (k in CODE) add("[コード重複] " $4 " : 操作 " $3 " の表に同じコードが複数ある (" CODE[k] ", " $6 ")")
                         else { CODE[k] = $6; CODES[++ncode] = k; COMMONOF[k] = $5 }
                         OPCODE[$3, $4] = 1; OPCODES[$3] = OPCODES[$3] " " $4; KNOWNOP[$3] = 1 }
    $1 == "badcode"    { add("[コード形式] " $2 " : コード表の行にレスポンスコードが無い（" $3 "）") }
    $1 == "def"        { k = $3 SUBSEP $4 SUBSEP $6
                         if (k in DEF) add("[ID重複] " $6 " : 同じ文書の中で複数回定義されている (" DEF[k] ", " $7 ")")
                         else DEF[k] = $7
                         DEFS[$2, $5, $6] = $7; DEFL[++ndef] = $2 SUBSEP $5 SUBSEP $6 }
    $1 == "brdesign"   { BRD[$2, $3] = $4; BRDL[++nbrd] = $2 SUBSEP $3 }
    $1 == "fldesign"   { if (!(($2, $3) in FLD)) { FLD[$2, $3] = $4; FLDL[++nfld] = $2 SUBSEP $3 } }
    $1 == "tgt"        { TGT[$2, $3, $4, $5] = 1; TGTL[++ntgt] = $2 SUBSEP $3 SUBSEP $4 SUBSEP $5 SUBSEP $6 SUBSEP $7 }
    $1 == "evop"       { CALL[$2, $4] = $5; CALLL[++ncall] = $2 SUBSEP $4 }
    $1 == "rsop"       { if (!(($2, $3) in CALL)) { CALL[$2, $3] = $4; CALLL[++ncall] = $2 SUBSEP $3 } }
    $1 == "rscode"     { RSC[$2, $3, $4] = $5; RSCL[++nrsc] = $2 SUBSEP $3 SUBSEP $4 }
    $1 == "rsband"     { RSB[$2, $3, $4] = 1 }
    $1 == "rscommon"   { RSN[$2, $3, $4] = 1 }
    $1 == "rsev"       { RSEV[++nrsev] = $2 SUBSEP $3 SUBSEP $4 }
    $1 == "requc"      { REQUC[$2, $3] = $4; REQUCL[++nrequc] = $2 SUBSEP $3; UCDIR[$2] = 1 }
    $1 == "reqbr"      { REQBR[$2, $3] = $4; REQBRL[++nreqbr] = $2 SUBSEP $3 }
    $1 == "reqac"      { REQAC[$2, $3] = $4; REQACL[++nreqac] = $2 SUBSEP $3 }
    $1 == "tduc"       { TDUC[$2, $3] = 1 }
    $1 == "tdac"       { TDAC[$2, $3, $4] = 1; TDACL[++ntdac] = $2 SUBSEP $3 SUBSEP $4 SUBSEP $5 }
    $1 == "tdcov"      { TDCOV[++ntdcov] = $2 SUBSEP $3 SUBSEP $4 SUBSEP $5 }
    $1 == "nocov"      { add("[担保先なし] " $2 " : 受入基準（" $3 "）の担保先に、テスト設計の行の ID もテスト参照（パス::テスト名）も無い") }
    END {
        # 文書の組: 要件を持つ機能に統括のテスト設計、設計書に対のテスト設計
        for (d in UCDIR) if (lineup == "layered" && !(("test_design", d) in DOC)) add("[文書の欠落] " d " : 要件にユースケースがあるが TEST_DESIGN が無い")
        for (d in DOCS) {
            if (("api_design", d) in DOC && !(("api_test_design", d) in DOC)) add("[文書の欠落] " d " : API_DESIGN に対になる API_TEST_DESIGN が無い")
            if (("screen_design", d) in DOC && !(("screen_test_design", d) in DOC)) add("[文書の欠落] " d " : SCREEN_DESIGN に対になる SCREEN_TEST_DESIGN が無い")
            if (("api_design", d) in DOC && !(("api_design", d, "operations") in CHAP)) add("[表を読めない] " d " : API_DESIGN に操作の章が見つからない")
            if (("screen_design", d) in DOC && !(("screen_design", d, "ui_logic") in CHAP)) add("[表を読めない] " d " : SCREEN_DESIGN に UI ロジックの章が見つからない")
            if (("test_design", d) in DOC && !(("test_design", d, "use_cases") in CHAP)) add("[表を読めない] " d " : TEST_DESIGN にユースケースの章が見つからない")
        }
        # API 設計: 操作の数とコード表の数の突き合わせ・コードの帯と共通コード
        for (i = 1; i <= nop; i++) { split(OPS[i], p, SUBSEP); if (!((p[1], p[2]) in OPT)) add("[表を読めない] " OP[p[1], p[2]] " : 操作 " p[2] " にレスポンスコードの表が無い") }
        for (i = 1; i <= ncode; i++) { split(CODES[i], p, SUBSEP); c = p[3]; cm = COMMONOF[CODES[i]]; s = serial(c); bc = band(c) sprintf("%03d", s)
            if (s >= 800) {
                if (!(bc in CC_NAME)) add("[コード形式] " c " : 連番 800〜999 は共通コードの枠だが、共通コードの一覧に " bc " が無い (" CODE[CODES[i]] ")")
                else if (cm != CC_NAME[bc]) add("[コード形式] " c " : 共通コード " bc " の commonCode は " CC_NAME[bc] " (" CODE[CODES[i]] ")")
            } else if (cm != "") add("[コード形式] " c " : 機能固有のコード（連番 001〜799）に commonCode " cm " がある (" CODE[CODES[i]] ")")
            if (("api_test_design", p[1]) in DOC && !((p[1], "api", "code", p[2] "|" c) in TGT))
                add("[テスト設計漏れ] " c " : 操作 " p[2] " のコード（" CODE[CODES[i]] "）に API_TEST_DESIGN の行が無い")
        }
        for (i = 1; i <= ndef; i++) { split(DEFL[i], p, SUBSEP)
            if (p[2] == "TR" && ("api_test_design", p[1]) in DOC && !((p[1], "api", "TR", p[3]) in TGT)) add("[テスト設計漏れ] " p[3] " : 状態遷移（" DEFS[DEFL[i]] "）に API_TEST_DESIGN の行が無い")
            if (p[2] ~ /^(validation|event|response)$/ && ("screen_test_design", p[1]) in DOC && !((p[1], "screen", p[2], p[3]) in TGT)) add("[テスト設計漏れ] " p[3] " : 画面設計の行（" DEFS[DEFL[i]] "）に SCREEN_TEST_DESIGN の行が無い")
        }
        for (i = 1; i <= nbrd; i++) { split(BRDL[i], p, SUBSEP)
            if (("api_test_design", p[1]) in DOC && !((p[1], "api", "BR", p[2]) in TGT)) add("[テスト設計漏れ] " p[2] " : 機能ルール（" BRD[BRDL[i]] "）に API_TEST_DESIGN の行が無い")
            if (!(BRDL[i] in REQBR)) add("[孤児参照] " p[2] " : API_DESIGN の機能ルール（" BRD[BRDL[i]] "）が要件の業務ルールに無い") }
        for (i = 1; i <= nreqbr; i++) { split(REQBRL[i], p, SUBSEP)
            if (("api_design", p[1]) in DOC && !(REQBRL[i] in BRD)) add("[設計漏れ] " p[2] " : 業務ルール（" REQBR[REQBRL[i]] "）に API_DESIGN の機能ルールの節が無い") }
        for (i = 1; i <= nfld; i++) { split(FLDL[i], p, SUBSEP)
            if (("api_test_design", p[1]) in DOC && !((p[1], "api", "FL", p[2]) in TGT)) add("[テスト設計漏れ] " p[2] " : その他処理フロー（" FLD[FLDL[i]] "）に API_TEST_DESIGN の行が無い") }
        # テスト設計の対象が設計書にあるか
        for (i = 1; i <= ntgt; i++) { split(TGTL[i], p, SUBSEP); d = p[1]; where = p[6] " " p[5]
            if (p[3] == "code") { split(p[4], q, "|"); if (!((d, q[1], q[2]) in CODE)) add("[孤児参照] " q[2] " : テスト設計の行（" where "）の対象が、API_DESIGN の操作 " q[1] " のコード表に無い") }
            else if (p[3] == "TR") { if (!((d, "TR", p[4]) in DEFS)) add("[孤児参照] " p[4] " : テスト設計の行（" where "）の対象が API_DESIGN の状態遷移に無い") }
            else if (p[3] == "BR") { if (!((d, p[4]) in BRD)) add("[孤児参照] " p[4] " : テスト設計の行（" where "）の対象が API_DESIGN の機能ルールに無い") }
            else if (p[3] == "FL") { if (!((d, p[4]) in FLD)) add("[孤児参照] " p[4] " : テスト設計の行（" where "）の対象が API_DESIGN のその他処理フローに無い") }
            else if (!((d, p[3], p[4]) in DEFS)) add("[孤児参照] " p[4] " : テスト設計の行（" where "）の対象が SCREEN_DESIGN に無い")
        }
        # 画面設計: 呼ぶ操作が返しうるすべてのコードを、レスポンス処理の行（個別・帯のまとめ行・共通コード名）が受けるか
        for (i = 1; i <= ncall; i++) { split(CALLL[i], p, SUBSEP); d = p[1]; o = p[2]
            if (!(o in KNOWNOP)) { if (napi > 0) add("[孤児参照] " o " : 画面が呼ぶ操作（" CALL[CALLL[i]] "）が、どの API_DESIGN のコード表にも無い"); continue }
            m = split(OPCODES[o], cs, " ")
            for (j = 1; j <= m; j++) { c = cs[j]; if (c == "" || ((d, o, c) in SEEN)) continue; SEEN[d, o, c] = 1
                if ((d, o, c) in RSC) continue
                if ((d, o, band(c)) in RSB) continue
                nmc = ""; for (k in COMMONOF) { split(k, q, SUBSEP); if (q[2] == o && q[3] == c && COMMONOF[k] != "") nmc = COMMONOF[k] }
                if (nmc != "" && (d, o, nmc) in RSN) continue
                add("[画面の受け漏れ] " c " : 画面が呼ぶ操作 " o "（" CALL[CALLL[i]] "）が返すコードを、レスポンス処理のどの行も受けていない")
            }
        }
        for (i = 1; i <= nrsc; i++) { split(RSCL[i], p, SUBSEP); if ((p[2] in KNOWNOP) && !((p[2], p[3]) in OPCODE)) add("[孤児参照] " p[3] " : レスポンス処理の行（" RSC[RSCL[i]] "）のコードを、操作 " p[2] " は返さない") }
        for (i = 1; i <= nrsev; i++) { split(RSEV[i], p, SUBSEP); if (!((p[1], "event", p[2]) in DEFS)) add("[孤児参照] " p[2] " : レスポンス処理の行（" p[3] "）のイベントがイベント処理の表に無い") }
        # 要件と統括のテスト設計: ユースケースと受入基準を双方向に
        for (i = 1; i <= nrequc; i++) { split(REQUCL[i], p, SUBSEP)
            if (("test_design", p[1]) in DOC && !(REQUCL[i] in TDUC)) add("[テスト設計漏れ] " p[2] " : ユースケース（" REQUC[REQUCL[i]] "）が TEST_DESIGN のユースケースの表に無い") }
        for (i = 1; i <= nreqac; i++) { split(REQACL[i], p, SUBSEP); if (!(("test_design", p[1]) in DOC)) continue
            for (k = 1; k <= REQAC[REQACL[i]] + 0; k++) if (!((p[1], p[2], k) in TDAC)) add("[受入基準の担保漏れ] " p[2] " の受入基準 " k " : TEST_DESIGN の受入基準の担保先の表に行が無い（" REQUC[p[1], p[2]] "）") }
        for (i = 1; i <= ntdac; i++) { split(TDACL[i], p, SUBSEP)
            if (!((p[1], p[2]) in REQUC)) add("[孤児参照] " p[2] " : 受入基準の行（" p[4] "）のユースケースが要件に無い")
            else if (p[3] + 0 < 1 || p[3] + 0 > REQAC[p[1], p[2]] + 0) add("[孤児参照] " p[2] " の受入基準 " p[3] " : 要件の受入基準は " (REQAC[p[1], p[2]] + 0) " 件（" p[4] "）") }
        for (i = 1; i <= ntdcov; i++) { split(TDCOV[i], p, SUBSEP)
            if (!((p[1], p[2], p[3]) in DEFS)) add("[孤児参照] " p[3] " : 受入基準の担保先（" p[4] "）の行がテスト設計に無い") }
        for (i = 1; i <= ng; i++) print G[i]
    }
    ' "$TABLE_FACTS"
}

# レスポンスコードの形式（機能略号は response_codes.feature_code_pattern）と、テスト参照のパスの存在
check_codes_and_refs() {
    awk -F'\t' '$1 == "code" { print $4 "\t" $6 }' "$TABLE_FACTS" | while IFS=$'\t' read -r c l; do
        printf '%s\n' "$c" | grep -qE "^(${FEATURE_CODE_RE})-[019][0-9]{3}\$" ||
            echo "[コード形式] $c : 「<機能略号>-<帯 0/1/9><連番 3 桁>」の形でない、または機能略号が response_codes.feature_code_pattern に合わない ($l)"
        case "$c" in *-?000) echo "[コード形式] $c : 連番 000 は使わない ($l)" ;; esac
    done
    awk -F'\t' '$1 == "tref" { print $2 "\t" $3 }' "$TABLE_FACTS" | while IFS=$'\t' read -r l p; do
        p=${p#./}
        [ -e "$ROOT/$p" ] || echo "[テスト参照切れ] $p : テスト参照のファイルが無い ($l)"
    done
}

TABLE_GAPS=""
if [ -z "$TABLES_STATUS" ]; then
    TABLE_GAPS=$( { check_tables; check_codes_and_refs; } | LC_ALL=C sort -u)
fi

# ---------------------------------------------------------------------------
# 出力ヘルパ（逆方向モード用）: ある ID の全リンク先
# ---------------------------------------------------------------------------
print_links() {  # $1=id
    local id="$1"
    awk -F'\t' -v id="$id" '
        $1==id { locs[$2]=locs[$2] (locs[$2]?", ":"") $3 }
        END {
            split("req design plan test impl", order, " ")
            label["req"]="要件"; label["design"]="技術設計"; label["plan"]="テスト計画"
            label["test"]="テスト"; label["impl"]="実装"
            for (i=1;i<=5;i++) { k=order[i]
                printf "    - %-10s : %s\n", label[k], (locs[k] ? locs[k] : "（なし）")
            }
        }
    ' "$RECORDS"
}

# 設計書の表で ID（レスポンスコード・ユースケースなど）が現れる位置（--impact 用）
table_locations() {  # $1=id
    [ -s "$TABLE_FACTS" ] || return 0
    awk -F'\t' -v id="$1" '
        function put(label, l) { if (!((label, l) in seen)) { seen[label, l] = 1; out[label] = out[label] (out[label] ? ", " : "") l } }
        $1 == "code"   && $4 == id { put("API 設計のコード表", $6) }
        $1 == "rscode" && $4 == id { put("画面設計のレスポンス処理", $5) }
        $1 == "tgt"    && ($5 == id || $5 ~ ("[|]" id "$")) { put("テスト設計の行", $7) }
        $1 == "tduc"   && $3 == id { put("統括テスト設計", $4) }
        $1 == "tdac"   && $3 == id { put("統括テスト設計", $5) }
        END { n = split("API 設計のコード表|画面設計のレスポンス処理|テスト設計の行|統括テスト設計", o, "|")
              for (i = 1; i <= n; i++) if (o[i] in out) printf "    - %s : %s\n", o[i], out[o[i]] }
    ' "$TABLE_FACTS"
}

# ---------------------------------------------------------------------------
# 逆方向: --impact
# ---------------------------------------------------------------------------
if [ "$MODE" = "impact" ]; then
    echo "=========================================="
    echo "トレーサビリティ影響範囲（--impact）"
    echo "=========================================="
    BLOCKING=0
    [ "${#ARGS[@]}" -eq 0 ] && { echo ""; echo "ID が指定されていません"; exit 0; }
    for id in "${ARGS[@]}"; do
        echo ""
        echo "▶ $id"
        TABLE_LOCS=$(table_locations "$id")
        if ! grep -q "^$id	" "$RECORDS" && [ -z "$TABLE_LOCS" ]; then
            echo "    ⚠ この ID はどのレイヤにも存在しません（未定義 / タイプミスの可能性）"
            [ "$ENFORCE" = "block" ] && BLOCKING=$((BLOCKING+1))
            continue
        fi
        grep -q "^$id	" "$RECORDS" && print_links "$id"
        [ -n "$TABLE_LOCS" ] && printf '%s\n' "$TABLE_LOCS"
    done
    echo ""
    [ "$ENFORCE" = "block" ] && [ "$BLOCKING" -gt 0 ] && exit 2
    exit 0
fi

# ---------------------------------------------------------------------------
# 逆方向: --changed
# ---------------------------------------------------------------------------
if [ "$MODE" = "changed" ]; then
    echo "=========================================="
    echo "テスト/実装起点の影響範囲（--changed）"
    echo "=========================================="
    is_in_set() { printf '%s\n' "$2" | grep -qxF "$1"; }
    UNTRACKED=()
    IMPACT_IDS=""
    [ "${#ARGS[@]}" -eq 0 ] && { echo ""; echo "変更ファイルが指定されていません"; exit 0; }
    for raw in "${ARGS[@]}"; do
        f=${raw#./}
        ids=$(grep -F "	$f:" "$RECORDS" 2>/dev/null | cut -f1 | LC_ALL=C sort -u)
        if [ -n "$ids" ]; then
            IMPACT_IDS="$IMPACT_IDS
$ids"
        else
            # ID を持たないテスト/実装ファイルは「追跡不能変更」
            if is_in_set "$f" "$TEST_FILES" || is_in_set "$f" "$IMPL_FILES"; then
                UNTRACKED+=("$f")
            fi
        fi
    done

    UNIQ_IDS=$(printf '%s\n' "$IMPACT_IDS" | grep -vE '^$' | LC_ALL=C sort -u)
    if [ -n "$UNIQ_IDS" ]; then
        echo ""
        echo "## 変更が紐づく ID と影響範囲"
        while IFS= read -r id; do
            [ -z "$id" ] && continue
            echo ""
            echo "▶ $id"
            print_links "$id"
        done <<< "$UNIQ_IDS"
    else
        echo ""
        echo "変更ファイルに紐づく ID はありませんでした"
    fi

    BLOCKING=0
    if [ "${#UNTRACKED[@]}" -gt 0 ]; then
        echo ""
        echo "## 追跡不能変更（ID に紐づかないテスト/実装）"
        for f in "${UNTRACKED[@]}"; do
            echo "    ✗ $f : ID タグ / 注釈が無く、どの要件に紐づくか辿れません"
        done
        [ "$ENFORCE" = "block" ] && BLOCKING=${#UNTRACKED[@]}
    fi
    echo ""
    [ "$BLOCKING" -gt 0 ] && exit 2
    exit 0
fi

# ---------------------------------------------------------------------------
# 順方向: トレーサビリティ行列＋抜け漏れ
# ---------------------------------------------------------------------------
REPORT=$(awk -F'\t' -v ucp="$UCP" -v flp="$FLP" -v acp="$ACP" -v req_impl="$REQ_IMPL" '
function has(layer, id) { return ((layer SUBSEP id) in seen) }
function startsWith(s, p) { return substr(s, 1, length(p)+1) == (p "-") }
function isort(a, n,   i, j, key) {
    for (i=2; i<=n; i++) { key=a[i]; j=i-1
        while (j>=1 && a[j] > key) { a[j+1]=a[j]; j-- }
        a[j+1]=key }
}
{
    id=$1; layer=$2; loc=$3
    seen[layer, id]=1
    locs[layer, id]=locs[layer, id] (locs[layer, id] ? ", " : "") loc
    allids[id]=1
    if (layer=="req"    && startsWith(id, ucp)) { if (decl_uc[id]++ == 0) ucl[++nuc]=id; else dup_uc[id]=1 }
    if (layer=="design" && startsWith(id, flp)) { if (decl_fl[id]++ == 0) fll[++nfl]=id; else dup_fl[id]=1 }
}
END {
    ng=0; nw=0; nblock=0
    print "## トレーサビリティ行列"
    print ""
    print "| ID | 種別 | 設計 | テスト計画 | テスト | 実装 |"
    print "| --- | --- | :---: | :---: | :---: | :---: |"

    isort(ucl, nuc)
    for (i=1;i<=nuc;i++) { id=ucl[i]
        d = has("design",id) ? "✅" : "❌"
        p = has("plan",id)   ? "✅" : "❌"
        t = has("test",id)   ? "✅" : "❌"
        if (has("impl",id))        im="✅"
        else if (req_impl=="true") im="❌"
        else                       im="–"
        printf "| %s | UC | %s | %s | %s | %s |\n", id, d, p, t, im
        if (!has("design",id)) { gaps[++ng]="[設計漏れ] " id " : REQUIREMENTS(" locs["req",id] ") にあるが設計書（TECH_DESIGN / API_DESIGN / SCREEN_DESIGN）で参照なし"; nblock++ }
        if (!has("plan",id))   { gaps[++ng]="[テスト計画漏れ] " id " : テスト計画（TEST_PLAN / TEST_DESIGN）に対象 ID の記載なし"; nblock++ }
        if (!has("test",id))   { gaps[++ng]="[テスト実装漏れ] " id " : この ID を持つテストが存在しない"; nblock++ }
        if (!has("impl",id)) {
            if (req_impl=="true") { gaps[++ng]="[実装漏れ] " id " : @stdd 注釈を持つ実装が存在しない"; nblock++ }
            else                  { warns[++nw]="[実装未注釈] " id " : @stdd 注釈なし（任意・テスト経由で担保）" }
        }
    }

    isort(fll, nfl)
    for (i=1;i<=nfl;i++) { id=fll[i]
        p = has("plan",id) ? "✅" : "❌"
        t = has("test",id) ? "✅" : "❌"
        if (has("impl",id))        im="✅"
        else if (req_impl=="true") im="❌"
        else                       im="–"
        printf "| %s | FL | – | %s | %s | %s |\n", id, p, t, im
        if (!has("plan",id)) { gaps[++ng]="[テスト計画漏れ] " id " : テスト計画（TEST_PLAN §2 / API_TEST_DESIGN）に処理フローの記載なし"; nblock++ }
        if (!has("test",id)) { gaps[++ng]="[テスト実装漏れ] " id " : この ID を持つテストが存在しない"; nblock++ }
    }

    # 孤児参照: 宣言されていない ID の参照
    for (id in allids) {
        if (startsWith(id, ucp) && !(id in decl_uc)) {
            src=""
            if (has("design",id)) src=src "design(" locs["design",id] ") "
            if (has("plan",id))   src=src "test-plan(" locs["plan",id] ") "
            if (has("test",id))   src=src "test(" locs["test",id] ") "
            if (has("impl",id))   src=src "impl(" locs["impl",id] ") "
            gaps[++ng]="[孤児参照] " id " : REQUIREMENTS に未宣言の UC を参照 → " src; nblock++
        }
        if (startsWith(id, flp) && !(id in decl_fl)) {
            src=""
            if (has("plan",id)) src=src "test-plan(" locs["plan",id] ") "
            if (has("test",id)) src=src "test(" locs["test",id] ") "
            if (has("impl",id)) src=src "impl(" locs["impl",id] ") "
            gaps[++ng]="[孤児参照] " id " : 設計書（TECH_DESIGN §4.2 / API_DESIGN 章 4）に未宣言の FL を参照 → " src; nblock++
        }
    }

    # ID 重複宣言
    for (id in dup_uc) { gaps[++ng]="[ID重複] " id " : REQUIREMENTS に同一 UC が複数宣言 (" locs["req",id] ")"; nblock++ }
    for (id in dup_fl) { gaps[++ng]="[ID重複] " id " : 設計書に同一 FL が複数宣言 (" locs["design",id] ")"; nblock++ }

    isort(gaps, ng)
    isort(warns, nw)

    print ""
    if (ng==0 && nw==0) {
        print "## 抜け漏れ: なし ✅"
    } else {
        if (ng>0) { print "## 抜け漏れ（" ng " 件）"; for (i=1;i<=ng;i++) print "  ✗ " gaps[i] }
        if (nw>0) { print ""; print "## 警告（" nw " 件・非ブロッキング）"; for (i=1;i<=nw;i++) print "  ⚠ " warns[i] }
    }
    print ""
    print "__BLOCKING__ " nblock
}
' "$RECORDS")

BLOCKING=$(printf '%s\n' "$REPORT" | sed -n 's/^__BLOCKING__ //p')
BLOCKING=${BLOCKING:-0}

# 設計書の表の突合の結果（layered）。対象の件数を併記し、0 件のまま「なし」と表示しない
TABLE_REPORT=""
if [ "$TABLES_STATUS" != "single" ]; then
    if [ -n "$TABLES_STATUS" ]; then
        TABLE_REPORT="## 設計書の表の突合: 未実施（$TABLES_STATUS）"
    else
        COUNTS=$(awk -F'\t' '$1 == "doc" { n[$2]++ } $1 == "code" { c++ } $1 == "def" { d++ }
            END { printf "要件 %d・API 設計 %d・画面設計 %d・テスト設計 %d 件 / コード %d・行 ID %d 件",
                  n["requirements"], n["api_design"], n["screen_design"], n["api_test_design"] + n["screen_test_design"] + n["test_design"], c, d }' "$TABLE_FACTS")
        NT=$(printf '%s' "$TABLE_GAPS" | grep -c .)
        if [ "$N_LAYERED" -eq 0 ]; then
            TABLE_REPORT="## 設計書の表の突合: 対象の文書が 0 件（docs.lineup=layered だが API_DESIGN / SCREEN_DESIGN / テスト設計が見つからない）"
        elif [ "$NT" -eq 0 ]; then
            TABLE_REPORT="## 設計書の表の突合（$COUNTS）: 抜け漏れなし ✅"
        else
            TABLE_REPORT="## 設計書の表の突合（$COUNTS）: 抜け漏れ $NT 件
$(printf '%s\n' "$TABLE_GAPS" | sed 's/^/  ✗ /')"
            BLOCKING=$((BLOCKING + NT))
        fi
    fi
fi

echo "=========================================="
echo "トレーサビリティ監査（enforce=${ENFORCE}）"
echo "=========================================="
printf '%s\n' "$REPORT" | grep -v '^__BLOCKING__'
[ -n "$TABLE_REPORT" ] && { printf '%s\n' "$TABLE_REPORT"; echo ""; }

if [ "$ENFORCE" = "block" ] && [ "$BLOCKING" -gt 0 ]; then
    echo "✗ 抜け漏れ $BLOCKING 件（enforce=block）。処理を中止します。"
    exit 2
fi
if [ "$BLOCKING" -gt 0 ]; then
    echo "⚠ 抜け漏れ $BLOCKING 件（enforce=$ENFORCE のためブロックしません）。"
fi
exit 0
