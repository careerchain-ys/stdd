# Spec and Test Driven Development (STDD): 開発ガイド

## 目次

1. [概要](#概要)
2. [なぜSpec and Test Driven Developmentなのか](#なぜspec-and-test-driven-developmentなのか)
3. [仕様ドキュメントの役割](#仕様ドキュメントの役割)
4. [テスト戦略](#テスト戦略)
5. [開発フロー](#開発フロー)
6. [ベストプラクティス](#ベストプラクティス)

---

## 概要

### Spec and Test Driven Development (STDD) とは

**仕様を先に定義し、その仕様に基づいてテストを作成し、それに基づいて実装を行う開発手法**

```
Spec and Test Driven Development (STDD):
  仕様 → テスト → 実装 → 検証
  (仕様が常に最新のSSoT)
```

---

## なぜSpec and Test Driven Developmentなのか

**1. 仕様ドキュメント↔テスト↔実装の一貫性を保つ**

- ✅ 仕様ドキュメント = ビジネス要件のSSoT(Single Source of Truth)
- ✅ テスト = 仕様の実行可能な証明
- ✅ 実装 = テストを通すための手段

```
REQUIREMENTS.md (What & Why)
  ↓ Test Strategyで対応を明示
Test (E2E/Integration/Unit)
  ↓ テストを通すために実装
Implementation
  ↓ 仕様を満たしていることを証明
Test Pass ✅
```

---

**2. 仕様ドキュメントさえあれば、機能性が担保された実装をAIが行うことができる**

Claude Codeは仕様ドキュメント(REQUIREMENTS.md + TECH_DESIGN.md)を読み込み、Test Strategy に従ってテストを作成し、テストを通す実装を自動生成します。

```
Human: REQUIREMENTS.md作成(ビジネス要件)
  ↓
Human: TECH_DESIGN.md作成(技術設計)
  ↓
Human: レビュー・承認
  ↓
Claude Code: テスト作成(E2E/Integration/Unit)
  ↓
Claude Code: 実装(テストを通すために)
  ↓
Claude Code: テスト実行・検証
```

**メリット**:

- 人間は「何を作るか(What)」に集中
- 仕様さえ正確なら、実装の品質が担保される

---

**3. 仕様ドキュメントをビジネス要件のSSoT(Single Source of Truth)として利用することができる**

REQUIREMENTS.mdは以下の情報を集約します:

- ユーザージャーニー(すべて記述、エラーケース含む)
- 各JourneyのPriority(P0/P1/P2)
- 成功基準、エッジケース

これにより:

- ✅ ステークホルダーとの合意形成が容易
- ✅ 仕様レビュー段階で方向性を確定(手戻りを最小化)
- ✅ 常に最新のビジネス要件が参照可能
- ✅ ドキュメントと実装の乖離がない

---

## 仕様ドキュメントの役割

- 以下で表すものはすべて同じものを指す
  - Specドキュメント
  - Spec
  - 仕様ドキュメント
  - 仕様書
- 仕様ドキュメントは以下２つがある

### REQUIREMENTS.md

**目的**: ビジネス要件とユーザージャーニーを定義し、SSoT(Single Source of Truth)として機能させる

**記述内容**:

- Problem Statement: このFeatureが解決する問題
- Business Goals: ビジネス目標
- **すべてのUser Journeyを記述**(正常系、エラーケース、エッジケース含む)
- **各JourneyにPriority(P0/P1/P2)を付与**
- Out of Scope: 対応しない項目

---

### TECH_DESIGN.md

**目的**: Feature固有の技術設計と内部仕様を定義し、実装の指針とする

**記述内容**:

- Feature-Specific Architecture: この機能固有のアーキテクチャとデータフロー
- Key Design Decisions: 設計判断とその理由
- Data Model: ER図、TypeScript型定義、バリデーションルール
- API Design: エンドポイント、型定義、エラーハンドリング
- **Test Strategy**: 各Journeyおよび内部仕様とテストレベルの対応表
- **Error Handling Strategy**: エラーコード定義、HTTPステータス、実装方針
- Security Requirements: セキュリティ要件
- Performance Requirements: パフォーマンス目標
- Integration Points: 外部システムとの統合

---

### REQUIREMENTS.md と TECH_DESIGN.md の違い

| 項目     | REQUIREMENTS.md                  | TECH_DESIGN.md                                        |
| -------- | -------------------------------- | ----------------------------------------------------- |
| **視点** | ユーザー視点(What & Why)         | 技術視点(How)                                         |
| **読者** | ステークホルダー、PM、デザイナー | エンジニア、アーキテクト                              |
| **内容** | ユーザージャーニー、ビジネス目標 | アーキテクチャ、API設計、内部仕様、仕様とテストの対応 |

**⚠️ 重要**: Specドキュメントには「対応済み」「実装中」などの**実装過程の記述を含めない**こと。Specドキュメントは常にSSoTとして最新の要件・仕様のみを記載する。

---

## テスト戦略

### テストレベルの定義

| テストレベル    | 対象                                  | 目的                         |
| --------------- | ------------------------------------- | ---------------------------- |
| **E2E**         | 機能(feature)またはページ(page)       | Critical Pathsのみ           |
| **Integration** | ページ(page)以下のReactコンポーネント | エラーケース、統合動作       |
| **Unit**        | 関数、メソッド単体                    | 詳細ロジック、バリデーション |

---

### Priority(P0/P1/P2)の定義

| Priority | 定義                                                                                                                                            | テスト戦略                                       |
| -------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| **P0**   | **Critical Path**<br>・ビジネスに直結する最重要フロー<br>・頻度が非常に高い<br>・複数システムをまたぐ統合<br>・データ損失やセキュリティに関わる | E2E必須<br>+ Integration                         |
| **P1**   | **Important**<br>・重要だがCritical Pathではない<br>・頻度が高い<br>・エラーケースの大半                                                        | E2E検討(複雑さ・コストで判断)<br>Integration必須 |
| **P2**   | **Nice to Have**<br>・エッジケース<br>・頻度が低い<br>・ユーザー体験の改善                                                                      | E2E不要<br>Integration<br>Unit                   |

---

## 開発フロー

### 新機能開発の全体フロー

```
1. REQUIREMENTS.md作成
   - すべてのUser Journey記述(エラーケース含む)
   - 各JourneyにPriority付与(P0/P1/P2)
   ↓
2. ステークホルダーレビュー
   ↓
3. TECH_DESIGN.md作成
   - Feature固有の技術設計
   - Test Strategy(各Journeyとテストレベルの対応)
   - ここでREQUIREMENTS.mdのJourneyを含めて仕様とテストの対応を明確にする
   ↓
4. アーキテクトレビュー
   ↓
5. ★ PLANドキュメント作成
   - 開発者に実装スコープを確認
   - Test Strategyに従ってタスクを分解
   - Unit → Integration → E2Eの順でテスト作成タスクを記載
   - その後、実装タスクを記載
   ↓
6. テスト作成(Red状態)(PLANドキュメントに従う)
   - Unit test
   - Integration test
   - E2E test
   ↓
7. 実装(PLANドキュメントに従う)
   ↓
8. テスト実行
   - Unit
   - Integration
   - E2E
   ↓
9. テスト通過確認(Green)
   ↓
10. PR作成 → 開発者によるレビュー → マージ
```

### 既存機能への追加・変更の全体フロー

```
1. ★ PLANドキュメント作成
   - 開発者に実装スコープを確認
   - タスクの一つとしてSpecドキュメントの更新を含める
   ↓
2. REQUIREMENTS.md更新
   - 新しいJourneyを追加、または既存を変更
   - Priority付与
   ↓
3. ステークホルダーレビュー
   ↓
4. TECH_DESIGN.md更新
   - 技術設計の変更を反映
   - Test Strategyを更新
   ↓
5. アーキテクトレビュー
   ↓
6. PLANドキュメント更新
   - テスト・実装計画をTest Strategyに基づいて更新
   ↓
7. テスト作成・更新(Red状態)(PLANドキュメントに従う)
   ↓
8. 実装(PLANドキュメントに従う)
   ↓
9. テスト実行
   ↓
10. テスト通過確認
   ↓
11. PR作成 → 開発者によるレビュー → マージ
```

---

### Phase 1: 仕様定義

#### 1-1. REQUIREMENTS.md作成/更新

**配置**: `docs/<app>/<path>/REQUIREMENTS.md`

**新機能の場合**: 新規作成

**既存機能への追加の場合**: 直接更新

**含めるべき内容**:

- Problem Statement、Target Users、Business Goals
- すべてのUser Journey(エラーケース、エッジケース含む)
- 各JourneyにPriority(P0/P1/P2)を付与
- Success Criteria、Edge Cases、Out of Scope

#### 1-2. ステークホルダーレビュー

- PMやデザイナーと仕様を確認
- ビジネス要件が満たされているか確認
- 修正が必要な場合は、REQUIREMENTS.mdを更新

---

### Phase 2: 技術設計

#### 2-1. TECH_DESIGN.md作成/更新

**配置**: `docs/<app>/<path>/TECH_DESIGN.md`

**新機能の場合**: 新規作成

**既存機能への追加の場合**: 直接更新

**含めるべき内容**:

- Feature-Specific Architecture
- Key Design Decisions(設計判断とその理由)
- Data Model(ER図、TypeScript型定義)
- API Design(エンドポイント、型定義)
- **Test Strategy**(各Journeyをどのテストレベルでカバーするか)
  - REQUIREMENTS.mdのすべてのJourneyを含める
  - 各Journeyとテストレベル(E2E/Integration/Unit)の対応を明示
- Error Handling Strategy
- Security/Performance Requirements
- Integration Points

#### 2-2. アーキテクトレビュー

- 技術設計が適切か確認
- アーキテクチャパターンに従っているか
- パフォーマンス・セキュリティ要件を満たせるか
- Test Strategyが適切か(E2E/Integration/Unitの役割分担)

---

### Phase 3: PLANドキュメント作成

PLANドキュメントはセッションごとの実装タスクを管理するドキュメントです。

**配置**: `docs/<app>/<feature-path>/plans/[yyyy-mm-dd].md`

**詳細**: [documenting-plans Skill](../.claude/skills/documenting-plans/SKILL.md) を参照

---

### Phase 4: テスト作成(Red状態)

**TDDの原則**: テスト作成 → **Red確認** → 実装 → **Green確認** → Refactor

TECH_DESIGN.mdのTest Strategyに従ってテストを作成:

1. **Unit test**: バリデーションロジック、ビジネスロジック
2. **Integration test**: エラーケース、コンポーネント統合
3. **E2E test**: Critical Paths(P0の一部)

#### 重要: Red状態の確認

**テスト作成後、必ずテストを実行してRed（失敗）を確認すること**

**なぜRedを確認するのか**:

- ✅ テストが正しく動作していることを証明
- ✅ テストが実装をチェックしていることを保証
- ✅ "テストが最初から通ってしまう"バグを防ぐ

**Red確認の手順**:

```bash
# テストを実行してRedを確認
npm test -- <test-file>

# 期待される結果: テストが失敗する（Red状態）
# ❌ FAIL: "実装がないため失敗" → 正常
# ✅ PASS: "テストが通った" → 異常（テストが何もチェックしていない）
```

**もしテストが最初から通ってしまった場合**:

- テストが正しく実装をチェックしていない
- テストを修正し、Redになることを確認
- 例: アサーションが甘い、モックが実装を含んでいる

---

### Phase 5: 実装(Green状態)

PLANドキュメントに従って順次実装:

1. Unit testに対応する実装
2. Integration testに対応する実装
3. E2E testに対応する実装

**実装時の原則（Red → Green → Refactorサイクル）**:

1. **Red**: テストが失敗することを確認（Phase 4で完了）
2. **Green**: 実装してテストを通す
   - 1タスクずつ完成させる
   - テストが通ることを確認してから次へ
3. **Refactor**: コードを整理（必要に応じて）
4. 各タスク完了後にcommit

**Greenになったら**:

```bash
# すべてのテストを実行
npm test

# 期待される結果: すべてのテストが通る（Green状態）
# ✅ PASS: すべてのテスト → Phase 6へ進む
# ❌ FAIL: 一部のテストが失敗 → 実装を修正
```

---

### Phase 6: テスト実行と検証

すべてのテストを実行し、Greenであることを確認:

- Unit test
- Integration test
- E2E test

---

### Phase 7: PR作成とマージ

#### 7-1. PR作成

- CIが通っていることを確認
- PR descriptionに仕様ドキュメントへのリンクを記載
- テストカバレッジを確認

#### 7-2. 開発者によるレビューとマージ

レビュアーは以下を確認:

- ✅ REQUIREMENTS.mdの要件を満たしているか
- ✅ TECH_DESIGN.mdの設計に従っているか
- ✅ Test Strategyに従ってテストが書かれているか
- ✅ すべてのテストが通っているか
- ✅ コード品質(可読性、保守性)

承認後、マージを実行。

---

## ベストプラクティス

### 1. 仕様レビューを最優先する

実装前にREQUIREMENTS.mdとTECH_DESIGN.mdをレビューし、方向性を確定。手戻りを最小化。

### 2. E2Eテストは「Critical Pathsのみ」

すべてのJourneyをE2E化しない。P0の一部のみE2E化し、その他はIntegration/Unitで検証。

### 3. エラーケースもUser Journeyとして記述

エラーケースを「その他」として扱わず、Priorityを付与。

### 4. Test StrategyをTECH_DESIGN.mdで明示

各JourneyにどのテストレベルでカバーするかをTECH_DESIGN.mdで明記し、「なぜこのテストレベルか」の理由も記載。

### 5. ドキュメントは実装ディレクトリに従う

実装ファイル: `admin_app/app/login/page.tsx`
→ ドキュメント: `docs/admin_app/login/REQUIREMENTS.md`, `TECH_DESIGN.md`

### 6. セッション開始時にスコープを確認する

PLANドキュメント作成前に、必ず開発者に実装スコープを確認する。大きな機能は複数セッションに分割して実装することが多いため、スコープを明確にすることで認識齟齬を防ぐ。

**詳細**: [documenting-plans Skill](../.claude/skills/documenting-plans/SKILL.md) を参照
