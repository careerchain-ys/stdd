# Auto Implement - Phase詳細

各フェーズの詳細な手順。SKILL.mdから参照される。

## Reviewer エージェント運用の前提（必読）

`spec-reviewer` / `test-reviewer` / `code-reviewer` は **独立した Evaluator** として懐疑的にチューニングされている。Team Lead は以下を順守すること:

- **Reviewer の判定は原則そのまま受け入れる**: NEEDS CHANGES / ⚠️ 要修正 / ❌ Blocked を「厳しすぎる」と判断して無視しない。各 Reviewer は Hard Threshold を1項目でも下回ったら必ず NEEDS CHANGES 以下を出すよう設計されている。
- **差し戻し時は Reviewer 出力をそのまま渡す**: Reviewer 出力末尾の「Generator への差し戻し指示」セクションを、対象 Generator（spec-writer / implementer）にそのまま引き渡す。Team Lead が要約・再解釈しない。
- **再レビューは差分のみではなく全体を見させる**: 修正後の Spec/テスト/コード全体を Reviewer に渡し、修正により別の Hard Threshold を割っていないか確認させる。
- **3回ループ超過時**: 後述の各 Phase のループ上限（最大3回）を超えた場合、現状をコミット・push して draft PR を作成する。PR description には **どの Reviewer がどの Hard Threshold で停止させたか** を明記する。

## Phase 1: Spec作成（`full`, `spec-only`のみ）

**Spec Writerに依頼**して、issueの情報をもとにSpecドキュメントを作成する。

1. `docs/` 配下に該当機能のディレクトリを作成（存在しない場合）
2. `REQUIREMENTS.md` を作成:
   - 業務要件（解決する問題・対象ユーザー・ビジネス目標）の整理
   - 機能要件：ユースケースごとに 振る舞い（番号付き手順・主語明示）＋ 受入基準（EARS）＋ Priority を定義
   - 非機能要件（機能固有のもの。共通は common 準拠）の明確化
3. ワイヤーフレーム（WF）を生成（UI を持つ機能の場合）:
   - `generating-wireframes` スキルに従い `docs/<app>/<feature-path>/wireframes/` に HTML WF を生成
   - REQUIREMENTS.md「2.4 UI/UX・画面」から `./wireframes/index.html` にリンク
   - UI を持たない機能（バッチ・API のみ等）はスキップ
4. `TECH_DESIGN.md` を作成:
   - 技術設計方針（概要 / 主要な設計判断 / 処理ロジック / エラーハンドリング戦略）
   - 画面 feature では「画面項目定義」セクションを含める（非画面 feature は省略）
   - データ構造は common `TABLE_DEFINITION.md`、API は common `API_SPEC.md` を参照
5. `TEST_PLAN.md` を作成（テスト戦略・テストケース一覧。feature 単位の独立ドキュメント）

作成したSpecをコミット。

**Spec Reviewerに依頼**して、作成されたSpecをレビューする。

チェック項目:

- 要件の網羅性（issueの要求がすべてカバーされているか）
- 技術設計の実現可能性
- テスト戦略の十分性
- 既存実装との整合性

### 判定と差し戻しループ

Spec Reviewer の **Hard Threshold（SSOT 違反 0件）** を1件でも下回った場合は必ず ⚠️ 要修正 となる。

- **⚠️ 要修正**: Spec Reviewer 出力末尾の「Generator への差し戻し指示」をそのまま spec-writer に渡して修正させ、再度 Spec Reviewer に依頼する。**最大3回**ループ。
- **✅ 承認**: 次の Phase に進む。
- **3回ループ後も未解消**: 現状をコミットして次の Phase に進むが、未解消の指摘は PR description に明記する。

HIGH/MEDIUM の指摘がある場合は Hard Threshold とは別に判断する。Team Lead は HIGH が複数残っていれば実質的に差し戻す方向で扱う。

## Phase 1.5: PLANドキュメント作成（`full`, `impl-only`）

**Plan Writerに依頼**して、Specドキュメントに基づきPLANドキュメントを作成する。

1. REQUIREMENTS.mdのユースケース（振る舞い＋受入基準）とPriorityを確認
2. TEST_PLAN.mdのテスト戦略に基づきタスクを分解
3. テスト→実装の順序でタスクリストを作成
4. ファイル構成（新規/既存修正/既存維持）を明記
5. PLANドキュメントをコミット

配置先: `docs/<app>/<feature-path>/plans/[yyyy-mm-dd].md`

## Phase 2: 実装（`full`, `impl-only`, `quick`）

**Implementerに依頼**して、PLANドキュメント（存在する場合）に従いSTDDフローで実装する。

1. **テスト作成**（`quick`モードではスキップ可）:
   - PLANドキュメントのタスクリストに従いテストを作成（Unit → Integration → E2E）
   - テストが失敗すること（Red状態）を確認
   - テストをコミット

   **`quick`モード以外では、テストをコミットした時点で一旦Phase 2の作業を中断し、Phase 2.5（テストレビュー）に進む**。Phase 2.5で承認されてから次の「実装」ステップに戻る。

