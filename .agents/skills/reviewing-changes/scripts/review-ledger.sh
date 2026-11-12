#!/bin/bash
# review-ledger.sh — PR 前レビューの台帳・担当の決定・処置の導出・PR 作成前のゲート。
#
# 使い方:
#   review-ledger.sh [--root <dir>] [--base <ref>] <command> [args]
#
#   plan                       差分から、起動する担当と起動しない担当（理由つき）を表示する（記録しない）
#   round start [--independent yes|no] [--add <担当>]... [--skip <担当>=<理由>]...
#                              ラウンドを始める。HEAD をレビューする時点のコミットとして記録し、担当の決定を記録する
#   round end                  ラウンドを終える（ラウンドの途中でコミットしていれば警告する）
#   report --role <担当> (--ids "<ID>,<ID>" | --file <報告のファイル>)
#                              reviewer の報告の末尾の指摘 ID の一覧を記録する（無ければ --ids none）
#   add --id <ID> --role <担当> --trigger <発生条件> --frequency 常時|条件付き|稀 --impact 致命|支障|軽微
#       --target <影響先> --evidence 1-5
#                              指摘を台帳に載せ、導いた処置を表示する。セキュリティの担当は --frequency を書かない
#   unproven --id <ID> --role <担当> --reason <理由>
#                              実行で確かめられなかった指摘を記録する（台帳の指摘には数えない）
#   raise --id <ID> [--frequency <値>] [--impact <値>]
#                              4 項目を上げる（下げることはできない）
#   fixed --id <ID> --commit <SHA> | filed --id <ID> --issue <番号> | defer --id <ID> --reason <理由>
#                              指摘の状態を記録する。defer は処置が「見送り可」の指摘にだけ使える
#   derive --role <担当> [--frequency <値>] --impact <値> --target <影響先>
#                              処置の導出だけを行う（記録しない）
#   gate                       PR 作成の前の 3 条件を確かめる（満たさなければ exit 1）
#   summary [--json]           台帳の集計を表示する（--json は工程テレメトリ用）
#   table                      処置の表と起こりやすさの表を表示する
#
# 処置の表と起こりやすさの表は、このスクリプトの likelihood() と action() だけに置く。文書に転記しない。
#
# 担当（起動の単位）: cross（横断）/ consistency（突合）/ requirements / tech-specs / test /
#   code-quality（規約と品質）/ code-performance（性能とエラー処理）/ security（セキュリティ）
#   実行で証明できた指摘だけを台帳に載せる担当: test / code-quality / code-performance / security
#
# 置き場: 作業ツリーの外（git の共通ディレクトリ配下の stdd-review/<ブランチの / を __ にしたもの>.tsv）。
#   コミットにも差分にも入らない。1 行 1 記録のタブ区切りで、追記だけを行う（同じ ID の後の行が勝つ）。
#
# 設定（.stdd.config.yml の review。すべて任意）:
#   harness_paths  ハーネスのファイルの正規表現。差分がすべてこれに当たれば、指摘の種別をハーネスにする
#   global_paths   影響先に含まれていれば範囲を「全体」にするパスの正規表現
#   global_words   影響先に含まれていれば範囲を「全体」にする語の正規表現
#   triggers.<cross|consistency|requirements|tech_specs|test|code|security>
#                  担当を起動する差分のパスの正規表現。always は常に、never は起動しない
# 依存: bash 3.2 以上、git、awk。

set -u

ROOT=""
BASE=""
CMD=""
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --root) ROOT="${2:-}"; shift 2 ;;
        --base) BASE="${2:-}"; shift 2 ;;
        --help|-h) sed -n '2,42p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)
            if [ -z "$CMD" ]; then CMD="$1"; else ARGS+=("$1"); fi
            shift ;;
    esac
done

die()  { echo "review-ledger NG: $*" >&2; exit 1; }
warn() { echo "review-ledger 警告: $*" >&2; }
TAB=$(printf '\t')

[ -n "$CMD" ] || die "コマンドを指定してください（--help で一覧）"
[ -n "$ROOT" ] || ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CONFIG="$ROOT/.stdd.config.yml"

