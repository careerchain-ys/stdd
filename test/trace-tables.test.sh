#!/bin/bash
# trace-audit.sh の「設計書の表の突合」（layered）の振る舞いテスト。
# test/fixtures/id-chain/ の整合した設計書一式を一時ディレクトリにコピーし、1 か所ずつ壊して、
# 検査が不合格にすること（不合格にすべき例）と、通してよい書き方を通すこと（誤検知しない例）を確かめる。
# あわせて、テンプレートの例文で書いた設計書一式を検査が読めることを確かめる。
#
#   bash test/trace-tables.test.sh

set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
AUDIT="$REPO_ROOT/packages/core/hooks/trace-audit.sh"
FIXTURE="$REPO_ROOT/test/fixtures/id-chain"
TEMPLATES="$REPO_ROOT/packages/core/skills/documenting-tech-specs/templates"

PASS=0
FAIL=0
ok() { PASS=$((PASS+1)); echo "  PASS: $1"; }
ng() { FAIL=$((FAIL+1)); echo "  FAIL: $1 (rc=$RC)"; echo "----- OUT -----"; printf '%s\n' "$OUT"; echo "---------------"; }

OUT=""; RC=0
run() { OUT=$(bash "$AUDIT" --root "$1" "${@:2}" 2>&1); RC=$?; }
assert_contains()     { printf '%s' "$OUT" | grep -qF -- "$2" && ok "$1" || ng "$1"; }
assert_not_contains() { printf '%s' "$OUT" | grep -qF -- "$2" && ng "$1" || ok "$1"; }
assert_rc()           { [ "$RC" -eq "$2" ] && ok "$1" || ng "$1 (want rc=$2)"; }

# BSD / GNU の両方で動く置換（perl は macOS と多くの Linux に標準で入っている）
subst() { perl -0pi -e "$1" "$2"; }

fresh() { D=$(mktemp -d); cp -R "$FIXTURE/." "$D/"; F="$D/docs/orders"; }

echo "trace-tables tests"

# --- 整合した一式は通る。対象の件数が 0 でないことも確かめる（0 件のまま合格にしない） ---
fresh; run "$D"
assert_rc "clean set passes" 0
assert_contains "clean: no gaps" "抜け漏れなし ✅"
assert_contains "clean: codes counted" "コード 4"
assert_not_contains "clean: no unreadable" "[表を読めない]"

# --- API 設計 ⇄ API テスト設計 ---
fresh; subst 's/^\| AT-02 .*\n//m' "$F/API_TEST_DESIGN.md"; run "$D"
assert_contains "missing AT row for code" "[テスト設計漏れ] ORD-1001"
assert_rc "block on gap" 2

fresh; subst 's/(\| `ORD-1001` .*\n)/$1| `ORD-1002` | – | 409 | 上限を超えた |\n/' "$F/API_DESIGN.md"; run "$D"
assert_contains "new code needs test row" "[テスト設計漏れ] ORD-1002"
assert_contains "new code needs screen row" "[画面の受け漏れ] ORD-1002"

fresh; subst 's/^(\| AT-02 \| )`ORD-1001`/$1`ORD-1003`/m' "$F/API_TEST_DESIGN.md"; run "$D"
assert_contains "test row targets unknown code" "[孤児参照] ORD-1003"

fresh; subst 's/(\| TR-01 .*\n)/$1| TR-02 | draft → submitted | `submitOrder` | – | なし |\n/' "$F/API_DESIGN.md"; run "$D"
assert_contains "transition needs test row" "[テスト設計漏れ] TR-02"

fresh; subst 's/^\| AT-07 .*\n//m' "$F/API_TEST_DESIGN.md"; run "$D"
assert_contains "flow needs test row" "[テスト設計漏れ] FL-orders-01"

fresh; subst 's/^(\| AT-04 .*\n)/$1| AT-03 | `ORD-9800` | 重複 | ✅ | ❌ | TODO | |\n/m' "$F/API_TEST_DESIGN.md"; run "$D"
assert_contains "duplicate row id" "[ID重複] AT-03"

# --- 要件 ⇄ API 設計（業務ルール） ---
fresh; subst 's/### BR-orders-01: 在庫の確認/### 在庫の確認/' "$F/API_DESIGN.md"; run "$D"
assert_contains "rule needs design section" "[設計漏れ] BR-orders-01"

fresh; subst 's/### BR-orders-01: 在庫の確認/### BR-orders-09: 在庫の確認/' "$F/API_DESIGN.md"; run "$D"
assert_contains "design rule not in requirements" "[孤児参照] BR-orders-09"

