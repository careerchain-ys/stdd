#!/bin/bash
# PostToolUse Hook: .ts/.tsx ファイル編集後に自動で型チェックを実行

hook_input=$(cat)
file_path=$(echo "$hook_input" | jq -r '.tool_input.file_path // empty')

if [ -z "$file_path" ]; then
  exit 0
fi

extension="${file_path##*.}"

# TypeScript ファイルのみ対象
case "$extension" in
  ts|tsx)
    ;;
  *)
    exit 0
    ;;
esac

project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# 型チェックを実行する関数
run_typecheck() {
  local check_dir="$1"
  if [ ! -f "$check_dir/tsconfig.json" ]; then
    return
  fi

  cd "$check_dir"
  output=$(npx tsc --noEmit 2>&1)
  exit_code=$?

  if [ $exit_code -ne 0 ]; then
    error_count=$(echo "$output" | grep -c "error TS")
    echo "TypeCheck: ${error_count}件の型エラーを検出しました（${check_dir##*/}）"
    echo "$output" | grep "error TS" | head -10
    if [ "$error_count" -gt 10 ]; then
      echo "... 他 $((error_count - 10)) 件"
    fi
  fi
}

# ファイルがどのアプリに属するか判定
case "$file_path" in
  */user_app/*)
    run_typecheck "$project_dir/user_app"
    ;;
  */admin_app/*)
    run_typecheck "$project_dir/admin_app"
    ;;
  */packages/*)
    # packages変更時は両アプリをチェック
    run_typecheck "$project_dir/user_app"
    run_typecheck "$project_dir/admin_app"
    ;;
  *)
    exit 0
    ;;
esac

exit 0