# ---------------------------------------------------------------------------
# 設定（外部依存なしのパーサ）
# ---------------------------------------------------------------------------
unquote() {
    local v="$1"
    case "$v" in
        \"*) v="${v#\"}"; v="${v%\"*}" ;;
        \'*) v="${v#\'}"; v="${v%\'*}" ;;
        *)   v=$(printf '%s' "$v" | sed 's/[[:space:]]#.*$//; s/[[:space:]]*$//') ;;
    esac
    printf '%s' "$v"
}
# $1 = トップレベルのブロック, $2 = キー（2 段目）, $3 = キー（3 段目、任意）
cfg() {
    [ -f "$CONFIG" ] || return 0
    local v
    v=$(awk -v blk="$1:" -v k2="$2:" -v k3="${3:-}" '
        /^[^[:space:]#]/ { inblk = ($1 == blk); insub = 0; next }
        !inblk { next }
        k3 == "" && /^  [^[:space:]#]/ && $1 == k2 { sub(/^[[:space:]]*[^:]*:[[:space:]]*/, ""); print; exit }
        k3 != "" && /^  [^[:space:]#]/ { insub = ($1 == k2); next }
        k3 != "" && insub && $1 == k3 ":" { sub(/^[[:space:]]*[^:]*:[[:space:]]*/, ""); print; exit }
    ' "$CONFIG")
    unquote "$v"
}

PRIMARY=$(cfg project primary_branch); PRIMARY=${PRIMARY:-main}
HARNESS_RE=$(cfg review harness_paths)
HARNESS_RE=${HARNESS_RE:-'^(\.claude|\.agents|\.codex|\.stdd)/|^(AGENTS|CLAUDE)\.md$|^\.stdd\.config\.yml$'}
GLOBAL_PATHS_RE=$(cfg review global_paths)
GLOBAL_PATHS_RE=${GLOBAL_PATHS_RE:-'(^|[[:space:]/])(AGENTS|CLAUDE)\.md|(^|/)\.claude/rules/|(^|/)docs/common/|(^|/)(shared|common)/'}
GLOBAL_WORDS_RE=$(cfg review global_words)
GLOBAL_WORDS_RE=${GLOBAL_WORDS_RE:-'認証|認可|権限|テナント|セッション|全画面|全 API|すべての'}

ROLES="cross consistency requirements tech-specs test code-quality code-performance security"
PROOF_ROLES="test code-quality code-performance security"

role_agent() {
    case "$1" in
        cross|consistency) echo qa-engineer ;;
        requirements) echo requirements-reviewer ;;
        tech-specs) echo tech-specs-reviewer ;;
        test) echo test-reviewer ;;
        code-quality|code-performance|security) echo code-reviewer ;;
    esac
}
role_label() {
    case "$1" in
        cross) echo "横断" ;; consistency) echo "突合" ;; requirements) echo "要件" ;;
        tech-specs) echo "技術設計" ;; test) echo "テスト" ;; code-quality) echo "規約と品質" ;;
        code-performance) echo "性能とエラー処理" ;; security) echo "セキュリティ" ;;
    esac
}
RE_REQ='(^|/)REQUIREMENTS\.md$'
RE_TECH='(^|/)(TECH_DESIGN|TEST_PLAN|ARCHITECTURE|TABLE_DEFINITION|API_SPEC|DESIGN)\.md$'
RE_TEST='(^|/)(tests?|__tests__|e2e)/|[._-](test|spec)\.[A-Za-z0-9]+$'
RE_CODE='\.(ts|tsx|js|jsx|mjs|cjs|py|rb|go|rs|java|kt|kts|swift|php|cs|scala|sh|bash|sql|vue|svelte)$'
role_trigger() {
    local key def v
    case "$1" in
        cross) key=cross; def=always ;;
        consistency) key=consistency; def="$RE_REQ|$RE_TECH|$RE_TEST|$RE_CODE" ;;
        requirements) key=requirements; def="$RE_REQ" ;;
        tech-specs) key=tech_specs; def="$RE_TECH" ;;
        test) key=test; def="$RE_TEST" ;;
        code-quality|code-performance) key=code; def="$RE_CODE" ;;
        security) key=security; v=$(cfg review triggers security); [ -n "$v" ] || v=$(cfg review triggers code); def="$RE_CODE"
            printf '%s' "${v:-$def}"; return ;;
    esac
    v=$(cfg review triggers "$key")
    printf '%s' "${v:-$def}"
}
in_list()  { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }
is_role()  { in_list "$1" "$ROLES"; }
is_proof() { in_list "$1" "$PROOF_ROLES"; }

