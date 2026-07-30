#!/bin/bash
# trace-audit.sh の振る舞いテスト（外部テストフレームワーク非依存）。
# 一時ディレクトリに最小の feature spec / テスト / 実装を置き、順方向監査・
# 逆方向（--impact / --changed）・enforce 別の exit code を検証する。
#
#   bash test/trace-audit.test.sh
#
# このディレクトリ（test/）は配布対象外（sync-assets は .claude と templates のみ同期）。

set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
AUDIT="$REPO_ROOT/packages/core/hooks/trace-audit.sh"

PASS=0
FAIL=0
ok() { PASS=$((PASS+1)); echo "  PASS: $1"; }
ng() { FAIL=$((FAIL+1)); echo "  FAIL: $1 (rc=$RC)"; echo "----- OUT -----"; printf '%s\n' "$OUT"; echo "---------------"; }

OUT=""; RC=0
run() { OUT=$(bash "$AUDIT" --root "$1" "${@:2}"); RC=$?; }

assert_contains()     { printf '%s' "$OUT" | grep -qF "$2" && ok "$1" || ng "$1"; }
assert_not_contains() { printf '%s' "$OUT" | grep -qF "$2" && ng "$1" || ok "$1"; }
assert_rc()           { [ "$RC" -eq "$2" ] && ok "$1" || ng "$1 (want rc=$2)"; }

# in-place sed（BSD sed の `-i` は接尾辞必須のため GNU/BSD 両対応の一時ファイル方式）
sed_i() { local script="$1" file="$2"; sed "$script" "$file" > "$file.tmp" && mv "$file.tmp" "$file"; }

# 最小 .stdd.config.yml（traceability 付き）を書く。$2=enforce $3=require_impl_annotation
mkbase() {
    local dir="$1" enforce="${2:-warn}" reqimpl="${3:-false}"
    mkdir -p "$dir"
    cat > "$dir/.stdd.config.yml" <<YML
version: 1
project:
  name: "tmp"
  primary_branch: "main"
apps:
  - id: web
    path: "app"
commands:
  typecheck: "true"
  test: "true"
docs:
  layout:
    requirements: "docs/{{app.id}}/{{feature_path}}/REQUIREMENTS.md"
    tech_design: "docs/{{app.id}}/{{feature_path}}/TECH_DESIGN.md"
    test_plan: "docs/{{app.id}}/{{feature_path}}/TEST_PLAN.md"
    plan: "docs/{{app.id}}/{{feature_path}}/plans/{{date}}.md"
traceability:
  enabled: true
  enforce: "$enforce"
  require_impl_annotation: $reqimpl
  scan:
    tests:
      - "e2e/**/*.spec.ts"
      - "**/*.test.ts"
    impl:
      - "app/**"
      - "lib/**"
YML
    mkdir -p "$dir/docs/web/applies" "$dir/app" "$dir/lib" "$dir/e2e"
}

# 全リンクが揃った 1 ユースケース分の spec / test / impl を書く
write_clean_uc() {
    local dir="$1"
    printf '#### 応募一覧の閲覧 [UC-applies-01]\n' > "$dir/docs/web/applies/REQUIREMENTS.md"
    printf '| UC-applies-01 | P0 | §4.1 |\n' > "$dir/docs/web/applies/TECH_DESIGN.md"
    printf '| UC-applies-01 | P0 | ✅ |\n' > "$dir/docs/web/applies/TEST_PLAN.md"
    printf "describe('[UC-applies-01] 閲覧', () => {})\n" > "$dir/e2e/applies.spec.ts"
    printf '// @stdd UC-applies-01\nexport const x = 1\n' > "$dir/app/applies.ts"
}

echo "trace-audit.sh tests"

# 1. config 無し → スキップ（フェイルオープン）
D=$(mktemp -d)
run "$D"; assert_rc "no config -> skip" 0; assert_contains "no config message" "スキップ"
rm -rf "$D"

# 2. enabled=false → スキップ
D=$(mktemp -d); mkbase "$D" warn; sed_i 's/enabled: true/enabled: false/' "$D/.stdd.config.yml"
run "$D"; assert_rc "enabled=false -> skip" 0; assert_contains "disabled message" "enabled=false"
rm -rf "$D"

# 3. 完全に揃った feature → 抜け漏れなし / exit 0
D=$(mktemp -d); mkbase "$D" warn; write_clean_uc "$D"
run "$D"; assert_rc "clean feature rc0" 0; assert_contains "clean: no gaps" "抜け漏れ: なし"
assert_contains "clean: matrix row all green" "| UC-applies-01 | UC | ✅ | ✅ | ✅ | ✅ |"
rm -rf "$D"

# 4. 設計漏れ: REQUIREMENTS の UC が TECH_DESIGN に無い
D=$(mktemp -d); mkbase "$D" warn
printf '#### 未設計 [UC-applies-02]\n' > "$D/docs/web/applies/REQUIREMENTS.md"
run "$D"; assert_contains "design gap detected" "[設計漏れ] UC-applies-02"
rm -rf "$D"

