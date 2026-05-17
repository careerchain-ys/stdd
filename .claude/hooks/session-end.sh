#!/bin/bash
# Stop Hook: セッション終了時にセッション要約を保存

project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
log_dir="$project_dir/.claude/session-logs"

mkdir -p "$log_dir"

timestamp=$(date +"%Y-%m-%dT%H:%M:%S")
log_file="$log_dir/$(date +"%Y-%m-%d_%H%M%S").json"

# Git情報を収集（git -C でディレクトリ移動を回避）
git_branch=$(git -C "$project_dir" branch --show-current 2>/dev/null || echo "unknown")
uncommitted=$(git -C "$project_dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
recent_commits_json=$(git -C "$project_dir" log --oneline -5 2>/dev/null | jq -Rs .)

# jqで安全にJSONを生成
jq -n \
  --arg timestamp "$timestamp" \
  --arg branch "$git_branch" \
  --argjson uncommitted "$uncommitted" \
  --argjson commits "${recent_commits_json:-\"\"}" \
  '{timestamp: $timestamp, git_branch: $branch, uncommitted_changes: $uncommitted, recent_commits: $commits}' \
  > "$log_file"

# 古いログを削除（30日以上前）
find "$log_dir" -name "*.json" -mtime +30 -delete 2>/dev/null

exit 0
