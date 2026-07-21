#!/bin/bash
# PreToolUse Hook: 実装ファイルの編集前に STDD の「Spec → テスト → 実装」順序を促す。
# 登録: Claude は Edit / Write / MultiEdit（settings.json）、Codex は apply_patch|Edit|Write（.codex/hooks.json）。
#
# 役割（Poka-Yoke）:
#   ad-hoc な「この実装を直して」等の指示でスキルを介さず実装ファイルを編集しようと
#   したとき、まず Spec / テストの更新を検討するようリマインドする。既定は非ブロッキング。
#
# このフックは下流プロジェクト固有の値をハードコードせず、リポジトリルートの
# .stdd.config.yml を実行時に読み取って動作する（設定駆動）。
#   - apps[].path                  : 実装ファイルとみなすディレクトリ（"." はリポジトリ全体）
#   - docs.layout.requirements     : Spec の配置（{{ より前の固定 prefix を Spec 領域とみなす）
#   - workflow.enforce_spec_first  : off | warn(既定) | block
#   - project.primary_branch       : block 判定でブランチ差分を比較する基準
#
# 入力（PreToolUse stdin JSON）:
#   - Claude: tool_input.file_path（単一ファイル）
#   - Codex : apply_patch は file_path を持たず tool_input.command にパッチ本文を載せる。
#             パッチの "*** (Add|Update|Delete) File: <path>" から編集対象を抽出する（複数可）。
# 出力（stdout JSON）は Claude / Codex 共通（hookSpecificOutput.permissionDecision / additionalContext）。
#
# 分類で Spec / テスト / docs / .claude / 設定・ロックファイルは免除（無言で許可）する。
# 設定が無い / フックが失敗する場合はブロックせずスキップする（フェイルオープン）。
# 詳細な記述規約は docs/config-driven-authoring.md を参照。

hook_input=$(cat)

# 編集対象ファイルを取得する（Claude=file_path / Codex=apply_patch のパッチ本文）。
FILE_PATH=$(printf '%s' "$hook_input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
if [ -n "$FILE_PATH" ]; then
    FILES_RAW="$FILE_PATH"
else
    CMD=$(printf '%s' "$hook_input" | jq -r '.tool_input.command // empty' 2>/dev/null)
    FILES_RAW=$(printf '%s\n' "$CMD" | sed -n -E 's/^\*\*\* (Add|Update|Delete) File: (.+)$/\2/p')
fi
[ -z "$FILES_RAW" ] && exit 0

ROOT_DIR=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
CONFIG="$ROOT_DIR/.stdd.config.yml"
[ -f "$CONFIG" ] || exit 0

# 1 パスをリポジトリルート相対へ正規化
normalize_rel() {
    case "$1" in
        "$ROOT_DIR"/*) printf '%s' "${1#"$ROOT_DIR"/}" ;;
        ./*)           printf '%s' "${1#./}" ;;
        *)             printf '%s' "$1" ;;
    esac
}

# --- .stdd.config.yml パーサ（外部依存なし。pre-push-check.sh と同じ流儀） ---

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

# docs.layout.requirements の値（ネストキー。最初の requirements: 行を採用）
yaml_requirements() {
    awk '$1 == "requirements:" {
        sub(/^[[:space:]]*requirements:[[:space:]]*/, "", $0)
        print $0
        exit
    }' "$CONFIG"
}

strip_quotes() {
    local v="$1"
    v="${v%\"}"; v="${v#\"}"
    v="${v%\'}"; v="${v#\'}"
    printf '%s' "$v"
}

# docs.layout.requirements の {{ より前の固定 prefix を Spec 領域として導出
REQ_TPL=$(strip_quotes "$(yaml_requirements)")
SPEC_PREFIX="${REQ_TPL%%\{\{*}"

# --- パス分類 ---