# --- レスポンスコードの形式と共通コード ---
fresh; subst 's/`ORD-1800` \| `VALIDATION_ERROR`/`ORD-1800` | `NOT_FOUND`/' "$F/API_DESIGN.md"; run "$D"
assert_contains "common code name mismatch" "[コード形式] ORD-1800 : 共通コード 1800 の commonCode は VALIDATION_ERROR"

fresh; subst 's/`ORD-0001` \| – \| 201/`ORD-001` | – | 201/' "$F/API_DESIGN.md"; run "$D"
assert_contains "code with 3 digits" "[コード形式] ORD-001"

fresh; subst 's/`ORD-0001` \| – \| 201/`ORD-0000` | – | 201/' "$F/API_DESIGN.md"; run "$D"
assert_contains "serial 000" "[コード形式] ORD-0000 : 連番 000"

fresh; subst 's/`ORD-0001` \| – \| 201/`ORD-0001` | `VALIDATION_ERROR` | 201/' "$F/API_DESIGN.md"; run "$D"
assert_contains "feature code with commonCode" "[コード形式] ORD-0001 : 機能固有のコード"

fresh; printf 'response_codes:\n  feature_code_pattern: "^[A-Z]{2}$"\n' >> "$D/.stdd.config.yml"; run "$D"
assert_contains "feature_code_pattern override" "[コード形式] ORD-0001"

fresh; printf 'response_codes:\n  common_codes:\n    - { name: VALIDATION_ERROR, code: "1800", http: 422 }\n' >> "$D/.stdd.config.yml"; run "$D"
assert_contains "common_codes override replaces list" "[コード形式] ORD-9800 : 連番 800〜999 は共通コードの枠だが"
assert_not_contains "common_codes override keeps listed code" "[コード形式] ORD-1800"

fresh; printf 'response_codes:\n  common_codes:\n    - name: VALIDATION_ERROR\n      code: "1800"\n      http: 422\n    - name: AUTH_REQUIRED\n      code: "9800"\n      http: 401\n' >> "$D/.stdd.config.yml"; run "$D"
assert_contains "common_codes block style" "抜け漏れなし ✅"

# --- API 設計 ⇄ 画面設計 ---
fresh; subst 's/^\| RS-04 .*\n//m' "$F/SCREEN_DESIGN.md"; run "$D"
assert_contains "band row removed -> 9800 not received" "[画面の受け漏れ] ORD-9800"
assert_contains "test row for removed RS is orphan" "[孤児参照] RS-04"

fresh; subst 's/(\| `ORD-1800` .*\n)/$1| `ORD-9001` | – | 403 | 権限が無い |\n/' "$F/API_DESIGN.md"; run "$D"
assert_not_contains "band row receives new 9-band code" "[画面の受け漏れ] ORD-9001"
assert_contains "new 9-band code still needs test row" "[テスト設計漏れ] ORD-9001"

fresh; subst 's/^\| RS-03 \| EV-02 \| `ORD-1800`/| RS-03 | EV-02 | `VALIDATION_ERROR`/m' "$F/SCREEN_DESIGN.md"; run "$D"
assert_not_contains "commonCode name receives the code" "[画面の受け漏れ] ORD-1800"

fresh; subst 's/^\| RS-02 \| EV-02 \| `ORD-1001`/| RS-02 | EV-02 | `ORD-1009`/m' "$F/SCREEN_DESIGN.md"; run "$D"
assert_contains "screen receives code the op never returns" "[孤児参照] ORD-1009"
assert_contains "and misses the real one" "[画面の受け漏れ] ORD-1001"

fresh; subst 's/\| B-01 の押下 \| `createOrder`/| B-01 の押下 | `deleteOrder`/' "$F/SCREEN_DESIGN.md"; run "$D"
assert_contains "screen calls unknown operation" "[孤児参照] deleteOrder"

fresh; subst 's/^\| RS-02 \| EV-02/| RS-02 | EV-09/m' "$F/SCREEN_DESIGN.md"; run "$D"
assert_contains "response row refers to unknown event" "[孤児参照] EV-09"

# --- 画面設計 ⇄ 画面テスト設計 ---
fresh; subst 's/^\| ST-01 .*\n//m' "$F/SCREEN_TEST_DESIGN.md"; run "$D"
assert_contains "validation needs test row" "[テスト設計漏れ] VA-01"

fresh; subst 's/^\| ST-02 \| EV-01/| ST-02 | EV-07/m' "$F/SCREEN_TEST_DESIGN.md"; run "$D"
assert_contains "screen test targets unknown event" "[孤児参照] EV-07"
assert_contains "and EV-01 is uncovered" "[テスト設計漏れ] EV-01"

