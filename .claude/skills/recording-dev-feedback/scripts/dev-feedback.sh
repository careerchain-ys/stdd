#!/bin/bash
# dev-feedback.sh — 開発フィードバック（プロセス上の課題）の GitHub issue を扱う。
#
# 規約の正本は ../references/feedback-rules.md。このスクリプトは、規約のうち機械で確かめられる
# 部分（ラベル、上限、再発コメントの書式、昇格、見送りの条件）を実行する。何を起票するかの判断はしない。
#
# 使い方:
#   dev-feedback.sh [--root <dir>] [--repo <owner/name>] <command> [args]
#
#   setup                    ラベルを作成・更新する（冪等）
#   check                    前提（gh・認証・ラベル）を確かめる。不足があれば exit 1
#   file --title <t> --priority high|medium --category <k>[,<k>...] --body-file <f> [--target <path>]
#                            起票する。発生源・記録日の表を本文の先頭に付ける。上限に達していれば exit 2
#   recur <番号> --note <一言>
#                            再発コメントを追加する。必要なら reopen し、閾値に達したら priority:high へ上げる
#   triage --skipped <n>     棚卸しを終えたことと、上限で起票しなかった件数を記録する（テレメトリが読む）
#   audit                    open issue のラベル不整合・昇格候補・見送り候補を一覧する（読み取りのみ）
#   close-stale <番号>...    見送りの条件を取り直して確かめ、満たすものを not planned で閉じる
#   promote <番号>...        priority:medium を priority:high に付け替える
#
# 設定は .stdd.config.yml の feedback（無ければ既定値）。feedback.enabled が false なら何もせず exit 0。
# 依存: bash 3.2 以上、git、gh（gh の --jq を使う。jq 単体は不要）。
#
# 工程テレメトリとの連携: file / recur / triage は、作業ツリーの外（git の共通ディレクトリ配下の
# stdd-telemetry/<ブランチ>.tsv）に記録を追記する。create-pr の pr-telemetry.sh がこれを読む。

set -u

ROOT=""
REPO=""
CMD=""
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --root) ROOT="${2:-}"; shift 2 ;;
        --repo) REPO="${2:-}"; shift 2 ;;
        --help|-h) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)
            if [ -z "$CMD" ]; then CMD="$1"; else ARGS+=("$1"); fi
            shift ;;
    esac
done

die()  { echo "dev-feedback: $*" >&2; exit 1; }
warn() { echo "dev-feedback: $*" >&2; }

[ -n "$CMD" ] || die "コマンドを指定してください（--help で一覧）"
case "$REPO" in --*) die "--repo には owner/name を渡してください: $REPO" ;; esac
# gh は GH_REPO を全サブコマンド（gh api の {owner}/{repo} を含む）で解決に使う
[ -n "$REPO" ] && export GH_REPO="$REPO"

if [ -z "$ROOT" ]; then
    ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
CONFIG="$ROOT/.stdd.config.yml"

