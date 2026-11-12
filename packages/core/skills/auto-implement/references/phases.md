# Auto Implement - Phase詳細

各フェーズの詳細な手順。SKILL.mdから参照される。

## reviewer の使い方

`requirements-reviewer` / `tech-specs-reviewer` / `test-reviewer` / `code-reviewer` と `qa-engineer` は、メインのセッションとは
別の文脈で起動する。書いた本人とは別の目で、成果物だけを見て判定させるためである。書く作業（Spec・テスト・実装）は
メインのセッションが順に行い、並列にするのはレビューだけである。

| reviewer | 起動する条件 |
| --- | --- |
| `requirements-reviewer` | REQUIREMENTS.md（feature / common）を作成・変更したとき |
| `tech-specs-reviewer` | feature の技術設計・テスト設計（`docs.lineup` の構成のもの）・common の技術文書を作成・変更したとき |
| `test-reviewer` | テストを追加・変更し、実装に入る前（`quick` を除く） |
| `qa-engineer` | 実装・テストを変更したとき |
| `code-reviewer` | 実装のコードを変更したとき（文書だけの変更では起動しない） |

### 起動の仕方（並列が既定）

互いの結果を必要としないレビューは、**既定で同時に起動する**。

| 同時に起動するもの | Phase |
| --- | --- |
| 変更した REQUIREMENTS.md ごと（feature と common） | 1a |
| feature の設計書と、対になるテスト設計の組ごと（対応を見るので組で渡す。`single` は TECH_DESIGN.md + TEST_PLAN.md、`layered` は API_DESIGN.md + API_TEST_DESIGN.md、SCREEN_DESIGN.md + SCREEN_TEST_DESIGN.md、TEST_DESIGN.md + REQUIREMENTS.md）と、変更した common の技術文書ごと | 1b |
| `qa-engineer` と、`code-reviewer` の 3 つの観点（Phase 4「観点を分けた並列レビュー」） | 3・4 |

起動する前に、次のスクリプトで起動の形を決める（1 行目が `teams` か `subagents`、2 行目が理由）。

```bash
# <skill-dir> はこの skill のディレクトリ
bash <skill-dir>/scripts/review-runner.sh
```

- **`teams`**: agent teams で起動する。各メンバーは上の reviewer の agent の定義を使い、名前は agent の名前で始める
  （例: `code-reviewer-security`）。フック `agent-scope-guard.sh` が名前の先頭で reviewer を見分けるためである。
  メインのセッションが取りまとめ役になり、全員の結果がそろうまで次へ進まない。終わったらメンバーを終了させる。
- **`subagents`**: 同じ依頼を、1 回の応答の中で複数の subagent として起動する（Codex、または agent teams が無効な環境）。
- **記録**: 実際にどちらで動いたかを、Step 6 の完了報告と PR description の備考に `レビューの実行: agent teams / subagent` と書く。
  非対話の実行では `teams` と判定してもチームは作られず、通常の subagent として動くので、判定ではなく実際の形を書く。

### 作業ツリーを分ける（`code-reviewer`・`test-reviewer`）

`code-reviewer` と `test-reviewer` は、自分の作業ツリーで失敗するテストや再現のスクリプトを実行して指摘を裏付ける。
レビューされる作業ツリーを書き換えさせないため、別の作業ツリーで起動する。

- **起動**: agent の定義に `isolation: worktree` がある。Agent の呼び出しでも `isolation: "worktree"` を指定する。
- **起動の前にコミットする**: 作られる作業ツリーにはコミットした内容しか入らない。既定では既定のブランチから作られる
  （`worktree.baseRef` が `"head"` のときだけ HEAD から）ので、依頼に対象のコミットの SHA を渡し、reviewer に
  `git checkout --detach <SHA>` で切り替えさせる。
- **起動の前後で確かめる**: 起動の前に、レビューされる作業ツリーの `git status --porcelain` と `git rev-parse HEAD` を控え、
  結果を統合する前に同じものを取り直して一致を確かめる。変わっていたら、その reviewer の結果を使わずに変更を戻して起動し直す
  （フックは分離されたシェルからの絶対パスでの書き込みを防げない。`agent-scope-guard.sh` の冒頭）。