fresh; run "$D"
assert_not_contains "catalog rows are not definitions" "[ID重複] I-01"

# --- 要件 ⇄ 統括テスト設計 ---
fresh; subst 's/^\| UC-orders-01 の受入基準 2 .*\n//m' "$F/TEST_DESIGN.md"; run "$D"
assert_contains "acceptance criterion uncovered" "[受入基準の担保漏れ] UC-orders-01 の受入基準 2"

fresh; subst 's/(\| UC-orders-01 の受入基準 2 .*\n)/$1| UC-orders-01 の受入基準 3 | 何か | AT-01 |\n/' "$F/TEST_DESIGN.md"; run "$D"
assert_contains "criterion beyond requirements" "[孤児参照] UC-orders-01 の受入基準 3"

fresh; subst 's/API_TEST_DESIGN 1.1 の AT-01/AT-99/' "$F/TEST_DESIGN.md"; run "$D"
assert_contains "covered_by refers to unknown row" "[孤児参照] AT-99"

fresh; subst 's/API_TEST_DESIGN 1.1 の AT-01/あとで決める/' "$F/TEST_DESIGN.md"; run "$D"
assert_contains "covered_by without row or test" "[担保先なし]"

fresh; subst 's/^\| UC-orders-01 \| P0 .*\n//m' "$F/TEST_DESIGN.md"; run "$D"
assert_contains "use case missing in TEST_DESIGN" "[テスト設計漏れ] UC-orders-01"

fresh; subst 's/(\| UC-orders-01 の受入基準 1 \| 作成する \| )API_TEST_DESIGN 1.1 の AT-01/$1`tests\/orders.test.ts::[UC-orders-01] 作成`/' "$F/TEST_DESIGN.md"; run "$D"
assert_not_contains "test reference is accepted as coverage" "[担保先なし]"
assert_not_contains "existing test reference path" "[テスト参照切れ]"

fresh; subst 's/tests\/orders.test.ts::\[AT-01\]/tests\/missing.test.ts::[AT-01]/' "$F/API_TEST_DESIGN.md"; run "$D"
assert_contains "test reference to missing file" "[テスト参照切れ] tests/missing.test.ts"

# --- 文書の組と、読めない表（通してはいけない例） ---
fresh; rm "$F/SCREEN_TEST_DESIGN.md"; run "$D"
assert_contains "screen design without its test design" "[文書の欠落] docs/orders : SCREEN_DESIGN に対になる SCREEN_TEST_DESIGN が無い"

fresh; rm "$F/TEST_DESIGN.md"; run "$D"
assert_contains "use cases without TEST_DESIGN" "[文書の欠落] docs/orders : 要件にユースケースがあるが TEST_DESIGN が無い"

fresh; subst 's/^\| コード \| commonCode/| Code | commonCode/m' "$F/API_DESIGN.md"; run "$D"
assert_contains "renamed column is unreadable" "[表を読めない]"
assert_not_contains "renamed column does not pass" "抜け漏れなし"

fresh; subst 's/^## 1\. 操作$/## 1. エンドポイント/m' "$F/API_DESIGN.md"; run "$D"
assert_contains "renamed chapter is unreadable" "[表を読めない] docs/orders : API_DESIGN に操作の章が見つからない"
subst 's/^docs:\n/docs:\n  structure:\n    api_design:\n      sections:\n        operations: "エンドポイント"\n/m' "$D/.stdd.config.yml"; run "$D"
assert_contains "docs.structure override is read" "抜け漏れなし ✅"

# 章名・列名はスクリプトに書かず構造定義から読む: 言語を en にすると日本語の見出しは読めない
fresh; subst 's/language: "ja"/language: "en"/' "$D/.stdd.config.yml"; run "$D"
assert_contains "names come from doc-structure.json per language" "[表を読めない] docs/orders : API_DESIGN に操作の章が見つからない"

fresh; subst 's/^\| ID \| 対象 \|/| No | 対象 |/mg' "$F/SCREEN_TEST_DESIGN.md"; run "$D"
assert_contains "test design with zero readable rows" "[表を読めない] docs/orders/SCREEN_TEST_DESIGN.md"

fresh; subst 's/^(\| `ORD-0001` \| – \| 201 \|)/| 未定 | – | 201 |/m' "$F/API_DESIGN.md"; run "$D"
assert_contains "code row without code" "[コード形式] docs/orders/API_DESIGN.md"

D=$(mktemp -d); mkdir -p "$D/docs/orders"; cp "$FIXTURE/.stdd.config.yml" "$D/"; cp "$FIXTURE/docs/orders/REQUIREMENTS.md" "$D/docs/orders/"; run "$D"
assert_contains "layered with no design docs is not a pass" "対象の文書が 0 件"
assert_not_contains "layered with no design docs: no ok mark" "抜け漏れなし"

