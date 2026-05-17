#!/bin/bash
# PostToolUse Hook: ファイル編集後の自動フォーマット

hook_input=$(cat)
file_path=$(echo "$hook_input" | jq -r '.tool_input.file_path // empty')

if [ -z "$file_path" ]; then
  exit 0
fi

# ファイル拡張子を取得
extension="${file_path##*.}"

# プロジェクトルートを取得
project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# TypeScript/JavaScript/JSON/CSS/MDファイルの場合はPrettierでフォーマット
case "$extension" in
  ts|tsx|js|jsx|json|css|scss|md)
    if [ -f "$project_dir/node_modules/.bin/prettier" ]; then
      cd "$project_dir"
      npx prettier --write "$file_path" 2>/dev/null
      echo "Prettierでフォーマットしました: $file_path"
    fi
    ;;
esac

exit 0