# ---------------------------------------------------------------------------
# git
# ---------------------------------------------------------------------------
base_ref() {
    if [ -n "$BASE" ]; then printf '%s' "$BASE"; return; fi
    if git -C "$ROOT" rev-parse -q --verify "origin/$PRIMARY" >/dev/null 2>&1; then printf 'origin/%s' "$PRIMARY"
    elif git -C "$ROOT" rev-parse -q --verify "$PRIMARY" >/dev/null 2>&1; then printf '%s' "$PRIMARY"
    fi
}
changed_files() {
    local b
    b=$(base_ref)
    [ -n "$b" ] || return 0
    git -C "$ROOT" diff --name-only "$b...HEAD" 2>/dev/null
}
head_sha() { git -C "$ROOT" rev-parse HEAD 2>/dev/null; }

ledger_file() {
    local common branch
    common=$(cd "$ROOT" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd) || return 1
    branch=$(git -C "$ROOT" branch --show-current 2>/dev/null)
    [ -n "$branch" ] || return 1
    printf '%s/stdd-review/%s.tsv' "$common" "$(printf '%s' "$branch" | sed 's|/|__|g')"
}
LEDGER=$(ledger_file) || LEDGER=""
record() {
    [ -n "$LEDGER" ] || die "台帳の置き場を決められません（git の作業ツリーの外か detached HEAD）"
    mkdir -p "$(dirname "$LEDGER")" || die "台帳の置き場を作れません: $(dirname "$LEDGER")"
    local IFS="$TAB"
    printf '%s\n' "$*" | tr -d '\r' >> "$LEDGER"
}
clean() { printf '%s' "$1" | tr '\t\n' '  '; }   # 欄に入れる値からタブと改行を除く
lines() { [ -n "$LEDGER" ] && [ -f "$LEDGER" ] && awk -F'\t' -v t="$1" '$1 == t' "$LEDGER"; }
current_round() { lines round | awk -F'\t' 'END { print ($2 == "" ? 0 : $2) }'; }

# ---------------------------------------------------------------------------
# 処置の導出（表はここだけに置く）
# ---------------------------------------------------------------------------
# 起こりやすさ: $1 = 頻度, $2 = 範囲
likelihood() {
    case "$1/$2" in
        常時/全体|常時/複数|条件付き/全体) echo 高 ;;
        常時/単一|条件付き/複数|稀/全体) echo 中 ;;
        条件付き/単一|稀/複数|稀/単一) echo 低 ;;
    esac
}
# 処置: $1 = 種別, $2 = 起こりやすさ, $3 = 影響
action() {
    case "$1/$2/$3" in
        */*/致命) echo 直す ;;
        プロダクト/高/支障|プロダクト/中/支障) echo 直す ;;
        プロダクト/低/支障|プロダクト/高/軽微) echo 起票 ;;
        プロダクト/中/軽微|プロダクト/低/軽微) echo 見送り可 ;;
        ハーネス/高/支障) echo 直す ;;
        ハーネス/中/支障|ハーネス/低/支障|ハーネス/*/軽微) echo 見送り可 ;;
    esac
}
# セキュリティの担当: 頻度を評価せず、影響だけで決める（軽微でも起票する）
security_action() {
    case "$1" in 致命|支障) echo 直す ;; 軽微) echo 起票 ;; esac
}

kind_of_diff() {
    local files
    files=$(changed_files)
    if [ -n "$files" ] && ! printf '%s\n' "$files" | grep -Evq -- "$HARNESS_RE"; then echo ハーネス; else echo プロダクト; fi
}
scope_of() {
    local t="$1" n
    if printf '%s' "$t" | grep -Eq -- "$GLOBAL_WORDS_RE" || printf '%s' "$t" | grep -Eq -- "$GLOBAL_PATHS_RE"; then
        echo 全体; return
    fi
    n=$(printf '%s' "$t" | sed 's/、/,/g' | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -c .)
    if [ "$n" -gt 1 ]; then echo 複数; else echo 単一; fi
}
valid_freq()   { case "$1" in 常時|条件付き|稀) return 0 ;; esac; return 1; }
valid_impact() { case "$1" in 致命|支障|軽微) return 0 ;; esac; return 1; }
rank_freq()   { case "$1" in 稀) echo 1 ;; 条件付き) echo 2 ;; 常時) echo 3 ;; *) echo 0 ;; esac; }
rank_impact() { case "$1" in 軽微) echo 1 ;; 支障) echo 2 ;; 致命) echo 3 ;; *) echo 0 ;; esac; }

