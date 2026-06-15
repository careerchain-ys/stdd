# STDD (Spec and Test Driven Development) — 方法論ガイド

## 1. STDD とは

### 1.1 定義

- 仕様を先に定義し、その仕様に基づいてテストを作成し、テストを通すために実装する開発手法
- 仕様ドキュメントは常に最新の SSoT (Single Source of Truth) として維持される

```
仕様 (Spec) → テスト (Test) → 実装 (Implementation) → 検証 (Verification)
        ↑                                                 │
        └─────────────────  仕様は常に最新 ←──────────────┘
```

### 1.2 AI エージェントとの協働

STDD は AI エージェント (Claude Code 等) との協働を前提に設計されている。役割分担は次のとおり。

- 人間は「何を作るか (What)」を Spec に固定する
- AI は「どう作るか (How)」をテストと実装で実現する

仕様が正確でありさえすれば、AI はそれを唯一の入力として、Test Strategy に沿ったテスト作成から実装まで行える。人間は仕様の正確さに集中すればよい。

### 1.3 3 つの成果物の役割

3 つの成果物は、それぞれ次の役割を担い、相互に整合し続ける。

- Spec: ビジネス要件の SSoT。常に最新の「What / Why」を保持する
- テスト: 仕様の実行可能な証明。Spec の要求を機械的に検証できる形に落とす
- 実装: テストを通すための手段。テストが緑になることで仕様の充足を証明する

---

## 2. Spec ドキュメントの構成

### 2.0 Spec の 2 階層構造 (common / feature)

Spec は、プロジェクト全体を見る common 階層と、機能単位を見る feature 階層の 2 つに分かれる。テーブル定義や API 仕様のような横断的な要素は common に集約し、feature 側はそれを参照する。

| 階層    | ドキュメント                                                                                                                                            | 配置例                  |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| common  | `REQUIREMENTS.md`（業務要件）/ `ARCHITECTURE.md`（システム概要）/ `TABLE_DEFINITION.md`（テーブル定義）/ `API_SPEC.md`（API 仕様）/ `DESIGN.md`（任意） | `docs/common/`          |
| feature | `REQUIREMENTS.md` / `TECH_DESIGN.md` / `TEST_PLAN.md`                                                                                                   | `docs/<app>/<feature>/` |

common 階層の役割は次のとおり。

- サービスの目的・アクター・アプリ構成 (REQUIREMENTS) を記述する
- システム概要として構成・スタック・連携・セキュリティ・インフラ (ARCHITECTURE) を記述する
- 複数の feature が前提とする横断的な文脈を一箇所に集約する SSoT として機能する

feature 階層の役割は次のとおり。

- 個々の機能の要件 (REQUIREMENTS)・技術設計 (TECH_DESIGN)・テスト戦略 (TEST_PLAN) を記述する

命名と配置の補足。

- 配置は `.stdd.config.yml` の `docs.layout.common_*` で設定する（任意。common 階層を使わないプロジェクトでは省略可）
- テンプレートは `.claude/skills/documenting-specifications/templates/` を参照する（`requirements-common.md` / `architecture-common.md` / `table-definition-common.md` / `api-spec-common.md` / `design-common.md`）

以下 2.1〜2.3 では、feature 階層の各ファイルの中身を述べる。

### 2.1 REQUIREMENTS.md (ビジネス要件 / ユーザー視点)

記述する内容は次のとおり。

- 解決する問題、対象ユーザー、ビジネス目標
- すべての User Journey（正常系、エラーケース、エッジケース）
- 各 Journey への Priority (P0 / P1 / P2) の付与
- UI / UX デザイン（HTML ワイヤーフレームへのリンク、表示要素）
- 成功基準、スコープ外

読者: ステークホルダー、PM、デザイナー、エンジニア

### 2.2 TECH_DESIGN.md (技術設計 / 内部仕様)

章構成は、概要 / 主要な設計判断（任意）/ 画面項目定義（画面 feature は必須）/ ロジック設計（コア）/ エラーハンドリング戦略 / 非機能要件（任意）。各章の内容は次のとおり。

