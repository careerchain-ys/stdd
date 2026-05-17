#!/bin/bash
# SessionStart Hook: セッション開始時の初期化

project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Git情報を収集
git_branch=$(cd "$project_dir" && git branch --show-current 2>/dev/null || echo "unknown")
git_status=$(cd "$project_dir" && git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

# プロジェクト情報を収集
has_user_app=false
has_admin_app=false

[ -d "$project_dir/user_app" ] && has_user_app=true
[ -d "$project_dir/admin_app" ] && has_admin_app=true

# JSON形式で追加コンテキストを出力
cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "## Session Context\n\n- **Current Branch**: $git_branch\n- **Uncommitted Changes**: $git_status files\n- **User App Available**: $has_user_app\n- **Admin App Available**: $has_admin_app\n\n開発を始める前にCLAUDE.mdを確認してください。"
  }
}
EOF

exit 0