is_spec() {
    local rel="$1" base
    base=$(basename "$rel")
    case "$base" in
        REQUIREMENTS.md|TECH_DESIGN.md|TEST_PLAN.md|ARCHITECTURE.md|TABLE_DEFINITION.md|API_SPEC.md|DESIGN.md) return 0 ;;
    esac
    case "$rel" in
        docs/*|*/docs/*) return 0 ;;
    esac
    if [ -n "$SPEC_PREFIX" ] && [ "$SPEC_PREFIX" != "$REQ_TPL" ]; then
        case "$rel" in
            "$SPEC_PREFIX"*) return 0 ;;
        esac
    fi
    return 1
}

is_test() {
    local rel="$1" base
    base=$(basename "$rel")
    case "$base" in
        *.test.*|*.spec.*|*_test.*|*_spec.*) return 0 ;;
    esac
    case "/$rel/" in
        */__tests__/*|*/__mocks__/*|*/tests/*|*/test/*|*/e2e/*|*/spec/*) return 0 ;;
    esac
    return 1
}

is_excluded() {
    local rel="$1" base
    base=$(basename "$rel")
    case "$rel" in
        .claude/*|*/.claude/*|.git/*|*/.git/*|node_modules/*|*/node_modules/*) return 0 ;;
        dist/*|*/dist/*|build/*|*/build/*|coverage/*|*/coverage/*|.next/*|*/.next/*) return 0 ;;
    esac
    case "$base" in
        .env*|*.lock) return 0 ;;
        *.md|*.txt|*.json|*.yml|*.yaml|*.toml|*.ini) return 0 ;;
        *.css|*.scss|*.sass|*.less|*.svg|*.png|*.jpg|*.jpeg|*.gif|*.ico|*.webp) return 0 ;;
    esac
    return 1
}

APPS_PATHS=$(yaml_apps_paths)
[ -z "$APPS_PATHS" ] && APPS_PATHS="."

in_apps() {
    local rel="$1" p
    while IFS= read -r raw; do
        [ -z "$raw" ] && continue
        p=$(strip_quotes "$raw")
        [ -z "$p" ] && continue
        [ "$p" = "." ] && return 0
        p="${p%/}"
        case "$rel" in
            "$p"/*) return 0 ;;
        esac
    done <<EOF
$APPS_PATHS
EOF
    return 1
}

# 編集対象のうち「apps 配下の実装ファイル（Spec/テスト/除外でない）」を 1 つ探す。
# 該当が無ければ（Spec/テスト/除外/apps 外のみ）無言で許可する。
REL=""
while IFS= read -r cand; do
    [ -z "$cand" ] && continue
    rel=$(normalize_rel "$cand")
    is_spec "$rel" && continue
    is_test "$rel" && continue
    is_excluded "$rel" && continue
    in_apps "$rel" || continue
    REL="$rel"
    break
done <<EOF
$FILES_RAW
EOF
[ -z "$REL" ] && exit 0

# --- 実装ファイル編集と判定。enforce_spec_first に従う ---

MODE=$(strip_quotes "$(yaml_scalar workflow enforce_spec_first)")
MODE=${MODE:-warn}

[ "$MODE" = "off" ] && exit 0

REMINDER="STDD リマインダ: 実装ファイル ($REL) を編集しようとしています。\
この変更が仕様の振る舞いを変えるなら、いきなり実装を直さず、先に Spec\
（.stdd.config.yml の docs.layout）とテストを更新してください（Spec → テスト → 実装）。\
振る舞いを変えないリファクタ・整形・設定変更ならこのまま進めて構いません。\
本格的な機能実装は auto-implement、仕様更新は documenting-requirements（要件）／ documenting-tech-specs（技術設計）スキルに委譲できます。"

if [ "$MODE" = "block" ]; then
    PRIMARY_BRANCH=$(strip_quotes "$(yaml_scalar project primary_branch)")
    PRIMARY_BRANCH=${PRIMARY_BRANCH:-main}

    branch_has_spec_or_test() {
        local base files f
        base=$(git merge-base HEAD "origin/$PRIMARY_BRANCH" 2>/dev/null || true)
        files=""
        [ -n "$base" ] && files=$(git diff --name-only "$base"...HEAD 2>/dev/null)
        files="$files
$(git diff --name-only 2>/dev/null)
$(git diff --name-only --cached 2>/dev/null)"
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            if is_spec "$f" || is_test "$f"; then return 0; fi
        done <<EOF
$files
EOF
        return 1
    }

    # ブランチに既に Spec / テストの変更があれば spec-first 充足とみなして許可
    if branch_has_spec_or_test; then
        exit 0
    fi

    DENY="STDD enforce_spec_first=block: このブランチにはまだ Spec / テストの変更がありません。\
$REMINDER"
    jq -n --arg r "$DENY" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 0
fi

# warn（既定）: 非ブロッキングのリマインドを文脈に注入
jq -n --arg r "$REMINDER" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$r}}'
exit 0
