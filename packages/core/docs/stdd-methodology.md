# STDD (Spec and Test Driven Development) — 方法論ガイド

## 1. STDD とは

> 仕様を先に定義し、その仕様に基づいてテストを作成し、それを通すために実装を行う開発手法。
> 仕様ドキュメントは常に最新の SSoT (Single Source of Truth) として維持される。

```
仕様 (Spec) → テスト (Test) → 実装 (Implementation) → 検証 (Verification)
        ↑                                                 │
        └─────────────────  仕様は常に最新 ←──────────────┘
```

STDD は AI エージェント (Claude Code 等) との協働を前提に設計されている。
人間は「何を作るか (What)」を Spec に固定し、AI は「どう作るか (How)」をテストと実装で実現する役割分担を取る。

3 つの成果物は、それぞれ次の役割を担い、相互に整合し続ける:

- **Spec = ビジネス要件の SSoT (Single Source of Truth)** — 常に最新の「What / Why」を保持する
- **テスト = 仕様の実行可能な証明** — Spec の要求を機械的に検証可能な形に落とす
- **実装 = テストを通すための手段** — テストが緑になることで仕様充足を証明する

```
REQUIREMENTS.md (What & Why)
        ↓  Test Strategy で対応を明示
テスト (E2E / Integration / Unit)
        ↓  テストを通すために実装
実装 (Implementation)
        ↓  仕様を満たすことを証明
テスト全件パス ✅
```

---

## 2. なぜ TDD でなく STDD なのか

TDD (Test-Driven Development) は「テスト → 実装」の 2 段で十分に機能する開発フローだが、
以下のギャップが残る:

1. **テストはユーザー要件を語らない**。テストは「実装の正しさ」を保証するが、「なぜこの機能が必要か」「誰が、どんな手順で使うか」までは伝えない。
2. **ステークホルダーがテストを読めない**。PM・デザイナー・プロダクトオーナーは TypeScript / Python のテストコードを直接レビューできない。
3. **AI エージェントは要件の抽象度を必要とする**。テストだけ与えられても、AI は「テストの裏にある意図」を取り違えてエッジケースを欠落させる。

STDD は TDD の前に **Spec フェーズ** を追加することで、これらを補う。

| ステージ | TDD                               | STDD                                         |
| -------- | --------------------------------- | -------------------------------------------- |
| 1        | (なし)                            | Spec (REQUIREMENTS.md + TECH_DESIGN.md) を書く |
| 2        | テストを書く (Red)                | Spec を読んでテストを書く (Red)              |
| 3        | テストを通す実装を書く (Green)    | 同じ (Green)                                 |
| 4        | リファクタ                        | 同じ                                         |

---

## 3. Spec ドキュメントの構成

### 3.0 Spec の 2 ティア構造 (common / feature)

Spec は **プロジェクト全体 (common ティア)** と **機能単位 (feature ティア)** の 2 つの高度を持つ。
どちらも「What/Why = REQUIREMENTS」「How = 技術設計」という同じ二項構造を、異なる高度で繰り返す。

| ティア      | What / Why                | How                          | 配置例                                                    |
| ----------- | ------------------------- | ---------------------------- | --------------------------------------------------------- |
| **common**  | `REQUIREMENTS.md` (全体版) | `ARCHITECTURE.md` (全体版)    | `docs/common/REQUIREMENTS.md` / `ARCHITECTURE.md`         |
| **feature** | `REQUIREMENTS.md`         | `TECH_DESIGN.md`             | `docs/<app>/<feature>/REQUIREMENTS.md` / `TECH_DESIGN.md` |

- **common ティア**は、サービスの目的・登場アクター・アプリ構成 (REQUIREMENTS) と、システム構成・リポジトリ構成・レイヤ規約・データモデル (ARCHITECTURE) を俯瞰する正典。複数 feature が前提とする横断的な文脈を一箇所に集約する。
- **feature ティア**は、個々の機能のユーザージャーニーと技術設計・テスト戦略を記述する。common ティアを**下方参照**する側であり、common と矛盾しないこと。
- 全体版の技術設計を `TECH_DESIGN.md` ではなく `ARCHITECTURE.md` と呼ぶのは、システム全体 (ARCHITECTURE) と機能単位 (TECH_DESIGN) を名前で区別するため。
- 配置は `.stdd.config.yml` の `docs.layout.common_requirements` / `docs.layout.common_architecture` で設定する (任意。common ティアを使わないプロジェクトでは省略可)。
- テンプレートは `packages/core/templates/common/REQUIREMENTS.md` / `ARCHITECTURE.md` を参照する。