# 出力: 種別<TAB>範囲<TAB>起こりやすさ<TAB>処置
derive() {
    local role="$1" freq="$2" impact="$3" target="$4" kind scope lk act
    kind=$(kind_of_diff); scope=$(scope_of "$target")
    if [ "$role" = security ]; then
        lk="-"; act=$(security_action "$impact")
    else
        lk=$(likelihood "$freq" "$scope"); act=$(action "$kind" "$lk" "$impact")
    fi
    printf '%s\t%s\t%s\t%s\n' "$kind" "$scope" "$lk" "$act"
}

# 指摘の最新の行（ID ごとに後の行が勝つ）: 出力 = finding の行
latest_findings() {
    [ -n "$LEDGER" ] && [ -f "$LEDGER" ] || return 0
    awk -F'\t' '$1 == "finding" { if (!($2 in row)) order[++n] = $2; row[$2] = $0 }
        END { for (i = 1; i <= n; i++) print row[order[i]] }' "$LEDGER"
}
finding_field() { latest_findings | awk -F'\t' -v id="$1" -v c="$2" '$2 == id { print $c }'; }
latest_state() {
    [ -n "$LEDGER" ] && [ -f "$LEDGER" ] || return 0
    awk -F'\t' -v id="$1" '$1 == "state" && $2 == id { s = $3 "\t" $4 } END { if (s != "") print s }' "$LEDGER"
}

# ---------------------------------------------------------------------------
# 担当の決定
# ---------------------------------------------------------------------------
# 出力: launch<TAB>担当<TAB>agent<TAB>理由 / skip<TAB>担当<TAB>-<TAB>理由
plan_roles() {
    local files role trig hit
    files=$(changed_files)
    for role in $ROLES; do
        trig=$(role_trigger "$role")
        case "$trig" in
            always) printf 'launch\t%s\t%s\t常に起動する\n' "$role" "$(role_agent "$role")"; continue ;;
            never)  printf 'skip\t%s\t-\t設定で起動しない（review.triggers）\n' "$role"; continue ;;
        esac
        hit=$(printf '%s\n' "$files" | grep -E -- "$trig" | head -1)
        if [ -n "$hit" ]; then
            printf 'launch\t%s\t%s\t差分に %s がある\n' "$role" "$(role_agent "$role")" "$hit"
        else
            printf 'skip\t%s\t-\t差分に対象のファイルが無い\n' "$role"
        fi
    done
}
print_plan() {
    printf '%s\n' "$1" | while IFS="$TAB" read -r kind role agent reason; do
        [ -n "$kind" ] || continue
        if [ "$kind" = launch ]; then
            printf '  起動   %-17s %-22s（%s）%s\n' "$role" "$agent" "$(role_label "$role")" "$reason"
        else
            printf '  起動しない %-13s %s\n' "$role" "$reason"
        fi
    done
}

cmd_plan() {
    echo "差分の基準: $(base_ref)"
    print_plan "$(plan_roles)"
}

cmd_round() {
    local sub="${1:-}"; shift || true
    case "$sub" in
        start)
            local indep=no adds="" skips="" a
            while [ $# -gt 0 ]; do
                case "$1" in
                    --independent) indep="${2:-}"; shift 2 ;;
                    --add) is_role "${2:-}" || die "知らない担当: ${2:-}（$ROLES）"; adds="$adds ${2}"; shift 2 ;;
                    --skip)
                        a="${2:-}"; is_role "${a%%=*}" || die "知らない担当: ${a%%=*}（$ROLES）"
                        [ -n "${a#*=}" ] && [ "${a#*=}" != "$a" ] || die "--skip は <担当>=<理由> で渡してください"
                        skips="$skips$a"$'\n'; shift 2 ;;
                    *) die "round start: 知らない引数: $1" ;;
                esac
            done
            case "$indep" in yes|no) ;; *) die "--independent は yes か no です" ;; esac
            local h n p
            h=$(head_sha) || die "HEAD を解決できません"
            [ -z "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ] || warn "コミットしていない変更があります。レビューはコミットに対して行うので、先にコミットしてください"
            n=$(( $(current_round) + 1 ))
            p=$(plan_roles | while IFS="$TAB" read -r kind role agent reason; do
                s=$(printf '%s' "$skips" | awk -F= -v r="$role" '$1 == r { sub(/^[^=]*=/, ""); print; exit }')
                if [ -n "$s" ]; then printf 'skip\t%s\t-\t%s\n' "$role" "$s"
                elif [ "$kind" = skip ] && in_list "$role" "$adds"; then
                    printf 'launch\t%s\t%s\t追加で起動する\n' "$role" "$(role_agent "$role")"
                else printf '%s\t%s\t%s\t%s\n' "$kind" "$role" "$agent" "$reason"
                fi
            done)
            record round "$n" "$h" "$indep" "${STDD_NOW:-$(date +%s)}"
            printf '%s\n' "$p" | while IFS="$TAB" read -r kind role agent reason; do
                [ -n "$kind" ] && record "$kind" "$n" "$role" "$(clean "$reason")"
            done
            echo "ラウンド $n を始めました（レビューする時点のコミット: ${h:0:12}、独立性: $indep）"
            print_plan "$p"
            ;;
        end)
            local n h start
            n=$(current_round); [ "$n" -gt 0 ] || die "始めたラウンドがありません（round start）"
            start=$(lines round | awk -F'\t' -v n="$n" '$2 == n { print $3 }')
            h=$(head_sha)
            [ "$h" = "$start" ] || warn "ラウンド $n の途中でコミットしています（${start:0:12} → ${h:0:12}）。修正はラウンドを終えてからコミットしてください"
            record round-end "$n" "$h" "${STDD_NOW:-$(date +%s)}"
            echo "ラウンド $n を終えました"
            ;;
        *) die "round の後に start か end を指定してください" ;;
    esac
}

