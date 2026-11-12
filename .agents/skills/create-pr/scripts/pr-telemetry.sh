#!/bin/bash
# pr-telemetry.sh — PR ごとの工程テレメトリを記録し、PR コメントとして投稿する。
#
# 使い方:
#   pr-telemetry.sh [--root <dir>] [--repo <owner/name>] <command> [args]
#
#   mark <step> start|end    工程の開始・終了を記録する。step は spec / plan / test / implement / qa / review
#   post [--exempt <kind>] [--review-rounds <n>] [--dry-run]
#                            payload を組み、現在のブランチの PR にコメントとして投稿し、読み直して確かめる
#                            --dry-run は投稿せずに本文を表示する
#   verify                   PR に、head の SHA と一致する payload が載っているかを確かめる（無ければ exit 1）
#
# 免除の区分（レビューをしなかった理由。--exempt）:
#   typo_format_only   誤字・整形だけの変更
#   link_fix_only      リンクの修正だけの変更
#   regenerate_only    生成物の再生成だけの変更
#   user_waived        ユーザーがレビュー不要と指示した
#   emergency          緊急モードで作った PR（レビューをした場合も使う。回数はそのまま記録する）
#
# 緊急モードとの照合: 同じ skill 群の choosing-work-mode/scripts/work-mode.sh で、現在のブランチが
# 緊急モードかを確かめる。緊急モードの枝では --exempt emergency を必須にし、そうでない枝では使わせない。
# --exempt emergency のときは、PR 本文に「緊急モード」の見出しがあることも確かめる。
#
# 項目: 規模・所要時間・レビューの回数と免除・フィードバックの棚卸しの件数。schema 2 で、PR 前レビューの台帳
# （reviewing-changes/scripts/review-ledger.sh）の集計（指摘の処置の内訳・独立性・実行で確かめられなかった指摘の
# 担当ごとの件数）を足した。値が測れなかった項目は null（0 とは区別する）。
#
# 記録の置き場は作業ツリーの外（git の共通ディレクトリ配下の stdd-telemetry/<ブランチ>.tsv）なので、
# コミットにも差分にも入らない。行の形式は <epoch>\t<kind>\t<arg>（recording-dev-feedback の
# dev-feedback.sh も同じ置き場へ feedback-filed / feedback-recur / feedback-triage を書く）。
#
# 設定: .stdd.config.yml の telemetry.enabled が false なら何もせず exit 0。
# 依存: bash 3.2 以上、git、gh（gh の --jq を使う）。

set -u

ROOT=""
REPO=""
CMD=""
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --root) ROOT="${2:-}"; shift 2 ;;
        --repo) REPO="${2:-}"; shift 2 ;;
        --help|-h) sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)
            if [ -z "$CMD" ]; then CMD="$1"; else ARGS+=("$1"); fi
            shift ;;
    esac
done

die()  { echo "pr-telemetry: $*" >&2; exit 1; }
warn() { echo "pr-telemetry: $*" >&2; }

[ -n "$CMD" ] || die "コマンドを指定してください（--help で一覧）"
case "$REPO" in --*) die "--repo には owner/name を渡してください: $REPO" ;; esac
[ -n "$REPO" ] && export GH_REPO="$REPO"

if [ -z "$ROOT" ]; then
    ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
CONFIG="$ROOT/.stdd.config.yml"