# ---------------------------------------------------------------------------
# .stdd.config.yml の feedback ブロック（外部依存なしのパーサ）
# ---------------------------------------------------------------------------
config_block() {
    [ -f "$CONFIG" ] || return 0
    awk -v blk="$1:" '
        /^[^[:space:]#]/ { inblk = ($1 == blk) ; next }
        inblk { print }
    ' "$CONFIG"
}
FB_BLOCK="$(config_block feedback)"

# ブロック内の leaf キーの値。引用符を外し、引用符で囲まれていない値の行末コメントを除く。
cfg() {
    local v
    v=$(printf '%s\n' "$FB_BLOCK" | awk -v k="$1:" '
        $1 == k { sub(/^[[:space:]]*[^:]*:[[:space:]]*/, ""); print; exit }
    ')
    case "$v" in
        \"*) v="${v#\"}"; v="${v%%\"*}" ;;
        \'*) v="${v#\'}"; v="${v%%\'*}" ;;
        *)   v=$(printf '%s' "$v" | sed 's/[[:space:]]#.*$//; s/[[:space:]]*$//') ;;
    esac
    printf '%s' "${v:-$2}"
}

ENABLED=$(cfg enabled true)
L_BASE=$(cfg base dev-feedback)
L_HIGH=$(cfg priority_high "priority:high")
L_MED=$(cfg priority_medium "priority:medium")
L_CAT=$(cfg category_prefix "category:")
MAX_PER_PR=$(cfg max_issues_per_pr 5)
STALE_DAYS=$(cfg stale_days 14)
RECUR_HIGH=$(cfg recurrence_to_high 2)

CATEGORY_KEYS="spec-format skill agent automation flow coding-rules other"
TRUSTED='"OWNER","MEMBER","COLLABORATOR"'
RECUR_PREFIX="再発 —"
STALE_PREFIX="見送り —"
SEP=$(printf '\037')
# 行内の区切り。タブは空白として扱われ、空の欄が詰められてしまうので使わない
FS1=$(printf '\036')

if [ ! -f "$CONFIG" ]; then
    warn ".stdd.config.yml が見つからないため既定値で動きます（$ROOT）"
fi
if [ "$ENABLED" = "false" ]; then
    echo "dev-feedback: feedback.enabled が false のため何もしません"
    exit 0
fi

now_epoch() { printf '%s' "${STDD_NOW:-$(date +%s)}"; }
today() { date -u +%F; }
current_branch() { git -C "$ROOT" branch --show-current 2>/dev/null; }

require_gh() {
    command -v gh >/dev/null 2>&1 || die "gh コマンドがありません（https://cli.github.com/）"
}

# ---------------------------------------------------------------------------
# 工程テレメトリの記録（pr-telemetry.sh と同じ置き場・同じ形式）
#   <epoch>\t<kind>\t<arg>
# ---------------------------------------------------------------------------
events_file() {
    local common branch
    common=$(cd "$ROOT" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd) || return 1
    branch=$(current_branch)
    [ -n "$branch" ] || return 1
    mkdir -p "$common/stdd-telemetry" || return 1
    printf '%s/stdd-telemetry/%s.tsv' "$common" "$(printf '%s' "$branch" | sed 's|/|__|g')"
}
record_event() {
    local f
    f=$(events_file) || { warn "テレメトリの記録先を決められないため記録しません（git の作業ツリー外か detached HEAD）"; return 0; }
    printf '%s\t%s\t%s\n' "$(now_epoch)" "$1" "${2:-}" >> "$f"
}

# ---------------------------------------------------------------------------
# ラベル
# ---------------------------------------------------------------------------
category_desc() {
    case "$1" in
        spec-format)  echo "反映先: Spec のテンプレート・ドキュメント規約" ;;
        skill)        echo "反映先: skill の手順・コード例" ;;
        agent)        echo "反映先: agent の定義" ;;
        automation)   echo "反映先: フック・検査スクリプト・CI" ;;
        flow)         echo "反映先: 開発フロー" ;;
        coding-rules) echo "反映先: コーディング規約・共通の技術設計" ;;
        other)        echo "起票時に反映先が決まらないもの" ;;
    esac
}

# name<TAB>color<TAB>description
label_defs() {
    printf '%s\t%s\t%s\n' "$L_BASE" "5319e7" "開発フィードバック（プロセス上の課題）。open は未反映を表す"
    printf '%s\t%s\t%s\n' "$L_HIGH" "b60205" "次の作業単位に入る前に。後から直すコストが跳ね上がるもの"
    printf '%s\t%s\t%s\n' "$L_MED"  "fbca04" "機能が増える前に。損失が機能の数に比例して増えるもの"
    local k
    for k in $CATEGORY_KEYS; do
        printf '%s\t%s\t%s\n' "$L_CAT$k" "c5def5" "$(category_desc "$k")"
    done
}

existing_labels() {
    gh label list --limit 1000 --json name --jq '.[].name'
}