# 引数の解析: --key value を KEY_<key> に入れる
parse_opts() {
    OPT_id=""; OPT_role=""; OPT_trigger=""; OPT_frequency=""; OPT_impact=""; OPT_target=""; OPT_evidence=""
    OPT_reason=""; OPT_commit=""; OPT_issue=""; OPT_ids=""; OPT_file=""; OPT_json=no
    while [ $# -gt 0 ]; do
        case "$1" in
            --id|--role|--trigger|--frequency|--impact|--target|--evidence|--reason|--commit|--issue|--ids|--file)
                [ $# -ge 2 ] || die "$1 に値を渡してください"
                eval "OPT_${1#--}=\$2"; shift 2 ;;
            --json) OPT_json=yes; shift ;;
            *) die "知らない引数: $1" ;;
        esac
    done
}

cmd_add() {
    parse_opts "$@"
    [ -n "$OPT_id" ] || die "--id を渡してください"
    is_role "$OPT_role" || die "--role は $ROLES のどれかです"
    [ -n "$OPT_trigger" ] || die "--trigger（発生条件）を渡してください"
    [ -n "$OPT_target" ] || die "--target（影響先）を渡してください"
    valid_impact "$OPT_impact" || die "--impact は 致命 / 支障 / 軽微 のどれかです"
    if [ "$OPT_role" = security ]; then
        [ -z "$OPT_frequency" ] || die "セキュリティの担当の指摘は頻度を評価しません（--frequency を外してください）"
        OPT_frequency="-"
    else
        valid_freq "$OPT_frequency" || die "--frequency は 常時 / 条件付き / 稀 のどれかです"
    fi
    case "$OPT_evidence" in [1-5]) ;; *) die "--evidence は確信の段階（1〜5。assessing-change-impact §1）です" ;; esac
    if is_proof "$OPT_role" && [ "$OPT_evidence" -lt 4 ]; then
        die "担当 $OPT_role の指摘は、実行で失敗を確かめたもの（確信の段階 4 以上）だけを台帳に載せます。確かめられなければ unproven で記録してください"
    fi
    [ -z "$(finding_field "$OPT_id" 2)" ] || die "ID $OPT_id は台帳にあります（4 項目を上げるなら raise）"
    local n d
    n=$(current_round); [ "$n" -gt 0 ] || die "始めたラウンドがありません（round start）"
    d=$(derive "$OPT_role" "$OPT_frequency" "$OPT_impact" "$OPT_target")
    IFS="$TAB" read -r kind scope lk act <<EOF
$d
EOF
    record finding "$OPT_id" "$n" "$OPT_role" "$OPT_frequency" "$OPT_impact" "$kind" "$scope" "$lk" "$act" \
        "$OPT_evidence" "$(clean "$OPT_trigger")" "$(clean "$OPT_target")"
    echo "$OPT_id: 種別 $kind / 範囲 $scope / 起こりやすさ $lk / 影響 $OPT_impact → 処置: $act"
}

