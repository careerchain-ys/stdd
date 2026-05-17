#!/bin/bash
# PreToolUse Hook: git push 実行前にテスト・ビルドを実行
# いずれかが失敗した場合、push を中止する
# 変更がないアプリはスキップする

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
ROOT_DIR=$(git rev-parse --show-toplevel)

# リモートブランチとの差分を取得（push対象のコミット）
# upstream が設定されていない場合は origin/develop と比較
UPSTREAM=$(git rev-parse --abbrev-ref @{upstream} 2>/dev/null || echo "origin/develop")
CHANGED_FILES=$(git diff --name-only "$UPSTREAM"...HEAD 2>/dev/null || git diff --name-only origin/develop...HEAD 2>/dev/null || echo "")

# 各アプリに変更があるかチェック
USER_APP_CHANGED=0
ADMIN_APP_CHANGED=0

if echo "$CHANGED_FILES" | grep -qE "^user_app/"; then
    USER_APP_CHANGED=1
fi

if echo "$CHANGED_FILES" | grep -qE "^admin_app/"; then
    ADMIN_APP_CHANGED=1
fi

# 両方とも変更がない場合はスキップ
if [ $USER_APP_CHANGED -eq 0 ] && [ $ADMIN_APP_CHANGED -eq 0 ]; then
    echo "=========================================="
    echo "Pre-push check: user_app/admin_app に変更がないためスキップします"
    echo "=========================================="
    exit 0
fi

echo "=========================================="
echo "Pre-push check: テストとビルドを実行中..."
echo "=========================================="

# 失敗フラグ
FAILED=0
STEP=1
TOTAL_STEPS=$((USER_APP_CHANGED * 2 + ADMIN_APP_CHANGED * 2))

# user_app のテスト
if [ $USER_APP_CHANGED -eq 1 ]; then
    echo ""
    echo "[$STEP/$TOTAL_STEPS] user_app: テスト実行中..."
    if (cd "$ROOT_DIR/user_app" && npm test --no-cache -- --watchAll=false 2>&1); then
        echo "✓ user_app: テスト成功"
    else
        echo "✗ user_app: テスト失敗"
        FAILED=1
    fi
    STEP=$((STEP + 1))

    # user_app のビルド
    if [ $FAILED -eq 0 ]; then
        echo ""
        echo "[$STEP/$TOTAL_STEPS] user_app: ビルド実行中..."
        if (cd "$ROOT_DIR/user_app" && npm run build 2>&1); then
            echo "✓ user_app: ビルド成功"
        else
            echo "✗ user_app: ビルド失敗"
            FAILED=1
        fi
        STEP=$((STEP + 1))
    fi
else
    echo ""
    echo "⏭ user_app: 変更がないためスキップ"
fi

# admin_app のテスト
if [ $ADMIN_APP_CHANGED -eq 1 ] && [ $FAILED -eq 0 ]; then
    echo ""
    echo "[$STEP/$TOTAL_STEPS] admin_app: テスト実行中..."
    if (cd "$ROOT_DIR/admin_app" && npm test --no-cache -- --watchAll=false 2>&1); then
        echo "✓ admin_app: テスト成功"
    else
        echo "✗ admin_app: テスト失敗"
        FAILED=1
    fi
    STEP=$((STEP + 1))

    # admin_app のビルド
    if [ $FAILED -eq 0 ]; then
        echo ""
        echo "[$STEP/$TOTAL_STEPS] admin_app: ビルド実行中..."
        if (cd "$ROOT_DIR/admin_app" && npm run build 2>&1); then
            echo "✓ admin_app: ビルド成功"
        else
            echo "✗ admin_app: ビルド失敗"
            FAILED=1
        fi
    fi
elif [ $ADMIN_APP_CHANGED -eq 0 ]; then
    echo ""
    echo "⏭ admin_app: 変更がないためスキップ"
fi

echo ""
echo "=========================================="
if [ $FAILED -eq 1 ]; then
    echo "✗ テストまたはビルドが失敗しました。push を中止します。"
    echo "=========================================="
    exit 2
else
    echo "✓ すべてのテスト・ビルドが成功しました。push を続行します。"
    echo "=========================================="
    exit 0
fi
