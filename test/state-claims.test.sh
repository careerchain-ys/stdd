#!/bin/bash
# 転記の検査（skills/documenting-requirements/scripts/state-claims.sh）の振る舞いテスト。
# あわせて、STDD 自身の skill・agent・規約・方法論の文書に転記が無いことを確かめる（docs/config-driven-authoring.md §8）。
#   bash test/state-claims.test.sh
# このディレクトリ（test/）は配布対象外。

set -u
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$REPO_ROOT/packages/core/skills/documenting-requirements/scripts/state-claims.sh"

PASS=0
FAIL=0
OUT=""; RC=0
ok() { PASS=$((PASS+1)); echo "  PASS: $1"; }
ng() { FAIL=$((FAIL+1)); echo "  FAIL: $1 (rc=$RC)"; echo "----- OUT -----"; printf '%s\n' "$OUT"; echo "---------------"; }
assert_contains()     { printf '%s' "$OUT" | grep -qF -- "$2" && ok "$1" || ng "$1"; }
assert_not_contains() { printf '%s' "$OUT" | grep -qF -- "$2" && ng "$1" || ok "$1"; }
assert_rc()           { [ "$RC" -eq "$2" ] && ok "$1" || ng "$1 (want rc=$2)"; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/stdd-claims-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

sc() { OUT=$(bash "$SCRIPT" --root "$DIR" "$@" 2>&1); RC=$?; }

# $1 = ディレクトリ名、$2 = docs: の下に足す行（空可）、$3 = project.language（既定 ja）
make_repo() {
    DIR="$TMP_ROOT/$1"
    mkdir -p "$DIR/docs/order"
    {
        echo "version: 1"
        echo "project:"
        echo "  name: \"t\""
        echo "  language: \"${3:-ja}\""
        echo "docs:"
        echo "  lineup: \"layered\""
        echo "  layout:"
        echo "    requirements: \"docs/{{feature_path}}/REQUIREMENTS.md\""
        echo "    test_design: \"docs/{{feature_path}}/TEST_DESIGN.md\""
        echo "    plan: \"docs/{{feature_path}}/plans/{{date}}.md\""
        [ -n "$2" ] && printf '%s\n' "$2"
    } > "$DIR/.stdd.config.yml"
}

echo "== 不合格にすべき例 =="
make_repo ng ""
cat > "$DIR/docs/order/TEST_DESIGN.md" <<'MD'
# テスト設計

## 1. 担保

この機能の画面は 3 画面あり、うち 2 画面は未作成である。
`4 機能` は実装済みなので、残りを担保する。
関係する機能 2 件のうち、受け取り側はまだ無い。
MD
sc
assert_rc "件数の句と状態の語が同じ文にあれば exit 1" 1
assert_contains "数字 + 名詞の形を見つける" "docs/order/TEST_DESIGN.md:5: この機能の画面は 3 画面あり、うち 2 画面は未作成である。"
assert_contains "インラインのコードの中も見る" "docs/order/TEST_DESIGN.md:6:"
assert_contains "名詞 + 数字 + 助数詞の形を見つける" "docs/order/TEST_DESIGN.md:7:"
assert_contains "件数を知らせる" "3 件あります"

echo "== 通す例 =="
make_repo okcase ""
cat > "$DIR/docs/order/TEST_DESIGN.md" <<'MD'
# テスト設計

## 2.2 3 機能の未作成の一覧

行が 0 件のときは、空の表示を出す。
上限は非機能要件の表（NFR-03）を参照する。
画面は UI-ORD-01 と UI-ORD-02 の 2 つ。作成状況は検査のコマンドで調べる。
3 画面ある。未作成の文書は TODO と書く。

```
この機能は 5 画面で、うち 2 画面が未作成。
```

## 更新履歴

- 1.1: 3 画面を未作成として追加した
MD
sc
assert_rc "片方だけの文・見出し・コード・更新履歴は通す" 0
assert_contains "見た文書の数を出す" "state-claims OK: 1 件の文書"

echo "== 対象の指定 =="
make_repo paths ""
mkdir -p "$DIR/notes"
echo "この skill は 2 agent が未対応。" > "$DIR/notes/a.md"
sc
assert_rc "既定は docs.layout の文書だけを見る" 0
sc notes
assert_rc "パスを渡せばそのディレクトリを見る" 1
assert_contains "渡したディレクトリの文書を見つける" "notes/a.md:1:"

echo "== 語彙の上書き =="
make_repo vocab "  state_claims:
    nouns: [\"帳票\"]
    words:
      - \"出力待ち\""
cat > "$DIR/docs/order/TEST_DESIGN.md" <<'MD'
# テスト設計

帳票は 4 帳票あり、うち 1 帳票は出力待ちである。
この機能の画面は 3 画面あり、うち 2 画面は未作成である。
MD
sc
assert_rc "設定の語彙で見つける" 1
assert_contains "設定の名詞と語を使う" "docs/order/TEST_DESIGN.md:3:"
assert_not_contains "設定に書いた一覧で既定を置き換える" "docs/order/TEST_DESIGN.md:4:"

echo "== 英語の既定 =="
make_repo en "" en
cat > "$DIR/docs/order/TEST_DESIGN.md" <<'MD'
# Test design

There are 3 screens. 2 screens are not yet implemented. Rows are empty when 0 rows match.
MD
sc
assert_rc "project.language が en なら英語の語彙を使う" 1
assert_contains "英語の文を区切って見る" "2 screens are not yet implemented."
assert_not_contains "同じ行のほかの文は出さない" "Rows are empty"

echo "== 文書が無い =="
make_repo empty ""
sc
assert_rc "見る文書が無ければ exit 0" 0

echo "== STDD 自身の定義 =="
DIR="$REPO_ROOT"
sc packages/core/skills packages/core/agents packages/core/rules packages/core/docs
assert_rc "skill・agent・規約・方法論の文書に転記が無い" 0

echo
echo "結果: PASS $PASS / FAIL $FAIL"
[ "$FAIL" -eq 0 ]
