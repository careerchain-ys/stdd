# フィードバックの仕組みのテストで共有する補助（source して使う）。
# 偽の gh を PATH の先頭に置き、一時的な git リポジトリを用意する。jq が必要。

PASS=0
FAIL=0
OUT=""; RC=0
ok() { PASS=$((PASS+1)); echo "  PASS: $1"; }
ng() { FAIL=$((FAIL+1)); echo "  FAIL: $1 (rc=$RC)"; echo "----- OUT -----"; printf '%s\n' "$OUT"; echo "---------------"; }
assert_contains()     { printf '%s' "$OUT" | grep -qF -- "$2" && ok "$1" || ng "$1"; }
assert_not_contains() { printf '%s' "$OUT" | grep -qF -- "$2" && ng "$1" || ok "$1"; }
assert_rc()           { [ "$RC" -eq "$2" ] && ok "$1" || ng "$1 (want rc=$2)"; }
assert_file_contains() { grep -qF -- "$3" "$2" 2>/dev/null && ok "$1" || { OUT=$(cat "$2" 2>/dev/null); ng "$1"; }; }
assert_file_not_contains() { grep -qF -- "$3" "$2" 2>/dev/null && { OUT=$(cat "$2"); ng "$1"; } || ok "$1"; }

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq が無いためテストを実行できません"
    exit 0
fi

LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/stdd-fb-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT/bin"
ln -s "$LIB_DIR/fake-gh" "$TMP_ROOT/bin/gh"
export PATH="$TMP_ROOT/bin:$PATH"
export STDD_NOW=1767225600   # 2026-01-01T00:00:00Z

# 新しい fixture ディレクトリと git リポジトリ（ブランチ claude/test、コミット 1 つ）を作る
#   $1 = 名前。FAKE_GH と REPO_DIR を設定する
new_case() {
    export FAKE_GH="$TMP_ROOT/$1/gh"
    REPO_DIR="$TMP_ROOT/$1/repo"
    mkdir -p "$FAKE_GH" "$REPO_DIR"
    : > "$FAKE_GH/calls.log"
    : > "$FAKE_GH/bodies.log"
    (
        cd "$REPO_DIR" || exit 1
        git init -q -b main
        git config user.email t@example.com
        git config user.name t
        echo x > README.md
        git add README.md
        GIT_COMMITTER_DATE="@1767222000 +0000" GIT_AUTHOR_DATE="@1767222000 +0000" git commit -q -m init
        git checkout -q -b claude/test
    )
}

# .stdd.config.yml を書く（$1 = 追記する YAML）
write_config() {
    cat > "$REPO_DIR/.stdd.config.yml" <<YML
version: 1
project:
  name: "tmp"
  primary_branch: "main"
apps:
  - id: app
    path: "."
commands:
  test: "true"
docs:
  layout:
    requirements: "docs/{{feature_path}}/REQUIREMENTS.md"
$1
YML
}

# ISO 8601（UTC）を返す。$1 = STDD_NOW からの日数（負なら過去）
iso_days() { date -u -r $((STDD_NOW + $1 * 86400)) +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$((STDD_NOW + $1 * 86400))" +%Y-%m-%dT%H:%M:%SZ; }

finish() {
    echo
    echo "結果: PASS ${PASS} / FAIL ${FAIL}"
    [ "$FAIL" -eq 0 ]
}
