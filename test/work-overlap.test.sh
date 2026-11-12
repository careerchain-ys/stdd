#!/bin/bash
# 並行作業の重なりの検出（hooks/work-overlap.sh）の振る舞いテスト。
#   bash test/work-overlap.test.sh
# このディレクトリ（test/）は配布対象外。

set -u
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$REPO_ROOT/packages/core/hooks/work-overlap.sh"
. "$REPO_ROOT/test/lib/common.sh"

wo() { OUT=$(cd "$REPO_DIR" && bash "$SCRIPT" "$@" 2>&1); RC=$?; }

# main に docs/a.md と src/app.ts を置き、origin/main を main に合わせ、
# ほかの作業ツリー（ブランチ claude/other）を $OTHER に作る
setup() {
    new_case "$1"
    write_config ""
    (
        cd "$REPO_DIR" || exit 1
        git checkout -q main
        mkdir -p docs src
        echo a > docs/a.md; echo ab > docs/ab.md; echo app > src/app.ts
        git add -A && git commit -q -m base
        git update-ref refs/remotes/origin/main main
        git checkout -q claude/test
        git merge -q --ff-only main
    )
    OTHER="$TMP_ROOT/$1/other"
    git -C "$REPO_DIR" worktree add -q -b claude/other "$OTHER" main
    echo "[]" > "$FAKE_GH/pr-list-open.json"
}

echo "== 重なりなし"
setup none
wo --path docs/new.md
assert_rc "重なりが無ければ 0" 0
assert_contains "対象と確認した範囲を要約する" "対象 1 件、ほかの作業ツリー 1 本、作成中の PR 0 本。重なり 0 件（基点 origin/main）"

echo "== ほかの作業ツリーのコミット済みの変更"
setup committed
( cd "$OTHER" && echo changed > docs/a.md && git commit -q -am other )
wo --path docs/a.md
assert_rc "重なりがあれば 2" 2
assert_contains "相手の作業ツリーとブランチを示す" "docs/a.md  ← 作業ツリー"
assert_contains "相手のブランチ名を示す" "ブランチ claude/other"
wo --path docs
assert_rc "ディレクトリを指定すると配下のファイルと重なる" 2
assert_contains "ディレクトリと相手のファイルを並べて示す" "docs（相手は docs/a.md）"
wo --path docs/a
assert_rc "接頭辞だけが同じ兄弟のパスとは重ならない" 0

echo "== ほかの作業ツリーの未コミットの変更"
setup uncommitted
( cd "$OTHER" && echo new > src/new.ts && echo edit > src/app.ts )
wo --path src/new.ts
assert_rc "未追跡のファイルも重なりとして拾う" 2
wo --path src/app.ts
assert_rc "未コミットの編集も重なりとして拾う" 2
( cd "$OTHER" && git checkout -q -- src/app.ts && git mv docs/ab.md docs/renamed.md )
wo --path docs/ab.md
assert_rc "改名は元のパスでも重なる" 2
wo --path docs/renamed.md
assert_rc "改名は新しいパスでも重なる" 2
before=$(cd "$OTHER" && git status --porcelain)
[ "$before" = "$(cd "$OTHER" && git status --porcelain)" ] && ok "相手の作業ツリーの状態を変えない" || ng "相手の作業ツリーの状態を変えない"

echo "== 対象の既定はいまの作業ツリーの変更"
setup own
( cd "$OTHER" && echo changed > docs/a.md && git commit -q -am other )
( cd "$REPO_DIR" && echo mine > docs/a.md )
wo
assert_rc "--path が無ければ自分の未コミットの変更を対象にする" 2
assert_contains "自分の変更の件数を数える" "対象 1 件"
( cd "$REPO_DIR" && git checkout -q -- docs/a.md )
wo
assert_rc "対象が 0 件なら成功にしない" 1
assert_contains "--path を案内する" "--path で触る予定のファイルを指定する"

echo "== 作成中の PR"
setup pr
cat > "$FAKE_GH/pr-list-open.json" <<'JSON'
[
  {"number": 7, "headRefName": "feature/x", "files": [{"path": "src/app.ts"}]},
  {"number": 8, "headRefName": "claude/test", "files": [{"path": "docs/a.md"}]}
]
JSON
wo --path src/app.ts
assert_rc "open な PR の変更ファイルと重なれば 2" 2
assert_contains "PR の番号とブランチを示す" "src/app.ts  ← PR #7（ブランチ feature/x）"
wo --path docs/a.md
assert_rc "いまのブランチの PR は相手に数えない" 0
assert_contains "PR の本数を数える" "作成中の PR 2 本"
jq -n '[range(0; 200) | {number: ., headRefName: "b\(.)", files: []}]' > "$FAKE_GH/pr-list-open.json"
wo --path docs/new.md
assert_rc "PR が上限の本数に達したら打ち切りを疑って 1" 1
FAKE_GH_FAIL="pr list" wo --path docs/new.md
assert_rc "gh が失敗したら重なりなしとは言わない" 1
OUT=$(cd "$REPO_DIR" && PATH="/usr/bin:/bin" bash "$SCRIPT" --path docs/new.md 2>&1); RC=$?
assert_rc "gh が無ければ 1" 1
assert_contains "--no-pr を案内する" "--no-pr"
OUT=$(cd "$REPO_DIR" && PATH="/usr/bin:/bin" bash "$SCRIPT" --path docs/new.md --no-pr 2>&1); RC=$?
assert_rc "--no-pr なら gh が無くても進む" 0
assert_contains "PR を確かめていないことを示す" "作成中の PR は未確認"

echo "== 引数と基点"
setup args
wo --path ../outside.md
assert_rc "リポジトリの外を指せば 1" 1
wo --path .
assert_rc "リポジトリ全体を指せば 1" 1
wo --path
assert_rc "--path に値が無ければ 1" 1
wo --bogus
assert_rc "未知の引数は 1" 1
wo --path docs/a.md --base origin/nope
assert_rc "基点が無ければ 1" 1
assert_contains "fetch か --base を案内する" "git fetch するか --base で指定する"
OUT=$(cd "$REPO_DIR/docs" && bash "$SCRIPT" --path a.md --no-pr 2>&1); RC=$?
assert_contains "サブディレクトリからの相対パスをリポジトリ相対に直す" "対象 1 件"
write_config ""
sed -i.bak 's/primary_branch: "main"/primary_branch: "develop"/' "$REPO_DIR/.stdd.config.yml"
git -C "$REPO_DIR" update-ref refs/remotes/origin/develop main
wo --path docs/a.md --no-pr
assert_contains "基点は project.primary_branch から決める" "基点 origin/develop"
rm "$REPO_DIR/.stdd.config.yml" "$REPO_DIR/.stdd.config.yml.bak"
wo --path docs/a.md --no-pr
assert_rc "設定が無くても動く" 0
assert_contains "設定が無ければ main とみなすと知らせる" "主ブランチを main とみなします"

finish