# トップレベルのブロック内の leaf キーの値（外部依存なしのパーサ）
cfg() {
    local v
    [ -f "$CONFIG" ] || { printf '%s' "$3"; return; }
    v=$(awk -v blk="$1:" -v k="$2:" '
        /^[^[:space:]#]/ { inblk = ($1 == blk); next }
        inblk && $1 == k { sub(/^[[:space:]]*[^:]*:[[:space:]]*/, ""); print; exit }
    ' "$CONFIG")
    v=$(printf '%s' "$v" | sed 's/[[:space:]]#.*$//; s/[[:space:]]*$//; s/^"//; s/"$//')
    printf '%s' "${v:-$3}"
}

ENABLED=$(cfg telemetry enabled true)
FEEDBACK_ENABLED=$(cfg feedback enabled true)
if [ "$ENABLED" = "false" ]; then
    echo "pr-telemetry: telemetry.enabled が false のため何もしません"
    exit 0
fi

STEPS="spec plan test implement qa review"
EXEMPT_KINDS="typo_format_only link_fix_only regenerate_only user_waived emergency"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
WORK_MODE="$SCRIPT_DIR/../../choosing-work-mode/scripts/work-mode.sh"
REVIEW_LEDGER="$SCRIPT_DIR/../../reviewing-changes/scripts/review-ledger.sh"
MARKER="<!-- stdd-telemetry -->"
SCHEMA="stdd-telemetry/2"

now_epoch() { printf '%s' "${STDD_NOW:-$(date +%s)}"; }

events_file() {
    local common branch
    common=$(cd "$ROOT" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd) || return 1
    branch=$(git -C "$ROOT" branch --show-current 2>/dev/null)
    [ -n "$branch" ] || return 1
    mkdir -p "$common/stdd-telemetry" || return 1
    printf '%s/stdd-telemetry/%s.tsv' "$common" "$(printf '%s' "$branch" | sed 's|/|__|g')"
}

require_gh() {
    command -v gh >/dev/null 2>&1 || die "gh コマンドがありません（https://cli.github.com/）"
}

# ---------------------------------------------------------------------------
cmd_mark() {
    local step="${1:-}" edge="${2:-}" f
    case " $STEPS " in *" $step "*) ;; *) die "mark: step は $STEPS のどれかです: '$step'" ;; esac
    case "$edge" in start|end) ;; *) die "mark: start か end を指定してください" ;; esac
    # 記録できなくても作業は止めない
    f=$(events_file) || { warn "記録先を決められないため記録しません（git の作業ツリー外か detached HEAD）"; exit 0; }
    printf '%s\t%s\t%s\n' "$(now_epoch)" "$edge" "$step" >> "$f"
}

json_str() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }

# 記録から工程別の分（完了した start/end の組の合計）と、レビューの回数（完了した review の組の数）を出す
#   出力: steps_json<TAB>review_rounds<TAB>first_epoch<TAB>feedback_json
summarize_events() {
    local f="$1"
    awk -F'\t' -v steps="$STEPS" '
        BEGIN { n = split(steps, order, " ") }
        NR == 1 || $1 < first { first = $1 }
        $2 == "start" { open[$3] = $1; next }
        $2 == "end" && ($3 in open) {
            total[$3] += $1 - open[$3]; done[$3] = 1
            if ($3 == "review") rounds++
            delete open[$3]; next
        }
        $2 == "feedback-filed" { filed++ }
        $2 == "feedback-recur" { recurred++ }
        $2 == "feedback-triage" { triaged = 1; skipped = $3 }
        END {
            s = ""
            for (i = 1; i <= n; i++) {
                k = order[i]
                if (k in done) s = s (s == "" ? "" : ",") "\"" k "\":" int((total[k] + 30) / 60)
            }
            steps_json = (s == "") ? "null" : "{" s "}"
            fb = triaged ? sprintf("{\"filed\":%d,\"recurred\":%d,\"skipped_by_cap\":%d}", filed, recurred, skipped) : "null"
            printf "%s\t%d\t%s\t%s\n", steps_json, rounds, (first == "" ? 0 : first), fb
        }
    ' "$f"
}

build_payload() {
    local exempt="$1" rounds_override="$2"
    local pr head base add del files commits local_head
    local info
    info=$(gh pr view --json number,headRefOid,baseRefName,additions,deletions,changedFiles,commits \
        --jq '[(.number|tostring), .headRefOid, .baseRefName, (.additions|tostring), (.deletions|tostring), (.changedFiles|tostring), (.commits|length|tostring)] | @tsv' 2>/dev/null) \
        || die "現在のブランチの PR を取得できません（PR を作成してから実行してください）"
    IFS="$(printf '\t')" read -r pr head base add del files commits <<EOF
$info
EOF
    local_head=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)
    [ "$local_head" = "$head" ] || die "手元の HEAD（${local_head:0:12}）が PR の head（${head:0:12}）と一致しません。push してから実行してください"

    local steps="null" rounds=0 first=0 fb="null" f
    if f=$(events_file) && [ -f "$f" ]; then
        IFS="$(printf '\t')" read -r steps rounds first fb <<EOF