cmd_setup() {
    require_gh
    local existing name color desc created=0 updated=0
    existing=$(existing_labels) || die "ラベルの一覧を取得できません（gh auth status とリポジトリを確認してください）"
    if [ "$(printf '%s\n' "$existing" | grep -c .)" -ge 1000 ]; then
        die "ラベルが 1000 件以上あり一覧が切り詰められた可能性があります"
    fi
    # stdin はヒアドキュメントなので、ループ内の gh には </dev/null を渡す
    while IFS="$(printf '\t')" read -r name color desc; do
        [ -n "$name" ] || continue
        if printf '%s\n' "$existing" | grep -qxF "$name"; then
            gh label edit "$name" --color "$color" --description "$desc" >/dev/null </dev/null \
                || die "ラベルを更新できません: $name"
            updated=$((updated + 1)); echo "  updated  $name"
        else
            gh label create "$name" --color "$color" --description "$desc" >/dev/null </dev/null \
                || die "ラベルを作成できません: $name"
            created=$((created + 1)); echo "  created  $name"
        fi
    done <<EOF
$(label_defs)
EOF
    echo "dev-feedback setup OK: 新規 ${created} 件 / 更新 ${updated} 件"
}

cmd_check() {
    require_gh
    gh auth status >/dev/null 2>&1 || die "gh が認証されていません（gh auth login）"
    local existing missing="" name
    existing=$(existing_labels) || die "ラベルの一覧を取得できません（リポジトリへのアクセスを確認してください）"
    while IFS="$(printf '\t')" read -r name _; do
        [ -n "$name" ] || continue
        printf '%s\n' "$existing" | grep -qxF "$name" || missing="$missing $name"
    done <<EOF
$(label_defs)
EOF
    if [ -n "$missing" ]; then
        echo "dev-feedback check NG: ラベルがありません:$missing" >&2
        echo "  対処: bash $0 setup を実行してください" >&2
        exit 1
    fi
    echo "dev-feedback check OK（ラベル: $L_BASE / $L_HIGH / $L_MED / ${L_CAT}*、上限 ${MAX_PER_PR} 件/PR）"
}

# ---------------------------------------------------------------------------
# 起票
# ---------------------------------------------------------------------------

# このブランチから起票した issue の番号（GitHub 上の本文の発生源と、手元の記録の和集合）
filed_numbers() {
    local branch="$1" f
    {
        gh issue list --label "$L_BASE" --state all --limit 200 --search "\"$branch\" in:body" \
            --json number,body \
            --jq '.[] | [(.number|tostring), ((.body // "") | split("\n") | map(select(startswith("| 発生源"))) | (.[0] // ""))] | @tsv' \
            2>/dev/null | while IFS="$(printf '\t')" read -r num src; do
                case "$src" in *"\`$branch\`"*) echo "$num" ;; esac
            done
        f=$(events_file 2>/dev/null) && [ -f "$f" ] && awk -F'\t' '$2 == "feedback-filed" { print $3 }' "$f"
    } | grep -E '^[0-9]+$' | sort -u
}