- **High 以上の指摘は再現し直す**: 指摘に書かれた再現のコマンドを、メインのセッションが自分で実行する。再現しない指摘は捨て、
  再現のコマンドが無い High 以上の指摘は「未確認」として扱う（判定の根拠にしない）。
- **分けられないとき**: Codex（`.codex/agents/` に作業ツリーを分ける設定が無い）や、作業ツリーを分けずに動く agent teams の
  メンバーでは、フックが読み取りのみに制限する。そのときの High 以上の指摘は、メインのセッションが再現を試みてから扱う。

`requirements-reviewer`・`tech-specs-reviewer` は文書のレビューなので、作業ツリーを分けず、シェルも持たない。

### 依頼と判定

- **依頼の内容**: 対象のファイル、基準にする Spec のパス、作業ツリーのパス、対象のコミットの SHA を渡す。書いたときの判断の理由は渡さない。
- **判定は原則そのまま受け入れる**: 「厳しすぎる」として NEEDS CHANGES / ⚠️ 要修正 / ❌ Blocked を退けない。退けるときは理由を完了報告に書く。
- **直すのはメインのセッション**: reviewer の出力の末尾の「修正の依頼」に沿って直し、直した後の全体を同じ reviewer にもう一度見せる（差分だけでなく、別の基準を割っていないかを確かめさせる）。
- **3 回で止める**: 各 Phase の差し戻しは最大 3 回。超えたら現状をコミット・push して draft PR を作り、どの reviewer がどの基準で止めたかを PR description に書く。

## 人間レビューゲート（必読）

Spec 工程は reviewer のレビューだけで自動承認せず、**節目で必ずユーザー（人間）の確認を仰ぐ**。`requirements-reviewer` / `tech-specs-reviewer` が ✅ 承認を出しても、それは**人間レビューに進める状態になった**という意味であり、フロー全体の承認ではない。

- **ゲート①（要件）**: Phase 1a で `requirements-reviewer` が ✅ 承認したら、REQUIREMENTS.md の要点をユーザーに提示し、**承認を求めて停止**する。ユーザーが承認するまで Phase 1b に進まない。
- **ゲート②（技術設計）**: Phase 1b で `tech-specs-reviewer` が ✅ 承認したら、TECH_DESIGN.md / TEST_PLAN.md の要点をユーザーに提示し、**承認を求めて停止**する。ユーザーが承認するまで Phase 1.5 に進まない。
- ユーザーから修正指示が出た場合は、メインのセッションが直し、reviewer のレビュー → 人間ゲートを再度通す。
- ユーザーの指示で人間ゲートをスキップする運用（完全自動）も可能だが、**既定は停止して確認**とする。

## 工程の記録（工程テレメトリ）

PR 作成後に投稿する工程テレメトリ（`create-pr` §5）の所要時間とレビュー回数は、メインのセッションが各 Phase の
開始と終了で付ける記録から集計する。`.stdd.config.yml` の `telemetry.enabled` が `false` なら省く。

```bash
# <create-pr> は create-pr skill のディレクトリ
bash <create-pr>/scripts/pr-telemetry.sh mark <step> start   # Phase に入るとき
bash <create-pr>/scripts/pr-telemetry.sh mark <step> end     # Phase を出るとき
```

| Phase | step |
| --- | --- |
| 1a 要件作成 / 1b 技術設計（人間レビューゲートの待ち時間を含む） | `spec` |
| 1.5 PLAN 作成 | `plan` |
| 2 実装のうちテスト作成（Red の確認まで）と 2.5 テストレビュー | `test` |
| 2 実装のうち実装（Green） | `implement` |
| 3 QA | `qa` |
| 4 コードレビュー（**差し戻しの 1 往復ごとに start / end を付ける**。往復の数がレビュー回数になる） | `review` |

- 記録は作業ツリーの外に書かれ、コミットには入らない。記録に失敗しても作業は止めない。
- 記録の無い Phase は「測れない」として集計から外れる（0 分とは扱われない）。

