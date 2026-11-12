#!/bin/bash
# 改修で直す文書の決定と古い記述の残りの確認（skills/revising-specs/scripts/spec-propagation.sh）の振る舞いテスト。
#   bash test/spec-propagation.test.sh
# このディレクトリ（test/）は配布対象外。

set -u
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$REPO_ROOT/packages/core/skills/revising-specs/scripts/spec-propagation.sh"

PASS=0
FAIL=0
OUT=""; RC=0
ok() { PASS=$((PASS+1)); echo "  PASS: $1"; }
ng() { FAIL=$((FAIL+1)); echo "  FAIL: $1 (rc=$RC)"; echo "----- OUT -----"; printf '%s\n' "$OUT"; echo "---------------"; }
assert_contains()     { printf '%s' "$OUT" | grep -qF -- "$2" && ok "$1" || ng "$1"; }
assert_not_contains() { printf '%s' "$OUT" | grep -qF -- "$2" && ng "$1" || ok "$1"; }
assert_rc()           { [ "$RC" -eq "$2" ] && ok "$1" || ng "$1 (want rc=$2)"; }
# $2 で始まる行が $3 で始まる行より前に出る
line_of() { printf '%s\n' "$OUT" | awk -v p="$1" 'index($0, p) == 1 { print NR; exit }'; }
assert_before() {
    local a b
    a=$(line_of "$2")
    b=$(line_of "$3")
    if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then ok "$1"; else ng "$1"; fi
}

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/stdd-propagation-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

sp() { OUT=$(bash "$SCRIPT" --root "$DIR" "$@" 2>&1); RC=$?; }

# layered の構成（API と画面の両方）。order 機能は要件・API 設計・画面設計だけがある
layered_repo() {
    DIR="$TMP_ROOT/$1"
    mkdir -p "$DIR/docs/order" "$DIR/docs/cart" "$DIR/docs/common"
    cat > "$DIR/.stdd.config.yml" <<'YML'
version: 1
project:
  name: "t"
docs:
  lineup: "layered"
  layout:
    common_requirements: "docs/common/REQUIREMENTS.md"
    common_api_spec: "docs/common/API_SPEC.md"
    requirements: "docs/{{feature_path}}/REQUIREMENTS.md"
    api_design: "docs/{{feature_path}}/API_DESIGN.md"
    api_test_design: "docs/{{feature_path}}/API_TEST_DESIGN.md"
    screen_design: "docs/{{feature_path}}/SCREEN_DESIGN.md"
    screen_test_design: "docs/{{feature_path}}/SCREEN_TEST_DESIGN.md"
    test_design: "docs/{{feature_path}}/TEST_DESIGN.md"
    plan: "docs/{{feature_path}}/plans/{{date}}.md"
YML
    echo "UC-ORD-01 注文を確定する。在庫が足りなければ注文を受け付けない。" > "$DIR/docs/order/REQUIREMENTS.md"
    echo "ORD-1001 在庫が足りない" > "$DIR/docs/order/API_DESIGN.md"
    echo "RS-01 ORD-1001 を受けて在庫不足の文言を出す" > "$DIR/docs/order/SCREEN_DESIGN.md"
    echo "RS-03 ORD-1001 を受けてカートに戻す" > "$DIR/docs/cart/SCREEN_DESIGN.md"
    : > "$DIR/docs/common/API_SPEC.md"
}

echo "== targets: layered =="
layered_repo layered
sp targets requirements --feature order
assert_rc "要件を起点に出せる" 0
assert_contains "API 設計が候補に入る" "api_design	docs/order/API_DESIGN.md	あり"
assert_contains "画面設計が候補に入る" "screen_design	docs/order/SCREEN_DESIGN.md	あり"
assert_contains "common の API 仕様が候補に入る" "common_api_spec	docs/common/API_SPEC.md	あり"
assert_contains "まだ無いテスト設計は「無い」と出す" "test_design	docs/order/TEST_DESIGN.md	無い"
assert_before "API 設計を画面設計より先に直す" "api_design	" "screen_design	"
assert_before "画面設計を層別のテスト設計より先に直す" "screen_design	" "screen_test_design	"
assert_before "層別のテスト設計を TEST_DESIGN より先に直す" "screen_test_design	" "test_design	"
assert_before "文書の後にテスト、その後に実装" "tests	" "impl	"
assert_not_contains "計画書は改修の対象に入れない" "plan	"
assert_not_contains "single の文書は出さない" "tech_design"

sp targets screen_design --feature order
assert_rc "画面設計を起点に出せる" 0
assert_not_contains "画面設計の変更は API 設計に戻らない" "api_design	"
assert_not_contains "画面設計の変更は要件に戻らない" "requirements	"
assert_contains "画面設計の変更は画面のテスト設計に及ぶ" "screen_test_design	"
assert_contains "画面設計の変更は TEST_DESIGN に及ぶ" "test_design	"

