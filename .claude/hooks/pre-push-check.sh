#!/bin/bash
# PreToolUse Hook: git push 実行前にテスト・ビルドを実行
# いずれかが失敗した場合、push を中止する。
#
# このフックは下流プロジェクト固有の値をハードコードせず、リポジトリルートの
# .stdd.config.yml を実行時に読み取って動作する（設定駆動）。
#   - apps[].path            : 検査対象アプリのディレクトリ
#   - commands.test          : 各アプリで実行するテストコマンド（必須）
#   - commands.build         : 各アプリで実行するビルドコマンド（任意）
#   - project.primary_branch : upstream 未設定時の比較先ブランチ
#
# 設定が無い / 必須キーが欠ける場合は push をブロックせずスキップする。
# 詳細な記述規約は docs/config-driven-authoring.md を参照。

hook_input=$(cat)
command=$(echo "$hook_input" | jq -r '.tool_input.command // empty')

# git push コマンドかどうかを判定
if ! echo "$command" | grep -qE "git push"; then
    exit 0
fi

# --no-verify オプションが付いている場合はスキップ
if echo "$command" | grep -qE "\-\-no-verify"; then
    exit 0
fi

# プロジェクトルートディレクトリを取得
ROOT_DIR=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
CONFIG="$ROOT_DIR/.stdd.config.yml"

if [ ! -f "$CONFIG" ]; then
    echo "Pre-push check: .stdd.config.yml が見つからないためスキップします"
    exit 0
fi

# --- .stdd.config.yml パーサ（外部依存なし） ---

# 指定セクション直下のスカラー値を取得: $1=section, $2=key
yaml_scalar() {
    awk -v sec="$1:" -v k="$2:" '
        /^[^[:space:]]/ { insec = ($1 == sec) }
        insec && $1 == k {
            sub(/^[[:space:]]*[^:]*:[[:space:]]*/, "", $0)
            print $0
            exit
        }
    ' "$CONFIG"
}

# apps[] の path を 1 行ずつ取得
yaml_apps_paths() {
    awk '
        /^[^[:space:]]/ { inapps = ($1 == "apps:") }
        inapps && $1 == "path:" {
            sub(/^[[:space:]]*path:[[:space:]]*/, "", $0)
            print $0
        }
    ' "$CONFIG"
}

# 前後のクォートを除去
strip_quotes() {
    local v="$1"
    v="${v%\"}"; v="${v#\"}"
    v="${v%\'}"; v="${v#\'}"
    printf '%s' "$v"
}

PRIMARY_BRANCH=$(strip_quotes "$(yaml_scalar project primary_branch)")
PRIMARY_BRANCH=${PRIMARY_BRANCH:-main}
TEST_CMD=$(strip_quotes "$(yaml_scalar commands test)")
BUILD_CMD=$(strip_quotes "$(yaml_scalar commands build)")

if [ -z "$TEST_CMD" ]; then
    echo "Pre-push check: commands.test が未定義のためスキップします"
    exit 0
fi

# リモートブランチとの差分を取得（push対象のコミット）
# upstream 未設定時は origin/<primary_branch> と比較
UPSTREAM=$(git rev-parse --abbrev-ref @{upstream} 2>/dev/null || echo "origin/$PRIMARY_BRANCH")
CHANGED_FILES=$(git diff --name-only "$UPSTREAM"...HEAD 2>/dev/null \
    || git diff --name-only "origin/$PRIMARY_BRANCH"...HEAD 2>/dev/null \
    || echo "")

# 検査対象アプリ（apps[].path）を取得。未定義ならリポジトリルートを単一アプリ扱い
APPS_PATHS=$(yaml_apps_paths)
if [ -z "$APPS_PATHS" ]; then
    APPS_PATHS="."
fi

echo "=========================================="
echo "Pre-push check: 変更のあったアプリを検査します"
echo "=========================================="

FAILED=0
ANY=0

while IFS= read -r raw_path; do
    [ -z "$raw_path" ] && continue
    appdir=$(strip_quotes "$raw_path")
    [ -z "$appdir" ] && continue

    # 変更があったか判定
    if [ "$appdir" = "." ]; then
        # ルートを単一アプリとする構成: 何らかの変更があれば対象
        if [ -n "$CHANGED_FILES" ]; then changed=1; else changed=0; fi
    else
        if echo "$CHANGED_FILES" | grep -qE "^${appdir%/}/"; then changed=1; else changed=0; fi
    fi

    if [ "$changed" -eq 0 ]; then
        echo "⏭ $appdir: 変更がないためスキップ"
        continue
    fi

    ANY=1
    echo ""
    echo "▶ $appdir: テスト実行中... ($TEST_CMD)"
    if ( cd "$ROOT_DIR/$appdir" && eval "$TEST_CMD" 2>&1 ); then
        echo "✓ $appdir: テスト成功"
    else
        echo "✗ $appdir: テスト失敗"
        FAILED=1
        break
    fi

    if [ -n "$BUILD_CMD" ]; then
        echo ""
        echo "▶ $appdir: ビルド実行中... ($BUILD_CMD)"
        if ( cd "$ROOT_DIR/$appdir" && eval "$BUILD_CMD" 2>&1 ); then
            echo "✓ $appdir: ビルド成功"
        else
            echo "✗ $appdir: ビルド失敗"
            FAILED=1
            break
        fi
    fi
done <<EOF
$APPS_PATHS
EOF

echo ""
echo "=========================================="
if [ "$ANY" -eq 0 ]; then
    echo "Pre-push check: 対象アプリに変更がないためスキップします"
    echo "=========================================="
    exit 0
fi

if [ "$FAILED" -eq 1 ]; then
    echo "✗ テストまたはビルドが失敗しました。push を中止します。"
    echo "=========================================="
    exit 2
else
    echo "✓ すべてのテスト・ビルドが成功しました。push を続行します。"
    echo "=========================================="
    exit 0
fi