## Phase 1a: 要件作成（`full`, `spec-only`のみ）

要件（What & Why）を確定させるフェーズ。技術設計（Phase 1b）には進まず、まず REQUIREMENTS.md を完成・承認させる。

`documenting-requirements` skill に従い、入力（タスク記述。GitHub issue の場合はその情報、それ以外は Step 1 のヒアリングで確定したタスク記述）をもとに REQUIREMENTS.md を作成する。

1. `docs/` 配下に該当機能のディレクトリを作成（存在しない場合）
2. `REQUIREMENTS.md` を作成:
   - 業務要件（解決する問題・対象ユーザー・ビジネス目標）の整理
   - 機能要件：ユースケースごとに 振る舞い（番号付き手順・主語明示）＋ 受入基準（EARS）＋ Priority を定義
   - 非機能要件（機能固有のもの。共通は common 準拠）の明確化
3. ワイヤーフレーム（WF）を生成（UI を持つ機能の場合）:
   - `generating-wireframes` スキルに従い `docs/<app>/<feature-path>/wireframes/` に HTML WF を生成
   - REQUIREMENTS.md「2.4 UI/UX・画面」から `./wireframes/index.html` にリンク
   - UI を持たない機能（バッチ・API のみ等）はスキップ

作成した REQUIREMENTS.md をコミット。

`requirements-reviewer` を起動して、作成した REQUIREMENTS.md をレビューさせる。

チェック項目:

- 要件の網羅性（入力（タスク記述）の要求がすべてユースケース・受入基準としてカバーされているか）
- 3層構造（業務 → 機能 → 非機能）とユースケース品質（Priority＋振る舞い＋EARS）
- SSOT 準拠（履歴・経緯・issue 言及がないか）
- 既存・common 階層との整合性

### 判定と差し戻しループ（reviewer）

Requirements Reviewer の **Hard Threshold（SSOT 違反 0件）** を1件でも下回った場合は必ず ⚠️ 要修正 となる。

- **⚠️ 要修正**: 出力末尾の「修正の依頼」に沿ってメインのセッションが直し、再度 `requirements-reviewer` に見せる。**最大3回**ループ。
- **✅ 承認**: **人間レビューゲート①**へ進む。
- **3回ループ後も未解消**: 現状をコミットし、未解消の指摘を保持したまま人間レビューゲート①へ進み、ユーザー判断を仰ぐ。

HIGH/MEDIUM の指摘がある場合は Hard Threshold とは別に判断する。HIGH が複数残っていれば実質的に差し戻す方向で扱う。

### 🧑 人間レビューゲート①（要件）

Requirements Reviewer が ✅ 承認したら（または 3回ループ上限に達したら）、**ユーザーに REQUIREMENTS.md の確認を求めて停止する**。

- REQUIREMENTS.md の要点（ユースケース一覧・Priority・主要な受入基準・スコープ外・未解消の指摘があればそれ）を簡潔に提示する
- 「この要件で技術設計に進んでよいか」をユーザーに確認する
- **ユーザーが承認するまで Phase 1b に進まない**
- 修正指示が出たらメインのセッションが直し、`requirements-reviewer` の再レビュー → 本ゲートを再度通す
- ユーザーが明示的に「人間ゲートをスキップして自動で進めてよい」と指示した場合のみ、停止せず Phase 1b に進む

## Phase 1b: 技術設計作成（`full`, `spec-only`のみ）

**人間レビューゲート①で承認された REQUIREMENTS.md を前提**に、技術設計を作成するフェーズ。

`documenting-tech-specs` skill に従い、`.stdd.config.yml` の `docs.lineup` の構成で技術 spec を作成する。
`layered` では skill の writing-procedure §6 の順（API_DESIGN → SCREEN_DESIGN → 層別のテスト設計 → TEST_DESIGN）に書く。
以下は `single` の場合の内容である。このフェーズ以降の TECH_DESIGN.md / TEST_PLAN.md は、`layered` では設計書（API_DESIGN.md / SCREEN_DESIGN.md）
とテスト設計（TEST_DESIGN.md と層別のテスト設計）と読み替える。