sp targets api_design
assert_rc "--feature なしでもテンプレートのまま出せる" 0
assert_contains "パスはテンプレートのまま" "api_design	docs/{{feature_path}}/API_DESIGN.md	-"
assert_contains "API 設計の変更は画面設計に及ぶ（画面がコードを受ける）" "screen_design	"

sp targets tech_design
assert_rc "layered に無い文書のキーは拒否する" 2
assert_contains "構成に無いことを知らせる" "docs.lineup=layered の構成に無い"

sp targets unknown_doc
assert_rc "知らないキーは拒否する" 2

echo "== targets: layered（画面を持たない構成） =="
layered_repo api-only
sed -i.bak '/screen_/d' "$DIR/.stdd.config.yml" && rm -f "$DIR/.stdd.config.yml.bak"
sp targets requirements --feature order
assert_not_contains "layout に無い画面の文書は出さない" "screen_design"
assert_contains "layout に無い文書を通り抜けて TEST_DESIGN に届く" "test_design	"

echo "== targets: single =="
DIR="$TMP_ROOT/single"
mkdir -p "$DIR/docs/login"
cat > "$DIR/.stdd.config.yml" <<'YML'
version: 1
docs:
  layout:
    requirements: "docs/{{feature_path}}/REQUIREMENTS.md"
    tech_design: "docs/{{feature_path}}/TECH_DESIGN.md"
    test_plan: "docs/{{feature_path}}/TEST_PLAN.md"
    common_table_definition: "docs/common/TABLE_DEFINITION.md"
YML
: > "$DIR/docs/login/REQUIREMENTS.md"
sp targets requirements --feature login
assert_rc "lineup を書いていなければ single として扱う" 0
assert_contains "docs.lineup=single と出す" "docs.lineup=single"
assert_contains "TECH_DESIGN が候補に入る" "tech_design	docs/login/TECH_DESIGN.md	無い"
assert_before "TECH_DESIGN を TEST_PLAN より先に直す" "tech_design	" "test_plan	"
assert_contains "要件の変更は common のテーブル定義に及びうる" "common_table_definition	"
sp targets common_table_definition --feature login
assert_contains "テーブル定義の変更は TECH_DESIGN に及ぶ" "tech_design	"
assert_not_contains "テーブル定義の変更は要件に戻らない" "requirements	"

echo "== order =="
layered_repo order
sp order
assert_rc "order は exit 0" 0
assert_before "要件は設計書より前" "requirements	" "api_design	"
assert_not_contains "order に計画書は出さない" "plan	"

echo "== search =="
layered_repo search
sp search ORD-1001 "在庫が足りない"
assert_rc "見つかっても --expect-none が無ければ exit 0" 0
assert_contains "ほかの機能の文書も探す" "docs/cart/SCREEN_DESIGN.md:1:"
assert_contains "ID の件数を出す" "## ORD-1001（3 件）"
assert_contains "変更前の語でも探す" "## 在庫が足りない（1 件）"

sp search --feature order ORD-1001
assert_not_contains "--feature を付けるとほかの機能の文書を探さない" "docs/cart/"

sp search --expect-none ORD-1001
assert_rc "古い記述が残っていれば --expect-none で exit 1" 1
assert_contains "残っていることを知らせる" "古い記述が残っています"

# ID は直したが、変更前の説明文が要件に残っている（ID だけの検索では見つからない）
printf 'UC-ORD-01 注文を確定する。在庫を引き当てられなければ注文を保留する。\n在庫が足りなければ注文を受け付けない。\n' > "$DIR/docs/order/REQUIREMENTS.md"
sed -i.bak 's/ORD-1001 在庫が足りない/ORD-1002 在庫を引き当てられない/' "$DIR/docs/order/API_DESIGN.md" && rm -f "$DIR/docs/order/API_DESIGN.md.bak"
sp search --expect-none "受け付けない"
assert_rc "変更前の語が残っていれば exit 1" 1
assert_contains "残っている行を出す" "docs/order/REQUIREMENTS.md:2:"

sp search --expect-none ORD-9999 "存在しない語"
assert_rc "残りが無ければ exit 0" 0
assert_contains "0 件と出す" "## ORD-9999（0 件）"

mkdir -p "$DIR/src"
echo "// ORD-1001 のとき在庫不足" > "$DIR/src/order.ts"
sp search --also src ORD-1001
assert_contains "--also で実装のディレクトリも探す" "src/order.ts:1:"

sp search
assert_rc "語が無ければ exit 2" 2

echo "== 設定が無い =="
DIR="$TMP_ROOT/noconfig"; mkdir -p "$DIR"
sp order
assert_rc "設定が無ければ exit 2" 2

echo
echo "結果: PASS $PASS / FAIL $FAIL"
[ "$FAIL" -eq 0 ]