2. **実装**:
   - PLANドキュメントのタスクリストに従い実装
   - テストがパスすること（Green状態）を確認
   - 実装をコミット

3. **型チェック**: `.stdd.config.yml` の `commands.typecheck` を実行する。

   ```bash
   # 例（実際の値は .stdd.config.yml に従う）
   <commands.typecheck>
   ```

4. **ビルドエラー解決**（型チェック/ビルドでエラーが発生した場合）:
   **Build Error Resolverに依頼**して、ビルド・型エラーを段階的に修正する。
   - エラーを1つずつ修正し、修正ごとに型チェックを再実行
   - 修正が新たなエラーを生まないことを確認
   - 最大3回の修正ループ後もエラーが残る場合はImplementerに差し戻し

## Phase 2.5: テストレビュー（`full`, `impl-only`のみ）

**Phase 2のステップ1（テスト作成）が完了し、テストがコミットされた直後、ステップ2（実装）を開始する前にこのPhaseを実行する。** 実装前にテスト自体の妥当性を検証することで、誤ったテストに基づく無駄な実装を防ぐ。

### スキップ条件

- `quick`モード（テスト作成自体をスキップしているため）
- PLANドキュメントが存在しない（`impl-only` でPLANを飛ばしたケース等）かつテストコード変更がない場合

### 実行手順

**Test Reviewerに依頼**して、作成されたテストをレビューする。

レビュー観点:

1. **Spec準拠**: TEST_PLAN.mdのテスト戦略（ユースケース別テストレベル分類・テスト総数・内訳）に作成テストが則っているか
2. **形骸的テストの検出**: トートロジー、モック戻り値のassert、内容を検証しないアサーション等、意味のないテストがないか
   - ただしE2EテストでUI要素（role, aria-label, data-testid, 可視テキスト等）に依拠した検証は許容
3. **一般的なテスト品質**: AAA構造、独立性、命名、Flaky耐性、アサーションの具体性

### 判定結果の扱い

Test Reviewer の **Hard Threshold**（HIGH 0件 / MEDIUM ≤2件 / 形骸的テスト 0件 / TEST_PLAN.md整合 / P0 E2E完全カバー / 受入基準テスト網羅）を1項目でも下回った場合は必ず NEEDS CHANGES 以下となる。

- **PASS**: Phase 2のステップ2（実装）に戻って作業を継続。
- **NEEDS CHANGES**: Test Reviewer 出力末尾の「Generator への差し戻し指示」をそのまま implementer に渡してテストを修正させる → テストを再コミット → Test Reviewer に再レビュー依頼。**最大3回**ループ。
- **CRITICAL ISSUES**: Spec の受入基準がまったく検証されていない等の重大な問題。implementer に差し戻し、場合によっては Phase 1 の spec-writer にもテスト戦略の見直しを依頼する。

3回の修正ループ後も問題が解消されない場合は、現状のテストをコミットして Phase 2 のステップ2に進み、未解消の Hard Threshold 違反項目を PR description に明記する。

## Phase 3: QA（`full`, `impl-only`のみ）

**QA Engineerに依頼**して、品質を確認する。

1. **ユニットテスト実行**: `.stdd.config.yml` の `apps[]` を読み、各アプリについて `apps[].path` ディレクトリで `commands.test` を実行する（apps[] の数だけ繰り返す）。

   ```bash
   # 例（実際の値は .stdd.config.yml に従う）
   cd <apps[].path> && <commands.test>
   ```

2. **E2Eテスト実行**（関連テストがある場合）:

   ```bash
   cd e2e && npm run test
   ```

3. **整合性チェック**: `verifying-consistency` skill と同等のチェックを実施

4. **コード品質チェック**: `simplify` skill と同等のレビューを実施

5. **動作確認（Playwright MCP）**: `commands.dev` が定義され UI を持つ場合、dev サーバを起動し Playwright MCP（`mcp__playwright__*`）で主要ユースケースのハッピーパスをブラウザ操作で確認する（主要要素の存在・console エラーなし・画面遷移）。`commands.dev` 未定義 / UIなし / Playwright MCP 利用不可ならスキップする。詳細は QA Engineer の Phase 6 を参照。

問題がある場合:

- **ビルド・型エラー**: Build Error Resolverに修正を依頼
- **テスト失敗・ロジックの問題**: Implementerに修正を依頼
- 修正→QAを最大3回繰り返す

## Phase 4: コードレビュー（`full`, `impl-only`のみ）

**Code Reviewerに依頼**して、コード品質をレビューする。

チェック項目:

- `CLAUDE.md` のコーディング規約準拠（存在する場合のみ。snake_case禁止、!演算子禁止、asキャスト禁止等）
- セキュリティ（OWASP Top 10）
- パフォーマンス
- レスポンシブ対応
- 適切なエラーハンドリング

### 判定と差し戻しループ