1. `TECH_DESIGN.md` を作成:
   - 技術設計方針（概要＋対応ユースケース表 / 主要な設計判断 / ロジック設計 / エラーハンドリング戦略）
   - 画面 feature では「画面項目定義」セクションを含める（非画面 feature は省略）
   - データ構造は common `TABLE_DEFINITION.md`、API は common `API_SPEC.md` を参照（新規テーブル/API が生じたら common 側を更新）
2. `TEST_PLAN.md` を作成（テスト戦略・テストケース一覧。feature 単位の独立ドキュメント）

作成した技術設計をコミット。

`tech-specs-reviewer` を起動して、作成した技術設計をレビューさせる。

チェック項目:

- 要件カバレッジ（REQUIREMENTS の全ユースケースが設計書とテスト計画にマッピングされているか）
- 技術設計の実現可能性・既存/common 階層との整合性
- テスト戦略の十分性（テストレベル分類・総数/内訳・P0 E2E 方針）
- SSOT 準拠（履歴・「統合/集約」フレーミングがないか）

### 判定と差し戻しループ（reviewer）

Tech Specs Reviewer の **Hard Threshold（SSOT 違反 0件 / ユースケースマッピング漏れ 0件 / P0 E2E 方針明記）** を1件でも下回った場合は必ず ⚠️ 要修正 となる。

- **⚠️ 要修正**: 出力末尾の「修正の依頼」に沿ってメインのセッションが直し、再度 `tech-specs-reviewer` に見せる。**最大3回**ループ。
- **✅ 承認**: **人間レビューゲート②**へ進む。
- **3回ループ後も未解消**: 現状をコミットし、未解消の指摘を保持したまま人間レビューゲート②へ進み、ユーザー判断を仰ぐ。

### 🧑 人間レビューゲート②（技術設計）

Tech Specs Reviewer が ✅ 承認したら（または 3回ループ上限に達したら）、**ユーザーに TECH_DESIGN.md / TEST_PLAN.md の確認を求めて停止する**。

- 技術設計の要点（主要な設計判断・ロジック設計の概略・テスト総数と内訳・P0 E2E 方針・未解消の指摘があればそれ）を簡潔に提示する
- 「この技術設計で PLAN 作成・実装に進んでよいか」をユーザーに確認する
- **ユーザーが承認するまで Phase 1.5 に進まない**
- 修正指示が出たらメインのセッションが直し、`tech-specs-reviewer` の再レビュー → 本ゲートを再度通す
- ユーザーが明示的に「人間ゲートをスキップして自動で進めてよい」と指示した場合のみ、停止せず Phase 1.5 に進む

## Phase 1.5: PLANドキュメント作成（`full`, `impl-only`）

`documenting-plans` skill に従い、Specドキュメントに基づきPLANドキュメントを作成する。
`.stdd.config.yml` に `docs.layout.plan` が無いプロジェクトは PLAN を作らない体系なので、本 Phase を SKIP して Phase 2 に進む。

1. REQUIREMENTS.mdのユースケース（振る舞い＋受入基準）とPriorityを確認し、スコープを決める（`full`: P0 と P1、P2 は任意 / `impl-only`: TEST_PLAN.md の全範囲）
2. TEST_PLAN.mdのテスト戦略に基づきタスクを分解
3. テスト→実装の順序でタスクリストを作成
4. ファイル構成（新規/既存修正/既存維持）を明記
5. PLANドキュメントをコミット

配置先: `docs.layout.plan` のパステンプレート（中立例: `docs/<app>/<feature-path>/plans/[yyyy-mm-dd].md`）

## Phase 2: 実装（`full`, `impl-only`, `quick`）

[implementation.md](implementation.md) の手順で、PLANドキュメント（存在する場合）に従いメインのセッションが実装する。