以下 3.1〜3.3 は **feature ティア**の各ファイルの中身を述べる。

### 3.1 REQUIREMENTS.md (ビジネス要件 / ユーザー視点)

- 解決する問題、対象ユーザー、ビジネス目標
- すべての User Journey (正常系、エラーケース、エッジケース)
- 各 Journey に Priority (P0 / P1 / P2) を付与
- UI / UX デザイン (HTML ワイヤーフレームへのリンク、表示要素、空状態 / エラー状態。WF は `generating-wireframes` スキルで生成)
- 成功基準、スコープ外

**読者**: ステークホルダー、PM、デザイナー、エンジニア

### 3.2 TECH_DESIGN.md (技術設計 / 内部仕様)

- 機能固有のアーキテクチャとデータフロー
- 主要な設計判断 (選択 + 理由)
- データモデル (ER 図 / 型定義 / バリデーションルール)
- API 設計 (エンドポイント / Request-Response 型 / ビジネスロジック概要)
- **Test Strategy**: REQUIREMENTS.md の全 Journey を E2E / Integration / Unit のどれでカバーするかの対応表
- エラーハンドリング戦略 (エラーコード、HTTP ステータス、実装方針)
- セキュリティ要件、パフォーマンス要件
- Integration Points (外部システム / 他機能との統合点)

**読者**: エンジニア、AI エージェント、アーキテクト

### 3.2.1 REQUIREMENTS.md と TECH_DESIGN.md の違い

| 項目     | REQUIREMENTS.md                  | TECH_DESIGN.md                                          |
| -------- | -------------------------------- | ------------------------------------------------------- |
| **視点** | ユーザー視点 (What & Why)        | 技術視点 (How)                                          |
| **読者** | ステークホルダー、PM、デザイナー | エンジニア、アーキテクト、AI エージェント               |
| **内容** | ユーザージャーニー、ビジネス目標 | アーキテクチャ、API 設計、内部仕様、仕様とテストの対応 |

### 3.3 含めないもの (両方)

- "実装済み" / "実装中" 等の進捗ステータス。Spec は常に最新の仕様のみを保持する
- 関数 / コンポーネントの具体実装コード (型定義 / API 定義 / バリデーションルールは可)
- チェックボックス形式の TODO (これは PLAN ドキュメントに記載する)

---

## 4. PLAN ドキュメント

Spec が「常に最新の仕様」なら、PLAN は「1 セッション分の作業計画」を保持する。

- セッション開始時に作成し、スコープをユーザー / レビュワと合意する
- Test Strategy に従って「テスト作成 → 実装 → 検証」のタスクを並べる
- 進捗ステータス (`- [x]`) を保持してよい
- セッション中の決定事項、注意点、引き継ぎを書き留める

配置パスは `.stdd.config.yml` の `docs.layout.plan` で設定する。
デフォルト例: `docs/<app>/<feature_path>/plans/<yyyy-mm-dd>.md`

---

## 5. テスト戦略

### 5.1 テストレベル

| レベル          | 対象                                       | 目的                                  |
| --------------- | ------------------------------------------ | ------------------------------------- |
| **E2E**         | 機能 (feature) またはページ (page) 単位    | Critical Paths のみ                   |
| **Integration** | ページ以下のコンポーネント / モジュール統合 | エラーケース、コンポーネント間結合    |
| **Unit**        | 関数 / メソッド単体                         | 詳細ロジック、バリデーション、純粋関数 |

### 5.2 Priority と推奨テスト構成

| Priority | 定義                                                                                                           | 推奨テスト構成                                       |
| -------- | -------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| **P0**   | Critical Path<br>ビジネス直結、頻度が非常に高い、複数システム統合、データ損失 / セキュリティに関わる            | E2E 必須 + Integration + Unit                        |
| **P1**   | Important<br>重要だが Critical ではない、頻度が高い、エラーケースの大半                                          | E2E 検討 (複雑さ・コストで判断) + Integration 必須   |
| **P2**   | Nice to Have<br>エッジケース、頻度が低い、UX 改善                                                              | E2E 不要 + Integration 検討 + Unit                   |

