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
shopt -s nullglob globstar 2>/dev/null

# glob 群 → リポジトリルート相対のファイル一覧（重複除去）
expand_globs() {
    local globs="$1" out=() g f
    cd "$ROOT" || return 0
    while IFS= read -r g; do
        [ -z "$g" ] && continue
        g=$(strip_quotes "$g")
        for f in $g; do
            [ -f "$f" ] && out+=("$f")
        done
    done <<< "$globs"
    printf '%s\n' "${out[@]}" | LC_ALL=C sort -u
}

TEST_FILES=$(expand_globs "$TEST_GLOBS")
IMPL_FILES=$(expand_globs "$IMPL_GLOBS")

# Spec ファイル（REQUIREMENTS / TECH_DESIGN / TEST_PLAN）
SPEC_FILES=$(cd "$ROOT" && find . -type f \
    \( -name REQUIREMENTS.md -o -name TECH_DESIGN.md -o -name TEST_PLAN.md \) \
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
    case "$f" in
        *REQUIREMENTS.md) emit_from_file "$f" req "" ;;
        *TECH_DESIGN.md)  emit_from_file "$f" design "" ;;
        *TEST_PLAN.md)    emit_from_file "$f" plan "" ;;
    esac
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

# ---------------------------------------------------------------------------
# 逆方向: --impact
# ---------------------------------------------------------------------------
if [ "$MODE" = "impact" ]; then
    echo "=========================================="
    echo "トレーサビリティ影響範囲（--impact）"
    echo "=========================================="
    BLOCKING=0
    for id in "${ARGS[@]}"; do
        echo ""
        echo "▶ $id"
        if ! grep -qP "^$id\t" "$RECORDS" 2>/dev/null && ! grep -q "^$id	" "$RECORDS"; then
            echo "    ⚠ この ID はどのレイヤにも存在しません（未定義 / タイプミスの可能性）"
            [ "$ENFORCE" = "block" ] && BLOCKING=$((BLOCKING+1))
            continue
        fi
        print_links "$id"
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
        if (!has("design",id)) { gaps[++ng]="[設計漏れ] " id " : REQUIREMENTS(" locs["req",id] ") にあるが TECH_DESIGN で参照なし"; nblock++ }
        if (!has("plan",id))   { gaps[++ng]="[テスト計画漏れ] " id " : TEST_PLAN に対象 ID の記載なし"; nblock++ }
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
        if (!has("plan",id)) { gaps[++ng]="[テスト計画漏れ] " id " : TEST_PLAN(§2) に処理フローの記載なし"; nblock++ }
        if (!has("test",id)) { gaps[++ng]="[テスト実装漏れ] " id " : この ID を持つテストが存在しない"; nblock++ }
    }

    # 孤児参照: 宣言されていない ID の参照
    for (id in allids) {
        if (startsWith(id, ucp) && !(id in decl_uc)) {
            src=""
            if (has("design",id)) src=src "TECH_DESIGN(" locs["design",id] ") "
            if (has("plan",id))   src=src "TEST_PLAN(" locs["plan",id] ") "
            if (has("test",id))   src=src "test(" locs["test",id] ") "
            if (has("impl",id))   src=src "impl(" locs["impl",id] ") "
            gaps[++ng]="[孤児参照] " id " : REQUIREMENTS に未宣言の UC を参照 → " src; nblock++
        }
        if (startsWith(id, flp) && !(id in decl_fl)) {
            src=""
            if (has("plan",id)) src=src "TEST_PLAN(" locs["plan",id] ") "
            if (has("test",id)) src=src "test(" locs["test",id] ") "
            if (has("impl",id)) src=src "impl(" locs["impl",id] ") "
            gaps[++ng]="[孤児参照] " id " : TECH_DESIGN(§4.2) に未宣言の FL を参照 → " src; nblock++
        }
    }

    # ID 重複宣言
    for (id in dup_uc) { gaps[++ng]="[ID重複] " id " : REQUIREMENTS に同一 UC が複数宣言 (" locs["req",id] ")"; nblock++ }
    for (id in dup_fl) { gaps[++ng]="[ID重複] " id " : TECH_DESIGN に同一 FL が複数宣言 (" locs["design",id] ")"; nblock++ }

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

echo "=========================================="
echo "トレーサビリティ監査（enforce=$ENFORCE）"
echo "=========================================="
printf '%s\n' "$REPORT" | grep -v '^__BLOCKING__'

if [ "$ENFORCE" = "block" ] && [ "$BLOCKING" -gt 0 ]; then
    echo "✗ 抜け漏れ $BLOCKING 件（enforce=block）。処理を中止します。"
    exit 2
fi
if [ "$BLOCKING" -gt 0 ]; then
    echo "⚠ 抜け漏れ $BLOCKING 件（enforce=$ENFORCE のためブロックしません）。"
fi
exit 0