$(summarize_events "$f")
EOF
    fi
    # PR 前レビューの台帳（reviewing-changes）の集計。ラウンド数は工程の記録と台帳の多いほう
    local ledger="null" lr
    if [ -f "$REVIEW_LEDGER" ]; then
        ledger=$(bash "$REVIEW_LEDGER" --root "$ROOT" summary --json 2>/dev/null) || ledger="null"
        [ -n "$ledger" ] || ledger="null"
        lr=$(printf '%s' "$ledger" | sed -n 's/^{"rounds":\([0-9]*\).*/\1/p')
        [ -n "$lr" ] && [ "$lr" -gt "$rounds" ] && rounds="$lr"
    fi
    [ -n "$rounds_override" ] && rounds="$rounds_override"

    local emergency=no
    if [ -f "$WORK_MODE" ] && bash "$WORK_MODE" --root "$ROOT" active >/dev/null 2>&1; then emergency=yes; fi
    if [ "$emergency" = yes ] && [ "$exempt" != "emergency" ]; then
        die "このブランチは緊急モードです。--exempt emergency を付けて投稿してください（レビューをした回数はそのまま記録されます）"
    fi
    if [ "$exempt" = "emergency" ]; then
        [ "$emergency" = yes ] || die "--exempt emergency は緊急モードを宣言したブランチでだけ使います（choosing-work-mode）"
        gh pr view --json body --jq '.body // ""' 2>/dev/null | grep -qE '^#{1,6}[[:space:]]*緊急モード[[:space:]]*$' \
            || die "PR 本文に「## 緊急モード」の節がありません。宣言の理由・省いた工程・赤のまま残した検査・後追いが要るものを書いてから投稿してください"
    elif [ -n "$exempt" ]; then
        case " $EXEMPT_KINDS " in *" $exempt "*) ;; *) die "--exempt は $EXEMPT_KINDS のどれかです: '$exempt'" ;; esac
        [ "$rounds" -eq 0 ] || die "--exempt はレビューをしなかった PR にだけ使います（記録上のレビュー: ${rounds} 回）"
    elif [ "$rounds" -eq 0 ]; then
        echo "pr-telemetry NG: レビューの記録も免除の申告もありません" >&2
        echo "  レビューをしたなら --review-rounds <回数>、しなかったなら --exempt <区分>（$EXEMPT_KINDS）を渡してください" >&2
        exit 1
    fi

    # 所要の起点: 最初の記録と、ブランチの最初のコミットの早いほう
    local start="$first" c mb
    mb=$(git -C "$ROOT" merge-base HEAD "origin/$base" 2>/dev/null || true)
    if [ -n "$mb" ]; then
        c=$(git -C "$ROOT" log --reverse --format=%ct "$mb..HEAD" 2>/dev/null | head -1)
        if [ -n "$c" ] && { [ "$start" -eq 0 ] || [ "$c" -lt "$start" ]; }; then start="$c"; fi
    fi
    local lead="null"
    [ "$start" -gt 0 ] && lead=$(( ($(now_epoch) - start + 30) / 60 ))

    local exempt_json="null"
    [ -n "$exempt" ] && exempt_json=$(json_str "$exempt")

    # 台帳が無ければ findings / independent / unconfirmed は null（0 とは区別する）
    local findings="null" independent="null" unconfirmed="null"
    if [ "$ledger" != "null" ]; then
        findings=$(printf '%s' "$ledger" | sed -n 's/.*"findings":\({[^}]*}\).*/\1/p')
        independent=$(printf '%s' "$ledger" | sed -n 's/.*"independent":\([^,]*\),.*/\1/p')
        unconfirmed=$(printf '%s' "$ledger" | sed -n 's/.*"unconfirmed":\({[^}]*}\).*/\1/p')
    fi

    printf '{"schema":"%s","pr":%s,"head_sha":"%s","base":%s,"size":{"files":%s,"additions":%s,"deletions":%s,"commits":%s},"duration_min":{"lead_time":%s,"steps":%s},"review":{"rounds":%s,"exempt":%s,"findings":%s,"independent":%s,"unconfirmed":%s},"feedback":%s}\n' \
        "$SCHEMA" "$pr" "$head" "$(json_str "$base")" "$files" "$add" "$del" "$commits" "$lead" "$steps" "$rounds" "$exempt_json" \
        "${findings:-null}" "${independent:-null}" "${unconfirmed:-null}" "$fb"
}