1. **テスト作成（Red）**（`quick`モードではスキップ可）: テストを書き、書いたテストだけを実行して失敗を確かめ、コミットする。
   **`quick`モード以外では、ここで Phase 2.5（テストレビュー）に進み**、承認されてから実装に戻る。
2. **実装（Green）**: 対象のテストを通す実装をし、`commands.typecheck` を通してコミットする。ビルド・型のエラーもここで直す。

## Phase 2.5: テストレビュー（`full`, `impl-only`のみ）

**Phase 2のステップ1（テスト作成）が完了し、テストがコミットされた直後、ステップ2（実装）を開始する前にこのPhaseを実行する。** 実装前にテスト自体の妥当性を検証することで、誤ったテストに基づく無駄な実装を防ぐ。

### スキップ条件

- `quick`モード（テスト作成自体をスキップしているため）
- PLANドキュメントが存在しない（`impl-only` でPLANを飛ばしたケース等）かつテストコード変更がない場合

### 実行手順

`test-reviewer` を、作業ツリーを分けて起動し（「reviewer の使い方」の「作業ツリーを分ける」）、作成したテストをレビューさせる。`docs.lineup: layered` では、テスト計画として TEST_DESIGN.md と層別のテスト設計のパスを渡す。

レビュー観点:

1. **Spec準拠**: TEST_PLAN.mdのテスト戦略（ユースケース別テストレベル分類・テスト総数・内訳）に作成テストが則っているか
2. **形骸的テストの検出**: トートロジー、モック戻り値のassert、内容を検証しないアサーション等、意味のないテストがないか
   - ただしE2EテストでUI要素（role, aria-label, data-testid, 可視テキスト等）に依拠した検証は許容
3. **一般的なテスト品質**: AAA構造、独立性、命名、Flaky耐性、アサーションの具体性

### 判定結果の扱い

Test Reviewer の **Hard Threshold**（HIGH 0件 / MEDIUM ≤2件 / 形骸的テスト 0件 / TEST_PLAN.md整合 / P0 E2E完全カバー / 受入基準テスト網羅）を1項目でも下回った場合は必ず NEEDS CHANGES 以下となる。

- **PASS**: Phase 2のステップ2（実装）に戻って作業を継続。
- **NEEDS CHANGES**: 出力末尾の「修正の依頼」に沿ってメインのセッションがテストを直す → 再コミット → `test-reviewer` に再レビューさせる。**最大3回**ループ。
- **CRITICAL ISSUES**: Spec の受入基準がまったく検証されていない等の重大な問題。テストを直し、必要なら TEST_PLAN.md（Phase 1b）や受入基準（Phase 1a）に戻って見直す。

3回の修正ループ後も問題が解消されない場合は、現状のテストをコミットして Phase 2 のステップ2に進み、未解消の Hard Threshold 違反項目を PR description に明記する。

## Phase 3: QA（`full`, `impl-only`のみ）

`qa-engineer` を起動して、品質を確認させる。全件のテストや監査の長い出力は qa-engineer の中で読み、結果の要約だけを受け取る。
PASS の根拠は、qa-engineer が実行して得た結果に限る（レポートの「実行した」と「推測」を分けて読む）。

1. **ユニットテスト実行**: `.stdd.config.yml` の `apps[]` を読み、各アプリについて `apps[].path` ディレクトリで `commands.test` を実行する（apps[] の数だけ繰り返す）。

   ```bash
   # 例（実際の値は .stdd.config.yml に従う）
   cd <apps[].path> && <commands.test>
   ```

2. **E2Eテスト実行**（関連テストがある場合）:

   ```bash
   cd e2e && npm run test
   ```

3. **整合性チェック**: `verifying-consistency` skill と同等のチェックを実施。特に **ID ベース・トレーサビリティ監査**（`bash .claude/hooks/trace-audit.sh`）で要件⇄設計⇄テスト⇄実装の抜け漏れを機械検知し、テスト/実装起点の変更は `--changed` で影響範囲・追跡不能変更を確認する（`traceability.enforce=block` なら抜け漏れは修正必須）

4. **コード品質チェック**: `simplify` skill と同等のレビューを実施

