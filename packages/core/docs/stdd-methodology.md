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

Spec は、用途による 2 種別（要件 spec / 技術 spec (tech_specs)）と、適用範囲による 2 階層（common / feature）で整理される。階層は 2.0、種別は 2.1〜2.2 で述べる。

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

### 2.1 要件 spec (REQUIREMENTS.md)

「何を・なぜ作るか」をユーザー視点で記述する。解決する問題・対象ユーザー・ビジネス目標、Priority (P0 / P1 / P2) 付きの User Journey、UI / UX、成功基準など。

読者: ステークホルダー、PM、デザイナー、エンジニア

### 2.2 技術 spec (tech_specs)

「どう作るか」を技術視点で記述する設計書の総称。次のファイルで構成される。

- `ARCHITECTURE.md` — システム全体の構成・スタック・連携（common）
- `TECH_DESIGN.md` — 機能単位の技術設計：概要・設計判断・画面項目定義・ロジック設計・エラーハンドリング（feature）
- `TABLE_DEFINITION.md` — 全テーブル定義（common）
- `API_SPEC.md` — API 契約（common）
- `TEST_PLAN.md` — テスト戦略：どのユースケースをどのテストレベルで担保するか（feature）
- `DESIGN.md` — デザイン標準（common・任意）

読者: エンジニア、AI エージェント、アーキテクト

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

---

## 6. ベストプラクティス

- 仕様レビューを最優先する。実装前に Spec を凍結し、後工程の手戻りを最小化する
- セッション開始時にスコープを確認する。大きな機能は複数の PLAN に分割する

---

## 7. 関連ドキュメント

- `workflow-diagram.md` — 各フローを Mermaid で図示
- `guide-for-existing-project.md` — 既存プロジェクトへの STDD 導入手順（遡行ブートストラップ → 順行運用）
- `guide-for-new-project.md` — 新規プロジェクトの STDD 立ち上げ手順（最初から順行）
- `.claude/skills/documenting-specifications/templates/` — spec テンプレ（feature: `requirements.md` / `tech-design.md` / `test-plan.md`、common: `architecture-common.md` / `table-definition-common.md` / `api-spec-common.md` / `requirements-common.md` / `design-common.md`）
- `.claude/skills/documenting-plans/templates/plan.md` — 実装計画テンプレ
- `../schema/.stdd.config.schema.json` — プロジェクト設定の JSON Schema