cmd_file() {
    require_gh
    local title="" priority="" categories="" body_file="" target="未定"
    while [ $# -gt 0 ]; do
        case "$1" in
            --title) title="${2:-}"; shift 2 ;;
            --priority) priority="${2:-}"; shift 2 ;;
            --category) categories="${2:-}"; shift 2 ;;
            --body-file) body_file="${2:-}"; shift 2 ;;
            --target) target="${2:-}"; shift 2 ;;
            *) die "file: 知らない引数: $1" ;;
        esac
    done
    [ -n "$title" ] || die "file: --title が必要です"
    local plabel
    case "$priority" in
        high) plabel="$L_HIGH" ;;
        medium) plabel="$L_MED" ;;
        low) die "file: 優先度が低のものは起票しません（feedback-rules.md §3）。その場で直すか、何もしないでください" ;;
        *) die "file: --priority は high か medium です" ;;
    esac
    [ -n "$categories" ] || die "file: --category を 1 つ以上指定してください（$CATEGORY_KEYS）"
    local label_args=(--label "$L_BASE" --label "$plabel") k
    for k in $(printf '%s' "$categories" | tr ',' ' '); do
        case " $CATEGORY_KEYS " in
            *" $k "*) label_args+=(--label "$L_CAT$k") ;;
            *) die "file: 分類 '$k' は定義にありません（$CATEGORY_KEYS）" ;;
        esac
    done
    [ -f "$body_file" ] || die "file: --body-file が見つかりません: $body_file"
    local h
    for h in "## 現象" "## なぜ問題か" "## 提案"; do
        grep -qxF "$h" "$body_file" || die "file: 本文に見出し「$h」がありません（templates/issue-body.md の形で書いてください）"
    done

    local branch count pr src
    branch=$(current_branch)
    [ -n "$branch" ] || die "file: ブランチを特定できません（detached HEAD）"
    count=$(filed_numbers "$branch" | grep -c .)
    if [ "$count" -ge "$MAX_PER_PR" ]; then
        echo "dev-feedback file NG: このブランチ（$branch）からは既に ${count} 件起票しています（上限 ${MAX_PER_PR} 件）" >&2
        echo "  残りは起票せず、triage --skipped の件数に含めてください（feedback-rules.md §5）" >&2
        exit 2
    fi

    pr=$(gh pr view --json number --jq .number 2>/dev/null || true)
    src="ブランチ \`$branch\`"
    [ -n "$pr" ] && src="$src ／ PR #$pr"
    local tmp url num
    tmp=$(mktemp "${TMPDIR:-/tmp}/dev-feedback.XXXXXX")
    {
        echo "| 項目 | 内容 |"
        echo "| --- | --- |"
        echo "| 記録日 | $(today) |"
        echo "| 発生源 | $src |"
        echo "| 反映先候補 | $target |"
        echo
        cat "$body_file"
    } > "$tmp"
    url=$(gh issue create --title "$title" "${label_args[@]}" --body-file "$tmp") || { rm -f "$tmp"; die "file: issue を作成できません"; }
    rm -f "$tmp"
    num="${url##*/}"
    record_event feedback-filed "$num"
    echo "dev-feedback file OK: #$num $title（$((count + 1))/${MAX_PER_PR} 件目）"
    echo "$url"
}

# ---------------------------------------------------------------------------
# 再発
# ---------------------------------------------------------------------------