5. **動作確認（Playwright MCP）**: `commands.dev` が定義され UI を持つ場合、dev サーバを起動し Playwright MCP（`mcp__playwright__*`）で主要ユースケースのハッピーパスをブラウザ操作で確認する（主要要素の存在・console エラーなし・画面遷移）。`commands.dev` 未定義 / UIなし / Playwright MCP 利用不可ならスキップする。詳細は QA Engineer の Phase 6 を参照。

問題がある場合:

- ビルド・型のエラー、テストの失敗、ロジックの問題は、メインのセッションが直す
- 修正→QAを最大3回繰り返す

## Phase 4: コードレビュー（`full`, `impl-only`のみ）

`code-reviewer` を、作業ツリーを分けて起動し（「reviewer の使い方」の「作業ツリーを分ける」）、コード品質をレビューさせる。Phase 3 と互いに独立しているので、Phase 3 の `qa-engineer` と同時に起動する。

### 観点を分けた並列レビュー

1 体の reviewer は、一度に 1 種類の問題に注意が偏りやすい。そこで `code-reviewer` は、変更の大きさにかかわらず、
次の 3 つの観点に分けて同時に起動する（起動の形は「reviewer の使い方」の「起動の仕方」）。

| 観点 | 見る範囲 |
| --- | --- |
| セキュリティ | OWASP Top 10、認証・認可、入力の検証、秘密情報の扱い |
| 性能とエラー処理 | 不要な繰り返しやデータの取得、エラーハンドリング |
| 規約と品質 | `AGENTS.md` / `CLAUDE.md` の規約、責務の分け方、フォーム・レスポンシブ（UI の変更時） |

- 依頼文で観点を 1 つだけ渡し、ほかの観点は見ないよう伝える。観点が重ならないようにするためである。
- 結果はメインのセッションが統合する。判定は観点ごとの判定のうち最も悪いものとし、同じ箇所への指摘はまとめる。
- 差し戻しの後は、NEEDS CHANGES 以下だった観点をもう一度起動する。
- agent teams で起動したときは、メンバーどうしで同じ箇所への指摘を確かめ合わせてよい。

チェック項目:

- `AGENTS.md / CLAUDE.md` のコーディング規約準拠（存在する場合のみ。snake_case禁止、!演算子禁止、asキャスト禁止等）
- セキュリティ（OWASP Top 10）
- パフォーマンス
- レスポンシブ対応
- 適切なエラーハンドリング

### 既存の機能を改修したとき

既存のコード（このブランチより前からあるファイル）の振る舞いを変えたときは、Phase 3・4 と同時に、メインのセッションが
`assessing-change-impact` で差分の外の壊れ方を確かめる。次のどれかに当たるときに使う。

- 公開している関数・API・型・テーブルの形、既定値、例外の型、呼ばれる順序を変えた
- 複数の機能から使われている共通の部品を変えた
- ライブラリの更新、設定、実行のタイミング（非同期・キャッシュ・トランザクション）に関わる変更をした

確かめた結果（確信の段階）は PR description に書き、確かめたスクリプトをテストとして残したときは Phase 3 の QA に含める。
新しいファイルだけの追加や、文書だけの変更では使わない。

### 判定と差し戻しループ

Code Reviewer の **Hard Threshold**（Critical 0件 / High 0件 / Medium ≤2件 / OWASP Critical/High 0件 / `AGENTS.md / CLAUDE.md` 絶対ルール違反 0件（存在する場合のみ評価） / `.claude/docs/coding-conventions.md` 全項目準拠（存在する場合のみ評価））を1項目でも下回った場合は必ず NEEDS CHANGES 以下となる。

- **✅ PASS**: 次の Phase に進む。
- **⚠️ NEEDS CHANGES**: 出力末尾の「修正の依頼」に沿ってメインのセッションが直し、再度 `code-reviewer` に見せる。**最大3回**ループ。
- **❌ Blocked**: セキュリティ脆弱性が実証可能 or アーキテクチャ崩壊レベル。最優先で直す。3回ループで解消しなければ draft PR を作成し、PR description で **Blocked 理由** を明示する。