Code Reviewer の **Hard Threshold**（Critical 0件 / High 0件 / Medium ≤2件 / OWASP Critical/High 0件 / `CLAUDE.md` 絶対ルール違反 0件（存在する場合のみ評価） / `.claude/docs/coding-conventions.md` 全項目準拠（存在する場合のみ評価））を1項目でも下回った場合は必ず NEEDS CHANGES 以下となる。

- **✅ PASS**: 次の Phase に進む。
- **⚠️ NEEDS CHANGES**: Code Reviewer 出力末尾の「Generator への差し戻し指示」をそのまま implementer に渡して修正させ、再度 Code Reviewer に依頼。**最大3回**ループ。
- **❌ Blocked**: セキュリティ脆弱性が実証可能 or アーキテクチャ崩壊レベル。即座に implementer に最優先で修正を依頼。3回ループで解消しなければ draft PR を作成し、PR description で **Blocked 理由** を明示する。

3回の修正ループ後も問題が解消されない場合は、現状をコミットして次の Phase に進むが、未解消の Hard Threshold 違反項目を PR description に明記する。

## Phase 4.3: ペネトレーションテスト（`full`, `impl-only`のみ）

**このPhaseはPhase 4（コードレビュー）の後に実行する。**

### スキップ条件

変更ファイルがすべて以下に該当する場合はスキップしてPhase 4.5に進む:

- `.md` / `.txt` 等のドキュメントファイルのみ
- `.claude/` 配下の設定・エージェント定義のみ
- CSS/Tailwindクラスのスタイル変更のみ（Server Actions/APIルート/マイグレーションに影響なし）

### 実行手順

**Penetration Testerに依頼**して、攻撃者視点で変更箇所の脆弱性を検証する。

1. **偵察**: 変更されたファイルから攻撃対象領域をマッピング
2. **攻撃シナリオ設計**: 認証バイパス、認可エスカレーション、RLSバイパス、インジェクション、IDOR、ビジネスロジック悪用の観点で攻撃シナリオを設計
3. **エクスプロイト実行**: 稼働中のローカル環境に対して実際に攻撃ペイロードを送信
4. **結果報告**: 実証された脆弱性（PoC付き）と潜在的リスクを報告

### 判定基準

- **SECURE**: 次のPhaseに進む
- **AT RISK**: Medium以上の潜在リスクをImplementerに修正依頼し、修正→再テストを最大3回繰り返す
- **COMPROMISED**: 脆弱性が実証された。Implementerに即座に修正を依頼し、修正→再テストを最大3回繰り返す

### Phase 4.5との関係

Phase 4.3の判定がSECUREまたはAT RISK（修正済み）の場合のみPhase 4.5を実行する。COMPROMISEDが3回の修正ループ後も解消されない場合はPhase 4.5をスキップし、draft PRを作成する。

## Phase 4.5: Figmaデザイン更新（`full`, `impl-only`のみ）

UI変更を伴う実装の場合、対象のSpecドキュメント（REQUIREMENTS.md）に「Figmaデザイン」セクションが存在するかを確認し、存在する場合はFigmaファイルを更新する。

**このPhaseはPhase 4.3（ペネトレーションテスト）完了後に実行する。**

### 実行条件の判定

1. 対象のREQUIREMENTS.mdを読み、`### Figmaデザイン` セクションの有無を確認
2. セクションが存在し、FigmaファイルURLが記載されている場合 → **Figma更新を実行**
3. セクションが存在しない場合 → **スキップ**（Phase 5に進む）

### 更新手順

1. **UIキャプチャ**: Playwright MCPを使用して、変更が反映された画面のスクリーンショットを取得
   - REQUIREMENTS.mdの「Figmaデザイン」セクションに記載された各画面状態をキャプチャ
   - 変更の影響がある画面のみ対象（全画面を再キャプチャする必要はない）
   - ログインが必要な場合はCLAUDE.mdのテストユーザー情報を使用
2. **Figmaファイル更新**: Figma MCPを使用して、キャプチャした画像でFigmaファイルの該当ノードを更新
   - REQUIREMENTS.mdに記載されたnode-idに対応するノードを更新
   - 新しい画面状態が追加された場合は、新しいノードとして追加
3. **REQUIREMENTS.mdのリンク更新**: 新しいノードを追加した場合、Figmaデザインセクションにリンクを追記してコミット

### エラー時の扱い

- Figma MCPが利用できない場合やエラーが発生した場合は**スキップ**してPhase 5に進む
- 完了報告の備考欄にスキップ理由を記載する
- Figma更新の失敗はPR作成をブロックしない

## Phase 5: PR作成（全モード）

すべてのコミットをpushし、`create-pr` skill と同等のフローでPRを作成する。

PRのdescriptionには以下を含める:

- 対応issue番号（`Closes #<issue番号>`）
- 実行モード
- 各フェーズの実行結果サマリ

PR作成後、GitHub Projectのステータスを「In review」に変更する（[references/github-project.md](github-project.md) の手順に従い、option IDに `"df73e18b"` を指定）。