# --- enforce=warn は報告だけ ---
fresh; subst 's/enforce: "block"/enforce: "warn"/' "$D/.stdd.config.yml"; subst 's/^\| AT-02 .*\n//m' "$F/API_TEST_DESIGN.md"; run "$D"
assert_rc "warn does not block" 0
assert_contains "warn still reports" "[テスト設計漏れ] ORD-1001"

# --- jq が無ければ未実施と表示する（合格とは表示しない） ---
NOJQ=$(mktemp -d)
for f in /bin/* /usr/bin/* /usr/local/bin/* /opt/homebrew/bin/*; do
    [ -x "$f" ] || continue
    b=${f##*/}; [ "$b" = "jq" ] && continue
    [ -e "$NOJQ/$b" ] || ln -s "$f" "$NOJQ/$b" 2>/dev/null
done
fresh; OUT=$(PATH="$NOJQ" bash "$AUDIT" --root "$D" 2>&1); RC=$?
assert_contains "without jq: not performed" "未実施（jq が見つからない"
assert_not_contains "without jq: no ok mark" "抜け漏れなし ✅"

# --- --impact はレスポンスコードの位置を示す ---
fresh; run "$D" --impact ORD-1001
assert_contains "impact: code table" "API 設計のコード表 : docs/orders/API_DESIGN.md"
assert_contains "impact: screen" "画面設計のレスポンス処理 : docs/orders/SCREEN_DESIGN.md"
assert_contains "impact: test design" "テスト設計の行 : docs/orders/API_TEST_DESIGN.md"

# --- 既定の共通コードの一覧は、レスポンスコード体系のガイド §4 と同じ ---
GUIDE=$(awk -F'|' '/^## 4\./{on=1} /^## 5\./{on=0} on && $2 ~ /`[A-Z_]+`/ && $3 ~ /`[0-9]+`/ { gsub(/[ `]/, "", $2); gsub(/[ `]/, "", $3); print $2 "=" $3 }' \
    "$REPO_ROOT/packages/core/skills/documenting-tech-specs/guides/response-codes.md" | LC_ALL=C sort | tr '\n' ' ')
SCRIPT=$(sed -n "s/.*COMMON_CODES=\$'\\(.*\\)'.*/\\1/p" "$AUDIT" | sed 's/\\n/\n/g; s/\\t/=/g' | LC_ALL=C sort | tr '\n' ' ')
[ -n "$GUIDE" ] && [ "$GUIDE" = "$SCRIPT" ] && ok "default common codes match the guide" || { RC=0; OUT="guide: $GUIDE / script: $SCRIPT"; ng "default common codes match the guide"; }

# --- テンプレートの例文で書いた一式を読める（章名・列名がテンプレートと一致している） ---
D=$(mktemp -d); mkdir -p "$D/docs/orders"; cp "$FIXTURE/.stdd.config.yml" "$D/"
extract_template() {  # $1=テンプレート $2=出力先。```` で囲んだ例文を取り出し、<feature> と XXX を埋める
    awk '/^````markdown/{on=1; next} /^````$/{on=0} on' "$1" | sed 's/<feature>/orders/g; s/XXX-/ORD-/g' > "$2"
}
extract_template "$REPO_ROOT/packages/core/skills/documenting-requirements/templates/requirements.md" "$D/docs/orders/REQUIREMENTS.md"
extract_template "$TEMPLATES/api-design.md"         "$D/docs/orders/API_DESIGN.md"
extract_template "$TEMPLATES/api-test-design.md"    "$D/docs/orders/API_TEST_DESIGN.md"
extract_template "$TEMPLATES/screen-design.md"      "$D/docs/orders/SCREEN_DESIGN.md"
extract_template "$TEMPLATES/screen-test-design.md" "$D/docs/orders/SCREEN_TEST_DESIGN.md"
extract_template "$TEMPLATES/test-design.md"        "$D/docs/orders/TEST_DESIGN.md"
run "$D"
assert_not_contains "templates: every table is readable" "[表を読めない]"
assert_not_contains "templates: no code format errors" "[コード形式]"
printf '%s' "$OUT" | grep -qE 'コード [1-9][0-9]*・行 ID [1-9][0-9]* 件' && ok "templates: codes and row ids are read" || ng "templates: codes and row ids are read"

echo ""
echo "Total: $((PASS+FAIL))  Pass: $PASS  Fail: $FAIL"
[ "$FAIL" -eq 0 ]