# issue の要約: state<TAB>stateReason<TAB>labels(SEP 区切り)<TAB>再発数<TAB>最後の見送りコメントの epoch
issue_summary() {
    gh issue view "$1" --json state,stateReason,labels,comments --jq "
        [ .state, (.stateReason // \"\"),
          ([.labels[].name] | join(\"$SEP\")),
          ([.comments[] | select(.authorAssociation | IN($TRUSTED)) | select(.body | startswith(\"$RECUR_PREFIX\"))] | length | tostring),
          ([.comments[] | select(.authorAssociation | IN($TRUSTED)) | select(.body | startswith(\"$STALE_PREFIX\")) | .createdAt | fromdateiso8601] | max // 0 | tostring)
        ] | join(\"\\u001e\")"
}

last_reopen_epoch() {
    gh api "repos/{owner}/{repo}/issues/$1/timeline" --paginate \
        --jq '.[] | select(.event == "reopened") | .created_at | fromdateiso8601' 2>/dev/null | sort -n | tail -1
}

has_label() { case "$SEP$1$SEP" in *"$SEP$2$SEP"*) return 0 ;; esac; return 1; }

# medium → high（付けてから外す。途中で失敗しても優先度が 0 個にならない順）
do_promote() {
    local n="$1"
    gh issue edit "$n" --add-label "$L_HIGH" >/dev/null || { warn "#$n: $L_HIGH を付けられません"; return 1; }
    gh issue edit "$n" --remove-label "$L_MED" >/dev/null || { warn "#$n: $L_MED を外せません（優先度が 2 つ付いています）"; return 1; }
    echo "  promoted #$n: $L_MED → $L_HIGH"
}

cmd_recur() {
    require_gh
    local n="" note=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --note) note="${2:-}"; shift 2 ;;
            *) [ -z "$n" ] && n="$1" || die "recur: 知らない引数: $1"; shift ;;
        esac
    done
    case "$n" in ''|*[!0-9]*) die "recur: issue 番号を指定してください" ;; esac
    [ -n "$note" ] || die "recur: --note に一言を書いてください"

    local s state reason labels recur stale_at
    s=$(issue_summary "$n") || die "recur: #$n を取得できません"
    IFS="$FS1" read -r state reason labels recur stale_at <<EOF
$s
EOF
    has_label "$labels" "$L_BASE" || die "recur: #$n には $L_BASE ラベルがありません"

    local branch pr src
    branch=$(current_branch)
    pr=$(gh pr view --json number --jq .number 2>/dev/null || true)
    src="${branch:-ブランチ不明}"
    [ -n "$pr" ] && src="$src ／ PR #$pr"
    printf '%s %s（%s）: %s\n' "$RECUR_PREFIX" "$(today)" "$src" "$note" | gh issue comment "$n" --body-file - >/dev/null \
        || die "recur: #$n にコメントできません"
    record_event feedback-recur "$n"
    echo "dev-feedback recur OK: #$n に再発コメントを追加しました"

    if [ "$state" = "CLOSED" ]; then
        local reopen=no why=""
        case "$reason" in
            COMPLETED) reopen=yes; why="反映済みとして閉じていたため（反映が足りなかった）" ;;
            NOT_PLANNED)
                local last_reopen
                last_reopen=$(last_reopen_epoch "$n"); last_reopen=${last_reopen:-0}
                if [ "${stale_at:-0}" -gt "$last_reopen" ]; then
                    reopen=yes; why="見送りで閉じていたため"
                else
                    why="人の判断で not planned にしたため reopen しません"
                fi ;;
            *) why="${reason:-理由不明} で閉じているため reopen しません" ;;
        esac
        if [ "$reopen" = yes ]; then
            gh issue reopen "$n" >/dev/null || die "recur: #$n を reopen できません"
            echo "  reopened #$n（$why）"
        else
            echo "  #$n: $why"
        fi
    fi

    # 投稿後に数え直す（自分のコメントが信頼できる投稿者として数えられるかは GitHub 側が決める）
    s=$(issue_summary "$n") || { warn "#$n を取り直せないため昇格の判定を省きます"; return 0; }
    IFS="$FS1" read -r state reason labels recur stale_at <<EOF
$s
EOF
    echo "  再発コメント: ${recur} 本（priority:high へ上げる閾値 ${RECUR_HIGH} 本）"
    if [ "$recur" -ge "$RECUR_HIGH" ] && has_label "$labels" "$L_MED" && ! has_label "$labels" "$L_HIGH"; then
        do_promote "$n"
    fi
}

cmd_triage() {
    local skipped=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --skipped) skipped="${2:-}"; shift 2 ;;
            *) die "triage: 知らない引数: $1" ;;
        esac
    done
    case "$skipped" in ''|*[!0-9]*) die "triage: --skipped に上限で起票しなかった件数を渡してください（0 件でも 0）" ;; esac
    record_event feedback-triage "$skipped"
    local f filed recurred
    f=$(events_file) || exit 0
    filed=$(awk -F'\t' '$2 == "feedback-filed" { printf " #%s", $3 }' "$f")
    recurred=$(awk -F'\t' '$2 == "feedback-recur" { printf " #%s", $3 }' "$f")
    echo "dev-feedback triage OK"
    echo "PR 本文の備考に書く行:"
    echo "開発フィードバック: 起票${filed:- なし} ／ 再発${recurred:- なし} ／ 上限で起票しなかったもの ${skipped} 件（反映は別 PR）"
}

# ---------------------------------------------------------------------------
# 監査・見送り・昇格
# ---------------------------------------------------------------------------

# 見送りしてはいけない理由（参照元・担当者）。空なら見送ってよい。
stale_blocker() {
    local n="$1" assignees="$2" refs
    [ "$assignees" -gt 0 ] && { echo "assignee が付いている"; return; }
    refs=$(gh api "repos/{owner}/{repo}/issues/$n/timeline" --paginate \
        --jq '.[] | select(.event == "cross-referenced") | select(.source.issue.pull_request != null) | select(.source.issue.state == "open") | .source.issue.number' </dev/null 2>/dev/null) \
        || { echo "参照元を取得できない"; return; }
    [ -n "$refs" ] && { echo "open の PR から参照されている（#$(printf '%s' "$refs" | head -1)）"; return; }
    if git -C "$ROOT" grep -qE "(#${n}([^0-9]|\$)|/issues/${n}([^0-9]|\$))" -- . 2>/dev/null; then
        echo "リポジトリ内のファイルから参照されている"; return
    fi
}

# open issue の一覧: number<TAB>title<TAB>labels<TAB>assignees<TAB>updatedAt(epoch)<TAB>再発数
open_issues() {
    gh issue list --label "$L_BASE" --state open --limit 1000 \
        --json number,title,labels,assignees,updatedAt,comments --jq "
        .[] | [ (.number|tostring), .title,
                ([.labels[].name] | join(\"$SEP\")),
                (.assignees | length | tostring),
                (.updatedAt | fromdateiso8601 | tostring),
                ([.comments[] | select(.authorAssociation | IN($TRUSTED)) | select(.body | startswith(\"$RECUR_PREFIX\"))] | length | tostring)
              ] | join(\"\\u001e\")"
}

priority_of() {
    local labels="$1" c=0 p=""
    has_label "$labels" "$L_HIGH" && { c=$((c + 1)); p=high; }
    has_label "$labels" "$L_MED" && { c=$((c + 1)); p=medium; }
    [ "$c" -eq 1 ] && echo "$p" || echo "count:$c"
}
category_count() {
    local labels="$1" c=0 k
    for k in $CATEGORY_KEYS; do has_label "$labels" "$L_CAT$k" && c=$((c + 1)); done
    echo "$c"
}

cmd_audit() {
    require_gh
    local rows now n title labels assignees updated recur total=0 pr cats idle
    rows=$(open_issues) || die "audit: issue を取得できません"
    now=$(now_epoch)
    local out_label="" out_promote="" out_stale="" out_keep=""
    while IFS="$FS1" read -r n title labels assignees updated recur; do
        [ -n "$n" ] || continue
        total=$((total + 1))
        pr=$(priority_of "$labels")
        cats=$(category_count "$labels")
        case "$pr" in count:*) out_label="$out_label#$n	優先度ラベルが ${pr#count:} 個	$title
" ;; esac
        [ "$cats" -eq 0 ] && out_label="$out_label#$n	分類ラベルがない	$title
"
        [ "$pr" = medium ] || continue
        if [ "$recur" -ge "$RECUR_HIGH" ]; then
            out_promote="$out_promote#$n	再発 ${recur} 本	$title
"
            continue
        fi
        idle=$(( (now - updated) / 86400 ))
        [ "$idle" -ge "$STALE_DAYS" ] || continue
        local why
        why=$(stale_blocker "$n" "$assignees")
        if [ -n "$why" ]; then
            out_keep="$out_keep#$n	${idle} 日	$why	$title
"
        else
            out_stale="$out_stale#$n	${idle} 日	$title
"
        fi
    done <<EOF
$rows
EOF
    [ "$total" -ge 1000 ] && warn "open issue が 1000 件に達し、一覧が切り詰められた可能性があります"
    echo "# 開発フィードバックの監査（open: ${total} 件）"
    echo
    echo "## ラベルの不整合（優先度はちょうど 1 つ、分類は 1 つ以上）"
    printf '%s' "${out_label:-なし
}"
    echo
    echo "## 昇格の候補（$L_MED で再発コメント ${RECUR_HIGH} 本以上 → promote）"
    printf '%s' "${out_promote:-なし
}"
    echo
    echo "## 見送りの候補（$L_MED で ${STALE_DAYS} 日以上動きなし → close-stale）"
    printf '%s' "${out_stale:-なし
}"
    echo
    echo "## 動きはないが見送らないもの"
    printf '%s' "${out_keep:-なし
}"
}

cmd_close_stale() {
    require_gh
    [ $# -gt 0 ] || die "close-stale: issue 番号を指定してください"
    local n s now closed=0 skipped=0
    now=$(now_epoch)
    for n in "$@"; do
        case "$n" in *[!0-9]*) warn "#$n: 番号ではないので飛ばします"; skipped=$((skipped + 1)); continue ;; esac
        s=$(gh issue view "$n" --json state,labels,assignees,updatedAt --jq "
            [ .state, ([.labels[].name] | join(\"$SEP\")), (.assignees | length | tostring), (.updatedAt | fromdateiso8601 | tostring) ] | join(\"\\u001e\")") \
            || { warn "#$n: 取得できないので閉じません"; skipped=$((skipped + 1)); continue; }
        local state labels assignees updated idle why
        IFS="$FS1" read -r state labels assignees updated <<EOF
$s
EOF
        why=""
        [ "$state" = OPEN ] || why="open ではない"
        [ -z "$why" ] && { has_label "$labels" "$L_BASE" || why="$L_BASE ラベルがない"; }
        [ -z "$why" ] && { [ "$(priority_of "$labels")" = medium ] || why="優先度が $L_MED だけではない"; }
        idle=$(( (now - updated) / 86400 ))
        [ -z "$why" ] && { [ "$idle" -ge "$STALE_DAYS" ] || why="動きのない期間が ${idle} 日（基準 ${STALE_DAYS} 日）"; }
        [ -z "$why" ] && why=$(stale_blocker "$n" "$assignees")
        if [ -n "$why" ]; then
            echo "  skip   #$n: $why"; skipped=$((skipped + 1)); continue
        fi
        {
            echo "$STALE_PREFIX $(today)"
            echo
            echo "- 基準: $L_MED で ${STALE_DAYS} 日以上動きがなく、参照元・担当者もない（${idle} 日）"
            echo "- 再発したら: 新しい issue を立てず、この issue に「$RECUR_PREFIX」で始まるコメントを追加して reopen する"
        } | gh issue comment "$n" --body-file - >/dev/null || { warn "#$n: コメントできないので閉じません"; skipped=$((skipped + 1)); continue; }
        gh issue close "$n" --reason "not planned" >/dev/null || { warn "#$n: 閉じられません"; skipped=$((skipped + 1)); continue; }
        echo "  closed #$n"
        closed=$((closed + 1))
    done
    echo "dev-feedback close-stale: 閉じた ${closed} 件 / 閉じなかった ${skipped} 件"
}

cmd_promote() {
    require_gh
    [ $# -gt 0 ] || die "promote: issue 番号を指定してください"
    local n labels
    for n in "$@"; do
        labels=$(gh issue view "$n" --json labels --jq "[.labels[].name] | join(\"$SEP\")") || { warn "#$n: 取得できません"; continue; }
        if has_label "$labels" "$L_HIGH"; then echo "  skip   #$n: 既に $L_HIGH"; continue; fi
        has_label "$labels" "$L_MED" || { echo "  skip   #$n: $L_MED ではない"; continue; }
        do_promote "$n"
    done
}

case "$CMD" in
    setup) cmd_setup ;;
    check) cmd_check ;;
    file) cmd_file ${ARGS[@]+"${ARGS[@]}"} ;;
    recur) cmd_recur ${ARGS[@]+"${ARGS[@]}"} ;;
    triage) cmd_triage ${ARGS[@]+"${ARGS[@]}"} ;;
    audit) cmd_audit ;;
    close-stale) cmd_close_stale ${ARGS[@]+"${ARGS[@]}"} ;;
    promote) cmd_promote ${ARGS[@]+"${ARGS[@]}"} ;;
    *) die "知らないコマンド: $CMD（--help で一覧）" ;;
esac