- 概要: 機能の目的・スコープ・参照する common のテーブルや API
- 主要な設計判断（選択と理由）: この機能特有の判断のみ
- 画面項目定義: UI × バリデーション × DB マッピング（DB カラムは `TABLE_DEFINITION.md` を参照）
- ロジック設計: 集計式・変換・ドメインルール・トランザクション境界・複数テーブル横断の流れ（手順 / 擬似コード）
- エラーハンドリング戦略: API や処理の失敗を本機能がどう捌くか
- 非機能要件: REQUIREMENTS に記載がある場合のみ、その実現方法

データ構造 (`TABLE_DEFINITION.md`)・API 契約 (`API_SPEC.md`)・テスト戦略 (`TEST_PLAN.md`) は別ファイルに持ち、ここでは参照のみとする（再定義しない）。

読者: エンジニア、AI エージェント、アーキテクト

### 2.2.1 TEST_PLAN.md (テスト戦略)

記述する内容は次のとおり。

- REQUIREMENTS.md の全ユースケースを E2E / Integration / Unit のどれでカバーするかの対応表（根拠つき）
- TECH_DESIGN.md のロジック設計に「その他処理フロー」がある場合、それも対応表でカバー
- テスト総数と内訳

### 2.2.2 REQUIREMENTS.md と TECH_DESIGN.md の違い

| 項目 | REQUIREMENTS.md                  | TECH_DESIGN.md                                         |
| ---- | -------------------------------- | ------------------------------------------------------ |
| 視点 | ユーザー視点 (What & Why)        | 技術視点 (How)                                         |
| 読者 | ステークホルダー、PM、デザイナー | エンジニア、アーキテクト、AI エージェント              |
| 内容 | ユーザージャーニー、ビジネス目標 | 画面項目・ロジック設計・エラーハンドリング・非機能要件 |

### 2.3 含めないもの (両方共通)

- 「実装済み」「実装中」などの進捗ステータス（Spec は常に最新の仕様のみを保持する）
- 関数やコンポーネントの具体的な実装コード（型定義 / API 定義 / バリデーションルールは可）
- チェックボックス形式の TODO（これは PLAN ドキュメントに記載する）

---

## 3. PLAN ドキュメント

Spec が「常に最新の仕様」を保持するのに対し、PLAN は「1 セッション分の作業計画」を保持する。

PLAN の扱い方は次のとおり。

- セッション開始時に作成し、スコープをユーザーやレビュアーと合意する
- Test Strategy に沿って「テスト作成 → 実装 → 検証」のタスクを並べる
- 進捗ステータス (`- [x]`) を保持してよい
- セッション中の決定事項、注意点、引き継ぎを書き留める

配置パスは `.stdd.config.yml` の `docs.layout.plan` で設定する。デフォルト例は `docs/<app>/<feature_path>/plans/<yyyy-mm-dd>.md`。

---

## 4. テスト戦略

### 4.1 テストレベル

| レベル      | 対象                                        | 目的                                   |
| ----------- | ------------------------------------------- | -------------------------------------- |
| E2E         | 機能 (feature) またはページ (page) 単位     | Critical Paths のみ                    |
| Integration | ページ以下のコンポーネント / モジュール統合 | エラーケース、コンポーネント間結合     |
| Unit        | 関数 / メソッド単体                         | 詳細ロジック、バリデーション、純粋関数 |

### 4.2 Priority と推奨テスト構成

| Priority | 定義                                                                                                 | 推奨テスト構成                                     |
| -------- | ---------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| P0       | Critical Path<br>ビジネス直結、頻度が非常に高い、複数システム統合、データ損失 / セキュリティに関わる | E2E 必須 + Integration + Unit                      |
| P1       | Important<br>重要だが Critical ではない、頻度が高い、エラーケースの大半                              | E2E 検討（複雑さ・コストで判断）+ Integration 必須 |
| P2       | Nice to Have<br>エッジケース、頻度が低い、UX 改善                                                    | E2E 不要 + Integration 検討 + Unit                 |

### 4.3 「E2E は P0 のみ」の原則

- E2E は実行コストもメンテナンスコストも高い
- すべての Journey を E2E で網羅すると、テストが壊れやすくなり、CI が長時間化する
- P0 のフローのみ E2E で守り、それ以外は Integration / Unit に役割を譲る

### 4.4 エラーケースも Journey として記述する

- エラーは「その他」ではなく、正規の User Journey として REQUIREMENTS.md に書く
- こうすることで、エラー時の挙動（メッセージ・回復導線）が暗黙仕様にならず、テストにマッピングできる