comment_body() {
    echo "$MARKER"
    echo "**工程テレメトリ**（create-pr が投稿する集計用の記録です。編集しないでください）"
    echo
    echo '```json'
    printf '%s\n' "$1"
    echo '```'
}

# head の SHA と一致する payload の数と、そのうち feedback を持つ数（緊急モードの PR は棚卸しをしないので数に含める）
#   出力: matched<TAB>with_feedback
count_payloads() {
    gh pr view --json headRefOid,comments --jq '
        .headRefOid as $h
        | [ .comments[]
            | select(.authorAssociation | IN("OWNER","MEMBER","COLLABORATOR"))
            | .body
            | select(contains("<!-- stdd-telemetry -->"))
            | (capture("```json\\s*(?<j>\\{[\\s\\S]*\\})\\s*```").j | fromjson?)
            | select((.schema // "") | startswith("stdd-telemetry/"))
            | select(.head_sha == $h) ]
        | [ length, (map(select(.feedback != null or .review.exempt == "emergency")) | length) ] | map(tostring) | @tsv'
}

cmd_verify() {
    require_gh
    local r matched withfb
    r=$(count_payloads) || die "verify: PR を取得できません"
    IFS="$(printf '\t')" read -r matched withfb <<EOF
$r
EOF
    if [ "${matched:-0}" -eq 0 ]; then
        echo "pr-telemetry verify NG: PR の head に対応するテレメトリが PR から読めません" >&2
        echo "  投稿の失敗か、投稿後にコミットを積んだ可能性があります。post をもう一度実行してください" >&2
        exit 1
    fi
    if [ "$FEEDBACK_ENABLED" != "false" ] && [ "${withfb:-0}" -eq 0 ]; then
        warn "警告: フィードバックの棚卸しの記録がありません（recording-dev-feedback の triage を実行していない）"
    fi
    echo "pr-telemetry verify OK"
}

cmd_post() {
    require_gh
    local exempt="" rounds="" dry=no
    while [ $# -gt 0 ]; do
        case "$1" in
            --exempt) exempt="${2:-}"; shift 2 ;;
            --review-rounds)
                rounds="${2:-}"
                case "$rounds" in ''|*[!0-9]*) die "--review-rounds には回数を渡してください" ;; esac
                shift 2 ;;
            --dry-run) dry=yes; shift ;;
            *) die "post: 知らない引数: $1" ;;
        esac
    done
    local payload tmp
    payload=$(build_payload "$exempt" "$rounds") || exit 1
    if [ "$dry" = yes ]; then comment_body "$payload"; exit 0; fi
    tmp=$(mktemp "${TMPDIR:-/tmp}/pr-telemetry.XXXXXX")
    comment_body "$payload" > "$tmp"
    gh pr comment --body-file "$tmp" >/dev/null || { rm -f "$tmp"; die "PR にコメントを投稿できません"; }
    rm -f "$tmp"
    echo "pr-telemetry post: 投稿しました"
    cmd_verify
}

case "$CMD" in
    mark) cmd_mark ${ARGS[@]+"${ARGS[@]}"} ;;
    post) cmd_post ${ARGS[@]+"${ARGS[@]}"} ;;
    verify) cmd_verify ;;
    *) die "知らないコマンド: $CMD（--help で一覧）" ;;
esac