cmd_raise() {
    parse_opts "$@"
    local row role freq impact target evidence trigger n
    row=$(latest_findings | awk -F'\t' -v id="$OPT_id" '$2 == id')
    [ -n "$row" ] || die "ID $OPT_id は台帳にありません"
    IFS="$TAB" read -r _ _ n role freq impact _ _ _ _ evidence trigger target <<EOF
$row
EOF
    if [ -n "$OPT_frequency" ]; then
        [ "$role" != security ] || die "セキュリティの担当の指摘は頻度を評価しません"
        valid_freq "$OPT_frequency" || die "--frequency は 常時 / 条件付き / 稀 のどれかです"
        [ "$(rank_freq "$OPT_frequency")" -ge "$(rank_freq "$freq")" ] || die "4 項目は下げられません（頻度 $freq → $OPT_frequency）"
        freq="$OPT_frequency"
    fi
    if [ -n "$OPT_impact" ]; then
        valid_impact "$OPT_impact" || die "--impact は 致命 / 支障 / 軽微 のどれかです"
        [ "$(rank_impact "$OPT_impact")" -ge "$(rank_impact "$impact")" ] || die "4 項目は下げられません（影響 $impact → $OPT_impact）"
        impact="$OPT_impact"
    fi
    local d kind scope lk act
    d=$(derive "$role" "$freq" "$impact" "$target")
    IFS="$TAB" read -r kind scope lk act <<EOF
$d
EOF
    record finding "$OPT_id" "$n" "$role" "$freq" "$impact" "$kind" "$scope" "$lk" "$act" "$evidence" "$trigger" "$target"
    echo "$OPT_id: 種別 $kind / 範囲 $scope / 起こりやすさ $lk / 影響 $impact → 処置: $act"
}

cmd_unproven() {
    parse_opts "$@"
    [ -n "$OPT_id" ] || die "--id を渡してください"
    is_proof "$OPT_role" || die "unproven は実行で証明する担当（$PROOF_ROLES）にだけ使います"
    [ -n "$OPT_reason" ] || die "--reason（確かめられなかった理由）を渡してください"
    local n; n=$(current_round); [ "$n" -gt 0 ] || die "始めたラウンドがありません（round start）"
    record unproven "$OPT_id" "$n" "$OPT_role" "$(clean "$OPT_reason")"
    echo "$OPT_id: 実行で確かめられなかった指摘として記録しました（台帳の指摘には数えません）"
}

cmd_state() {
    local kind="$1"; shift
    parse_opts "$@"
    local act; act=$(finding_field "$OPT_id" 10)
    [ -n "$act" ] || die "ID $OPT_id は台帳にありません"
    case "$kind" in
        fixed)
            local sha; sha=$(git -C "$ROOT" rev-parse -q --verify "${OPT_commit}^{commit}" 2>/dev/null) || die "--commit にコミットを渡してください: ${OPT_commit}"
            record state "$OPT_id" 修正済み "$sha"; echo "$OPT_id: 修正済み（${sha:0:12}）" ;;
        filed)
            case "$OPT_issue" in ''|*[!0-9#]*) die "--issue に issue の番号を渡してください" ;; esac
            record state "$OPT_id" 起票済み "${OPT_issue#\#}"; echo "$OPT_id: 起票済み（#${OPT_issue#\#}）" ;;
        defer)
            [ "$act" = 見送り可 ] || die "$OPT_id の処置は「$act」です。見送れるのは処置が「見送り可」の指摘だけです"
            [ -n "$OPT_reason" ] || die "--reason を渡してください"
            record state "$OPT_id" 見送り "$(clean "$OPT_reason")"; echo "$OPT_id: 見送り" ;;
    esac
}

cmd_report() {
    parse_opts "$@"
    is_role "$OPT_role" || die "--role は $ROLES のどれかです"
    local ids
    if [ -n "$OPT_file" ]; then
        [ -f "$OPT_file" ] || die "報告のファイルがありません: $OPT_file"
        ids=$(grep -E '^[[:space:]]*指摘 ?ID[[:space:]]*[:：]' "$OPT_file" | tail -1 | sed -E 's/^[^:：]*[:：][[:space:]]*//')
        [ -n "$ids" ] || die "報告の末尾に「指摘 ID: <ID>, <ID>」（無ければ「指摘 ID: なし」）の行がありません"
    else
        ids="$OPT_ids"
    fi
    ids=$(printf '%s' "$ids" | sed 's/、/,/g; s/[[:space:]]//g')
    case "$ids" in none|なし) ids="" ;; '') die "--ids か --file を渡してください（指摘が無ければ --ids none）" ;; esac
    local n; n=$(current_round); [ "$n" -gt 0 ] || die "始めたラウンドがありません（round start）"
    record report "$n" "$OPT_role" "$ids"
    echo "ラウンド $n の $OPT_role の報告を記録しました（指摘 ID: ${ids:-なし}）"
}