---

## 5. 開発フロー

### 5.1 新機能開発

```
1. REQUIREMENTS.md 作成 (Journey と Priority を網羅)
        ↓
2. ワイヤーフレーム生成 (HTML / 低忠実度。UI を持つ機能のみ)
        ↓
3. ステークホルダーレビュー
        ↓
4. TECH_DESIGN.md 作成 (ロジック設計等) + TEST_PLAN.md 作成 (Test Strategy)
        ↓
5. アーキテクトレビュー
        ↓
6. PLAN ドキュメント作成 (今セッションのスコープ合意)
        ↓
7. テスト作成 (Red) — Unit → Integration → E2E の順
        ↓
8. 実装 (Green) — テストを通す最小限の実装
        ↓
9. リファクタ (必要に応じて)
        ↓
10. テスト全件パス確認
        ↓
11. PR 作成 → レビュー → マージ
```

### 5.2 既存機能への追加 / 変更

```
1. PLAN ドキュメント作成 (Spec 更新タスクを含める)
        ↓
2. REQUIREMENTS.md 更新 (Journey 追加 / 変更 + Priority)
        ↓
3. ステークホルダーレビュー
        ↓
4. TECH_DESIGN.md / TEST_PLAN.md 更新 (テーブル・API 変更は common にも反映)
        ↓
5. アーキテクトレビュー
        ↓
6. PLAN ドキュメント更新 (タスク詳細を Test Strategy に基づき確定)
        ↓
7. テスト作成・更新 (Red) → 実装 (Green) → 検証 → PR
```

Mermaid 図は `workflow-diagram.md` を参照。

### 5.3 PR レビュー観点

PR 作成時は、CI が通っていること、PR description に仕様ドキュメントへのリンクがあることを確認する。レビュアーは次を確認してから承認・マージする。

- REQUIREMENTS.md の要件を満たしているか
- TECH_DESIGN.md の設計に従っているか
- Test Strategy に従ってテストが書かれているか
- すべてのテストが通っているか
- コード品質（可読性、保守性）

---

## 6. Red 状態を必ず確認する

テスト作成後、実装を入れる前に必ずテストを実行して Red（失敗）を確認する。

```
$ {{commands.test}} -- <test-file>
# 期待: FAIL (実装がないため失敗) → 正常
# 異常: PASS (テストが何もチェックしていない)
```

これは、テストが実装の振る舞いを実際に観察できている（最初から通ってしまう空テストではない）ことを保証するため。最初から PASS する場合はテストが何もチェックしていないので、アサーションを強化するか、モックの粒度を見直す。

なお `{{commands.test}}` は `.stdd.config.yml` の `commands.test` で定義されたコマンドを指す。

---

## 7. ベストプラクティス

- 仕様レビューを最優先する。実装前に Spec を凍結し、後工程の手戻りを最小化する
- E2E は P0 のみとし、安易に増やさない（4.3 参照）
- エラーケースも Journey として記述する（4.4 参照）
- Test Strategy を TEST_PLAN.md で明示する。各ユースケースにどのテストレベルを充てるか、その理由とともに表で示す
- ドキュメントは実装ディレクトリに対応させる。`docs.layout` で定義したパターンに従い、機械的に対応関係を保つ
- セッション開始時にスコープを確認する。大きな機能は複数の PLAN に分割する
- Spec に進捗ステータスを書かない。「実装済み」「対応中」のような時系列情報は PLAN とコミット履歴に任せる

---

## 8. 関連ドキュメント

- `workflow-diagram.md` — 各フローを Mermaid で図示
- `guide-for-existing-project.md` — 既存プロジェクトへの STDD 導入手順（遡行ブートストラップ → 順行運用）
- `guide-for-new-project.md` — 新規プロジェクトの STDD 立ち上げ手順（最初から順行）
- `.claude/skills/documenting-specifications/templates/` — spec テンプレ（feature: `requirements.md` / `tech-design.md` / `test-plan.md`、common: `architecture-common.md` / `table-definition-common.md` / `api-spec-common.md` / `requirements-common.md` / `design-common.md`）
- `.claude/skills/documenting-plans/templates/plan.md` — 実装計画テンプレ
- `../schema/.stdd.config.schema.json` — プロジェクト設定の JSON Schema