### 5.3 「E2E は P0 のみ」の原則

E2E は実行コストが高く、メンテナンスコストも高い。
すべての Journey を E2E で網羅すると、テストが壊れやすくなり、CI が長時間化する。
P0 のフローのみ E2E で守り、それ以外は Integration / Unit に役割を譲ること。

### 5.4 エラーケースも Journey として記述する

エラーは "その他" ではなく **正規の User Journey** として REQUIREMENTS.md に書く。
こうすることで、エラー時の挙動 (メッセージ・回復導線) が暗黙仕様化せず、テストにマッピングできる。

---

## 6. 開発フロー

### 6.1 新機能開発

```
1. REQUIREMENTS.md 作成 (Journey と Priority を網羅)
        ↓
2. ワイヤーフレーム生成 (HTML / 低忠実度。UI を持つ機能のみ)
        ↓
3. ステークホルダーレビュー
        ↓
4. TECH_DESIGN.md 作成 (アーキテクチャ + Test Strategy)
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

### 6.2 既存機能への追加 / 変更

```
1. PLAN ドキュメント作成 (Spec 更新タスクを含める)
        ↓
2. REQUIREMENTS.md 更新 (Journey 追加 / 変更 + Priority)
        ↓
3. ステークホルダーレビュー
        ↓
4. TECH_DESIGN.md 更新 (Test Strategy 反映)
        ↓
5. アーキテクトレビュー
        ↓
6. PLAN ドキュメント更新 (タスク詳細を Test Strategy に基づき確定)
        ↓
7. テスト作成・更新 (Red) → 実装 (Green) → 検証 → PR
```

Mermaid 図は `workflow-diagram.md` を参照。

### 6.3 PR レビュー観点

PR 作成時は、CI が通っていること・PR description に仕様ドキュメントへのリンクがあることを確認する。
レビュアーは以下を確認してから承認・マージする:

- ✅ REQUIREMENTS.md の要件を満たしているか
- ✅ TECH_DESIGN.md の設計に従っているか
- ✅ Test Strategy に従ってテストが書かれているか
- ✅ すべてのテストが通っているか
- ✅ コード品質 (可読性、保守性)

---

## 7. Red 状態を必ず確認する

テスト作成後、**実装を入れる前に必ずテストを実行して Red (失敗) を確認する**。

```
$ {{commands.test}} -- <test-file>
# 期待: FAIL (実装がないため失敗) → 正常
# 異常: PASS (テストが何もチェックしていない)
```

Red を確認する目的:

- ✅ テストが正しく動作していることを証明
- ✅ テストが実装の振る舞いを観察していることを保証
- ✅ "テストが最初から通ってしまう" バグを防ぐ

最初から PASS してしまう場合、テストが何もチェックしていない。アサーションを強化するか、モックの粒度を見直す。

(`{{commands.test}}` は `.stdd.config.yml` の `commands.test` で定義されたコマンド)

---

## 8. ベストプラクティス

1. **仕様レビューを最優先する**。実装前に Spec を凍結し、後工程の手戻りを最小化する
2. **E2E は P0 のみ**。安易に増やさない (5.3 参照)
3. **エラーケースも Journey として記述する** (5.4 参照)
4. **Test Strategy を TECH_DESIGN.md で明示する**。各 Journey にどのテストレベルを充てるか、その理由とともに表で示す
5. **ドキュメントは実装ディレクトリに対応させる**。`docs.layout` で定義したパターンに従い、機械的に対応関係を保つ
6. **セッション開始時にスコープを確認する**。大きな機能は複数 PLAN に分割する
7. **Spec に進捗ステータスを書かない**。"実装済み" "対応中" のような時系列情報は PLAN とコミット履歴に任せる

---

## 9. 関連ドキュメント

- `workflow-diagram.md` — 各フローを Mermaid で図示
- `guide-for-existing-project.md` — 既存プロジェクトへの STDD 導入手順（遡行ブートストラップ → 順行運用）
- `guide-for-new-project.md` — 新規プロジェクトの STDD 立ち上げ手順（最初から順行）
- `../templates/REQUIREMENTS.md` — ビジネス要件テンプレ
- `../templates/TECH_DESIGN.md` — 技術設計テンプレ
- `../templates/PLAN.md` — 実装計画テンプレ
- `../schema/.stdd.config.schema.json` — プロジェクト設定の JSON Schema
