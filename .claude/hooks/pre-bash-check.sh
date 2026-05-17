#!/bin/bash
# PreToolUse Hook: Bashコマンド実行前のセキュリティチェック

hook_input=$(cat)
command=$(echo "$hook_input" | jq -r '.tool_input.command // empty')

# 変数代入で始まるコマンドをブロック（allowパターンにマッチしなくなるため）
# 許可: PGPASSWORD=postgres psql ... （settings.jsonで明示的に許可済み）
ALLOWED_VAR_PREFIXES="PGPASSWORD="

first_token=$(echo "$command" | awk '{print $1}')
if echo "$first_token" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*='; then
  is_allowed=false
  for prefix in $ALLOWED_VAR_PREFIXES; do
    if echo "$first_token" | grep -qF "$prefix"; then
      is_allowed=true
      break
    fi
  done

  if [ "$is_allowed" = false ]; then
    echo "変数代入で始まるコマンドは許可されていません: $first_token" >&2
    echo "変数はコマンド内部（bash -c \"...\" 内）で使用してください。" >&2
    echo "例: devcontainer exec ... bash -c \"VAR=value; command\"" >&2
    exit 2
  fi
fi

# 複合コマンド（&& や ;）をブロック
# 承認プロンプト回避 + パーミッションマッチ確実化のため、コマンドは常に個別実行する
# クォート内の && や ; は許可（bash -c "cmd1 && cmd2" 等）
stripped_command=$(echo "$command" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")
if echo "$stripped_command" | grep -qE '&&|;'; then
  echo "複合コマンド（&& や ;）は使用しないでください。" >&2
  echo "コマンドは個別のBashツールコールとして実行してください。" >&2
  echo "cd が必要な場合は git -C 等の代替手段を使用してください。" >&2
  exit 2
fi

# 危険なコマンドパターンのチェック
dangerous_patterns=(
  "rm -rf /"
  "rm -rf /*"
  "rm -rf ~"
  "> /dev/sda"
  "mkfs"
  "dd if=/dev/zero"
  ":(){:|:&};:"
  "chmod -R 777 /"
  "git push.*--force.*main"
  "git push.*--force.*master"
  "DROP DATABASE"
  "DROP TABLE"
  "TRUNCATE"
)

for pattern in "${dangerous_patterns[@]}"; do
  if echo "$command" | grep -qE "$pattern"; then
    echo "危険なコマンドが検出されました: $pattern" >&2
    echo "このコマンドは実行できません。" >&2
    exit 2
  fi
done

# 機密ファイルへのアクセスチェック
sensitive_files=(
  ".env"
  ".env.local"
  ".env.production"
  "credentials"
  "secrets"
  "private_key"
)

for file in "${sensitive_files[@]}"; do
  if echo "$command" | grep -qE "cat.*$file|head.*$file|tail.*$file|less.*$file|more.*$file"; then
    echo "機密ファイルへの直接アクセスが検出されました: $file" >&2
    echo "Readツールを使用してください。" >&2
    exit 2
  fi
done

exit 0