cmd_derive() {
    parse_opts "$@"
    is_role "$OPT_role" || die "--role は $ROLES のどれかです"
    valid_impact "$OPT_impact" || die "--impact は 致命 / 支障 / 軽微 のどれかです"
    [ "$OPT_role" = security ] || valid_freq "$OPT_frequency" || die "--frequency は 常時 / 条件付き / 稀 のどれかです"
    local d; d=$(derive "$OPT_role" "${OPT_frequency:--}" "$OPT_impact" "$OPT_target")
    IFS="$TAB" read -r kind scope lk act <<EOF
$d
EOF
    echo "種別 $kind / 範囲 $scope / 起こりやすさ $lk / 処置: $act"
}

# ---------------------------------------------------------------------------
# ゲート（PR 作成の前の 3 条件）
# ---------------------------------------------------------------------------
cmd_gate() {
    local problems="" n reviewed h b fixes c parents p ok
    add_problem() { problems="${problems}  - $1"$'\n'; }
    n=$(current_round)
    h=$(head_sha)
    b=$(base_ref)

    # 条件 1: PR の中身がレビューされている
    if [ "$n" -eq 0 ]; then
        add_problem "条件 1: レビューの記録がありません。reviewing-changes の手順でラウンドを回してください"
    else
        reviewed=$(lines round | awk -F'\t' -v n="$n" '$2 == n { print $3 }')
        if ! git -C "$ROOT" merge-base --is-ancestor "$reviewed" "$h" 2>/dev/null; then
            add_problem "条件 1: レビューした時点のコミット（${reviewed:0:12}）が HEAD の祖先ではありません（rebase などで履歴を書き換えた）。もう一度ラウンドを回してください"
        else
            fixes=$(lines state | awk -F'\t' '$3 == "修正済み" { print $4 }')
            for c in $(git -C "$ROOT" rev-list "$reviewed..$h" ${b:+--not "$b"} 2>/dev/null); do
                if printf '%s\n' "$fixes" | grep -qx "$c"; then continue; fi
                parents=$(git -C "$ROOT" rev-list --parents -n 1 "$c" | cut -d' ' -f3-)
                if [ -n "$parents" ] && [ -n "$b" ]; then
                    ok=yes
                    for p in $parents; do git -C "$ROOT" merge-base --is-ancestor "$p" "$b" 2>/dev/null || ok=no; done
                    [ "$ok" = yes ] && continue   # 主ブランチの取り込み
                fi
                add_problem "条件 1: レビューの後のコミット ${c:0:12}（$(git -C "$ROOT" log -1 --format=%s "$c")）は、台帳の修正済みの指摘が指す修正ではありません。fixed で対応づけるか、もう一度ラウンドを回してください"
            done
        fi
        [ -n "$(lines round-end | awk -F'\t' -v n="$n" '$2 == n')" ] || warn "ラウンド $n を終えていません（round end）"
    fi

    # 条件 2: 直すべき指摘が残っていない
    local id act st
    while IFS="$TAB" read -r _ id _ _ _ _ _ _ _ act _; do
        [ -n "$id" ] || continue
        st=$(latest_state "$id" | cut -f1)
        case "$act" in
            直す) [ "$st" = 修正済み ] || add_problem "条件 2: $id は処置が「直す」で、修正済みになっていません（状態: ${st:-未対応}）" ;;
            起票) case "$st" in 起票済み|修正済み) ;; *) add_problem "条件 2: $id は処置が「起票」で、issue がありません（filed --issue <番号>）" ;; esac ;;
        esac
    done <<EOF
$(latest_findings)
EOF

    # 条件 3: 指摘が記録から漏れていない
    local known r role ids i
    known=$( { latest_findings | cut -f2; lines unproven | cut -f2; } | sort -u)
    while IFS="$TAB" read -r _ r role _; do
        [ -n "$r" ] || continue
        [ -n "$(lines report | awk -F'\t' -v r="$r" -v role="$role" '$2 == r && $3 == role')" ] \
            || add_problem "条件 3: ラウンド $r で起動した $role の報告が記録されていません（report --role $role）"
    done <<EOF
$(lines launch)
EOF
    while IFS="$TAB" read -r _ r role ids; do
        [ -n "$r" ] || continue
        for i in $(printf '%s' "$ids" | tr ',' ' '); do
            printf '%s\n' "$known" | grep -qxF -- "$i" \
                || add_problem "条件 3: ラウンド $r の $role の報告にある $i が台帳にありません（add か unproven で記録する）"
        done
    done <<EOF
