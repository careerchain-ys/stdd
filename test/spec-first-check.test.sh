#!/bin/bash
# spec-first-check.sh フックの振る舞いテスト（外部テストフレームワーク非依存）。
# 一時 git リポジトリを用意し、スタブの hook 入力を stdin で流して stdout / exit code を検証する。
#
#   bash test/spec-first-check.test.sh
#
# このディレクトリ（test/）は配布対象外（sync-assets は .claude と templates のみ同期）。

set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOOK="$REPO_ROOT/.claude/hooks/spec-first-check.sh"

PASS=0
FAIL=0

# 一時 git リポジトリを作り、最低限の .stdd.config.yml を置いて初期コミットする。
# $1: enforce_spec_first の値（空なら行を出さない＝既定 warn）
make_repo() {
    local mode="$1"
    local dir
    dir=$(mktemp -d)
    (
        cd "$dir" || exit 1
        git init -q
        git config user.email t@example.com
        git config user.name test
        {
            echo "version: 1"
            echo "project:"
            echo "  name: \"tmp\""
            echo "  primary_branch: \"main\""
            echo "apps:"
            echo "  - id: app"
            echo "    path: \".\""
            echo "commands:"
            echo "  typecheck: \"true\""
            echo "  test: \"true\""
            echo "docs:"
            echo "  layout:"
            echo "    requirements: \"docs/{{feature_path}}/REQUIREMENTS.md\""
            echo "    tech_design: \"docs/{{feature_path}}/TECH_DESIGN.md\""
            echo "    plan: \"docs/{{feature_path}}/plans/{{date}}.md\""
            echo "workflow:"
            echo "  branch_prefix: \"claude/\""
            [ -n "$mode" ] && echo "  enforce_spec_first: \"$mode\""
        } > .stdd.config.yml
        git add -A
        git commit -qm init
    )
    printf '%s' "$dir"
}

OUT=""
RC=0
# $1=repo dir, $2=file_path → sets globals OUT and RC（コマンド置換を介さないので RC が残る）
run_hook() {
    local dir="$1" file="$2"
    OUT=$( cd "$dir" && printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$file" | bash "$HOOK" )
    RC=$?
}

# $1=description $2=condition(0/1 already evaluated via [ ]) -- we pass via function below
ok() { PASS=$((PASS+1)); echo "  PASS: $1"; }
ng() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

assert_silent_exit0() {
    local desc="$1" out="$2"
    if [ "$RC" -eq 0 ] && [ -z "$out" ]; then ok "$desc"; else
        ng "$desc (rc=$RC out='$out')"; fi
}

assert_contains_exit0() {
    local desc="$1" out="$2" needle="$3"
    if [ "$RC" -eq 0 ] && printf '%s' "$out" | grep -q "$needle"; then ok "$desc"; else
        ng "$desc (rc=$RC out='$out')"; fi
}

echo "spec-first-check.sh tests"

# 1. 実装ファイル（warn 既定）→ additionalContext を含む / exit 0
D=$(make_repo "")
run_hook "$D" "src/foo.ts"; assert_contains_exit0 "impl file (warn default) emits additionalContext" "$OUT" "additionalContext"

# 2. Spec ファイル → 無言 / exit 0
run_hook "$D" "docs/feature-x/REQUIREMENTS.md"; assert_silent_exit0 "spec file is silent" "$OUT"

# 3. テストファイル → 無言 / exit 0
run_hook "$D" "src/foo.test.ts"; assert_silent_exit0 "test file (*.test.*) is silent" "$OUT"
run_hook "$D" "src/__tests__/foo.ts"; assert_silent_exit0 "test file (__tests__/) is silent" "$OUT"
run_hook "$D" "e2e/login.spec.ts"; assert_silent_exit0 "e2e spec is silent" "$OUT"

# 4. .claude 配下 → 無言
run_hook "$D" ".claude/skills/x/SKILL.md"; assert_silent_exit0 ".claude file is silent" "$OUT"

# 5. 非ソース拡張子 / ロックファイル → 無言
run_hook "$D" "package.json"; assert_silent_exit0 "package.json is silent" "$OUT"
run_hook "$D" "package-lock.json"; assert_silent_exit0 "lockfile is silent" "$OUT"
run_hook "$D" "src/styles.css"; assert_silent_exit0 "css is silent" "$OUT"
run_hook "$D" ".env.local"; assert_silent_exit0 ".env is silent" "$OUT"

# 6. 絶対パスでも実装ファイルとして判定される
run_hook "$D" "$D/src/bar.tsx"; assert_contains_exit0 "absolute impl path emits reminder" "$OUT" "additionalContext"

# 7. config 無し → 無言（フェイルオープン）
DNC=$(mktemp -d); ( cd "$DNC" && git init -q && git config user.email t@e.com && git config user.name t && git commit -q --allow-empty -m init )
OUT=$( cd "$DNC" && printf '{"tool_name":"Edit","tool_input":{"file_path":"src/foo.ts"}}' | bash "$HOOK" ); RC=$?
assert_silent_exit0 "no config is silent" "$OUT"

# 8. enforce_spec_first: off → 実装ファイルでも無言
DOFF=$(make_repo "off")
run_hook "$DOFF" "src/foo.ts"; assert_silent_exit0 "mode=off is silent for impl" "$OUT"

# 9. enforce_spec_first: block → Spec/テスト未変更なら deny
DBLK=$(make_repo "block")
run_hook "$DBLK" "src/foo.ts"; assert_contains_exit0 "mode=block denies when no spec/test change" "$OUT" '"deny"'

# 10. enforce_spec_first: block → ブランチに Spec 変更があれば許可（無言）
( cd "$DBLK" && mkdir -p docs/feature-x && echo "x" > docs/feature-x/REQUIREMENTS.md && git add docs/feature-x/REQUIREMENTS.md )
run_hook "$DBLK" "src/foo.ts"; assert_silent_exit0 "mode=block allows when spec changed on branch" "$OUT"

# 後片付け
rm -rf "$D" "$DNC" "$DOFF" "$DBLK"

echo ""
echo "Total: $((PASS+FAIL))  Pass: $PASS  Fail: $FAIL"
[ "$FAIL" -eq 0 ]