# 5. テスト計画漏れ / テスト実装漏れ（設計はあるが計画・テストが無い）
D=$(mktemp -d); mkbase "$D" warn
printf '#### 詳細 [UC-applies-03]\n' > "$D/docs/web/applies/REQUIREMENTS.md"
printf '| UC-applies-03 | P1 | §4.1 |\n' > "$D/docs/web/applies/TECH_DESIGN.md"
run "$D"
assert_contains "test-plan gap" "[テスト計画漏れ] UC-applies-03"
assert_contains "test-impl gap" "[テスト実装漏れ] UC-applies-03"
rm -rf "$D"

# 6. 孤児参照: 実在しない UC を検証するテスト
D=$(mktemp -d); mkbase "$D" warn; write_clean_uc "$D"
printf "describe('[UC-applies-99] orphan', () => {})\n" > "$D/app/orphan.test.ts"
run "$D"; assert_contains "orphan test detected" "[孤児参照] UC-applies-99"
rm -rf "$D"

# 7. FL（その他処理フロー）: 宣言・計画済みだがテスト無し → テスト実装漏れ
D=$(mktemp -d); mkbase "$D" warn
printf '#### 集計 [UC-applies-04]\n' > "$D/docs/web/applies/REQUIREMENTS.md"
printf '| UC-applies-04 | P0 | §4.1 |\n#### 夜間バッチ [FL-applies-01]\n' > "$D/docs/web/applies/TECH_DESIGN.md"
printf '| UC-applies-04 | ✅ |\n| FL-applies-01 | ❌ |\n' > "$D/docs/web/applies/TEST_PLAN.md"
printf "describe('[UC-applies-04] 集計', () => {})\n" > "$D/e2e/a.spec.ts"
run "$D"
assert_contains "FL row present" "| FL-applies-01 | FL |"
assert_contains "FL test-impl gap" "[テスト実装漏れ] FL-applies-01"
rm -rf "$D"

# 8. enforce=warn は抜け漏れがあっても exit 0、block は exit 2
D=$(mktemp -d); mkbase "$D" warn
printf '#### 未設計 [UC-applies-05]\n' > "$D/docs/web/applies/REQUIREMENTS.md"
run "$D"; assert_rc "warn does not block" 0
sed_i 's/enforce: "warn"/enforce: "block"/' "$D/.stdd.config.yml"
run "$D"; assert_rc "block blocks on gap" 2
rm -rf "$D"

# 9. require_impl_annotation: 未注釈が警告→抜け漏れ（block で exit 2）
D=$(mktemp -d); mkbase "$D" warn false
printf '#### 閲覧 [UC-applies-06]\n' > "$D/docs/web/applies/REQUIREMENTS.md"
printf '| UC-applies-06 | P0 | §4.1 |\n' > "$D/docs/web/applies/TECH_DESIGN.md"
printf '| UC-applies-06 | ✅ |\n' > "$D/docs/web/applies/TEST_PLAN.md"
printf "describe('[UC-applies-06]', () => {})\n" > "$D/e2e/a.spec.ts"
run "$D"; assert_contains "missing impl is warning by default" "[実装未注釈] UC-applies-06"
sed_i 's/require_impl_annotation: false/require_impl_annotation: true/' "$D/.stdd.config.yml"
run "$D"; assert_contains "require_impl_annotation promotes to gap" "[実装漏れ] UC-applies-06"
rm -rf "$D"

# 10. --impact: 既存 ID は全リンクを列挙 / 未知 ID は警告
D=$(mktemp -d); mkbase "$D" warn; write_clean_uc "$D"
run "$D" --impact UC-applies-01
assert_contains "impact lists requirement" "要件"
assert_contains "impact lists impl loc" "app/applies.ts"
run "$D" --impact UC-applies-77
assert_contains "impact unknown id warned" "存在しません"
rm -rf "$D"

# 11. --changed: 追跡可能な実装は影響範囲 / ID 無しは追跡不能変更
D=$(mktemp -d); mkbase "$D" warn; write_clean_uc "$D"
printf 'export const y = 2\n' > "$D/app/untracked.ts"
run "$D" --changed app/applies.ts
assert_contains "changed tracked shows impact id" "UC-applies-01"
assert_not_contains "changed tracked has no untraceable" "追跡不能変更"
run "$D" --changed app/untracked.ts
assert_contains "changed untracked flagged" "追跡不能変更"
assert_contains "changed untracked names file" "app/untracked.ts"
# block では追跡不能変更で exit 2
sed_i 's/enforce: "warn"/enforce: "block"/' "$D/.stdd.config.yml"
run "$D" --changed app/untracked.ts; assert_rc "changed untracked blocks under block" 2
rm -rf "$D"

echo ""
echo "Total: $((PASS+FAIL))  Pass: $PASS  Fail: $FAIL"
[ "$FAIL" -eq 0 ]