$(lines report)
EOF

    if [ -n "$problems" ]; then
        echo "review-ledger gate NG: PR を作る前の条件を満たしていません"
        printf '%s' "$problems"
        return 1
    fi
    echo "review-ledger gate OK（ラウンド $n、レビューした時点 ${reviewed:0:12}）"
}

# ---------------------------------------------------------------------------
# 集計
# ---------------------------------------------------------------------------
cmd_summary() {
    parse_opts "$@"
    if [ -z "$LEDGER" ] || [ ! -f "$LEDGER" ]; then
        [ "$OPT_json" = yes ] && echo null || echo "台帳がありません"
        return 0
    fi
    latest_findings | awk -F'\t' -v json="$OPT_json" -v ledger="$LEDGER" '
        BEGIN {
            while ((getline line < ledger) > 0) {
                split(line, f, "\t")
                if (f[1] == "state") st[f[2]] = f[3]
                if (f[1] == "round") { rounds++; ind[f[4]]++ }
                if (f[1] == "unproven") { up[f[4]]++; ups++ }
            }
        }
        { act[$10]++; total++; s = ($2 in st) ? st[$2] : "未対応"; stc[s]++ }
        END {
            indep = (rounds == 0) ? "null" : (ind["yes"] == rounds ? "true" : (ind["no"] == rounds ? "false" : "\"mixed\""))
            if (json == "yes") {
                u = ""; for (k in up) u = u (u == "" ? "" : ",") "\"" k "\":" up[k]
                printf "{\"rounds\":%d,\"independent\":%s,\"findings\":{\"total\":%d,\"fix\":%d,\"file\":%d,\"may_defer\":%d},\"states\":{\"fixed\":%d,\"filed\":%d,\"deferred\":%d,\"open\":%d},\"unproven\":{%s}}\n", \
                    rounds, indep, total, act["直す"], act["起票"], act["見送り可"], stc["修正済み"], stc["起票済み"], stc["見送り"], stc["未対応"], u
            } else {
                printf "ラウンド: %d（独立性: %s）\n", rounds, indep
                printf "指摘: %d 件（直す %d / 起票 %d / 見送り可 %d）\n", total, act["直す"], act["起票"], act["見送り可"]
                printf "状態: 修正済み %d / 起票済み %d / 見送り %d / 未対応 %d\n", stc["修正済み"], stc["起票済み"], stc["見送り"], stc["未対応"]
                printf "実行で確かめられず台帳に載せなかった指摘: %d 件", ups
                if (ups > 0) { printf "（"; sep = ""; for (k in up) { printf "%s%s %d", sep, k, up[k]; sep = " / " } printf "）" }
                printf "\n"
            }
        }'
}

cmd_table() {
    local f s i
    echo "起こりやすさ（頻度 × 範囲）"
    for f in 常時 条件付き 稀; do
        printf '  %-6s' "$f"; for s in 全体 複数 単一; do printf ' %s:%s' "$s" "$(likelihood "$f" "$s")"; done; echo
    done
    echo "処置（種別 × 起こりやすさ × 影響）"
    for k in プロダクト ハーネス; do for l in 高 中 低; do
        printf '  %s %s' "$k" "$l"; for i in 致命 支障 軽微; do printf ' %s:%s' "$i" "$(action "$k" "$l" "$i")"; done; echo
    done; done
    printf '  セキュリティ（頻度は評価しない）'; for i in 致命 支障 軽微; do printf ' %s:%s' "$i" "$(security_action "$i")"; done; echo
}

case "$CMD" in
    plan) cmd_plan ;;
    round) cmd_round ${ARGS[@]+"${ARGS[@]}"} ;;
    report) cmd_report ${ARGS[@]+"${ARGS[@]}"} ;;
    add) cmd_add ${ARGS[@]+"${ARGS[@]}"} ;;
    raise) cmd_raise ${ARGS[@]+"${ARGS[@]}"} ;;
    unproven) cmd_unproven ${ARGS[@]+"${ARGS[@]}"} ;;
    fixed|filed|defer) cmd_state "$CMD" ${ARGS[@]+"${ARGS[@]}"} ;;
    derive) cmd_derive ${ARGS[@]+"${ARGS[@]}"} ;;
    gate) cmd_gate ;;
    summary) cmd_summary ${ARGS[@]+"${ARGS[@]}"} ;;
    table) cmd_table ;;
    *) die "知らないコマンド: $CMD（--help で一覧）" ;;
esac