3回の修正ループ後も問題が解消されない場合は、現状をコミットして次の Phase に進むが、未解消の Hard Threshold 違反項目を PR description に明記する。

## Phase 4.5: Figmaデザイン更新（`full`, `impl-only`のみ）

UI変更を伴う実装の場合、対象のSpecドキュメント（REQUIREMENTS.md）に「Figmaデザイン」セクションが存在するかを確認し、存在する場合はFigmaファイルを更新する。

### 実行条件の判定

1. 対象のREQUIREMENTS.mdを読み、`### Figmaデザイン` セクションの有無を確認
2. セクションが存在し、FigmaファイルURLが記載されている場合 → **Figma更新を実行**
3. セクションが存在しない場合 → **スキップ**（Phase 5に進む）

### 更新手順

1. **UIキャプチャ**: Playwright MCPを使用して、変更が反映された画面のスクリーンショットを取得
   - REQUIREMENTS.mdの「Figmaデザイン」セクションに記載された各画面状態をキャプチャ
   - 変更の影響がある画面のみ対象（全画面を再キャプチャする必要はない）
   - ログインが必要な場合はAGENTS.md / CLAUDE.mdのテストユーザー情報を使用
2. **Figmaファイル更新**: Figma MCPを使用して、キャプチャした画像でFigmaファイルの該当ノードを更新
   - REQUIREMENTS.mdに記載されたnode-idに対応するノードを更新
   - 新しい画面状態が追加された場合は、新しいノードとして追加
3. **REQUIREMENTS.mdのリンク更新**: 新しいノードを追加した場合、Figmaデザインセクションにリンクを追記してコミット

### エラー時の扱い

- Figma MCPが利用できない場合やエラーが発生した場合は**スキップ**してPhase 5に進む
- 完了報告の備考欄にスキップ理由を記載する
- Figma更新の失敗はPR作成をブロックしない

## Phase 4.8: フィードバックの棚卸し（全モード）

**レビューを終えたあと、PR を作る前に** `recording-dev-feedback` skill を実行し、この作業中に生じたプロセス上の課題
（ユーザーからの訂正、繰り返した手戻り、その場しのぎの判断、検査で拾えたはずの欠陥）を起票する。
`.stdd.config.yml` の `feedback.enabled` が `false` なら省く。緊急モードのブランチでも省く（`choosing-work-mode` §3）。

- 各 reviewer の完了報告に書かれた「気づき」もここで拾う。subagent には起票させない。
- 起票は 1 PR あたりの上限（既定 5 件）まで。上限で起票しなかった件数も `triage --skipped` で記録する（0 件でも実行する）。
- 対象機能の Spec の誤りや実装のバグは起票せず、この PR の中で直す。
- 起票の失敗（`gh` が使えない等）は PR 作成をブロックしない。完了報告の備考に理由を書く。

## Phase 5: PR作成（全モード）

すべてのコミットをpushし、`create-pr` skill と同等のフローでPRを作成する。

PRのdescriptionには以下を含める:

- 対応issue番号（`Closes #<issue番号>`）。**GitHub issue 起点のときのみ**。issue 以外の入力では、代わりに対象タスクのサマリを記載する。Phase 4.8 で起票した issue には `Closes` を付けない。
- 実行モード
- 各フェーズの実行結果サマリ
- 備考に、Phase 4.8 の `triage` が出力した「開発フィードバック: …」の 1 行と、`レビューの実行: agent teams / subagent` の 1 行
- 緊急モードのブランチでは、冒頭に「## 緊急モード」の節（`create-pr` の Description テンプレート）

PR を作成したら、`create-pr` §5 のとおり工程テレメトリを投稿する。`quick` / `spec-only` モードのようにコードレビューを
行わなかった場合は、レビュー回数が 0 になるので、理由の区分を `--exempt` で申告する（ユーザーがモードを承認した場合は `user_waived`）。
緊急モードのブランチでは、レビューをしたかどうかに関わらず `--exempt emergency` で投稿する。
