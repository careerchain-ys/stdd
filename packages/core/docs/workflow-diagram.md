# STDD ワークフロー図

本ドキュメントは `stdd-methodology.md` のフローを Mermaid 図で示す。
Spec → Test → Implementation の流れを視覚的に把握したい場合に参照する。

---

## 1. 新機能開発フロー

```mermaid
flowchart TD
    Start([新機能の着手])
    Req[REQUIREMENTS.md 作成<br/>User Journey + Priority]
    WF[ワイヤーフレーム生成<br/>HTML / 低忠実度]
    StakeholderReview{ステークホルダー<br/>レビュー}
    Tech[TECH_DESIGN.md 作成<br/>アーキテクチャ + Test Strategy]
    ArchReview{アーキテクト<br/>レビュー}
    Plan[PLAN ドキュメント作成<br/>セッションスコープ合意]
    Red[テスト作成 — Red 状態]
    RedCheck{Red 確認<br/>テストが失敗するか}
    Green[実装 — テストを通す最小限のコード]
    GreenCheck{Green 確認<br/>テスト全件パス}
    Refactor["リファクタ<br/>必要に応じて"]
    PR[PR 作成]
    CodeReview{コードレビュー}
    Merge([マージ])

    Start --> Req
    Req --> WF
    WF --> StakeholderReview
    StakeholderReview -- 修正必要 --> Req
    StakeholderReview -- 承認 --> Tech
    Tech --> ArchReview
    ArchReview -- 修正必要 --> Tech
    ArchReview -- 承認 --> Plan
    Plan --> Red
    Red --> RedCheck
    RedCheck -- PASS してしまう --> RedFix[テスト修正<br/>アサーション強化]
    RedFix --> RedCheck
    RedCheck -- FAIL を確認 --> Green
    Green --> GreenCheck
    GreenCheck -- FAIL --> Green
    GreenCheck -- PASS --> Refactor
    Refactor --> PR
    PR --> CodeReview
    CodeReview -- 修正 --> Green
    CodeReview -- 承認 --> Merge
```

---

## 2. 既存機能への追加 / 変更フロー

```mermaid
flowchart TD
    Start([既存機能の変更着手])
    Plan1[PLAN ドキュメント作成<br/>Spec 更新タスクを含める]
    Req[REQUIREMENTS.md 更新<br/>Journey 追加 / 変更]
    StakeholderReview{ステークホルダー<br/>レビュー}
    Tech[TECH_DESIGN.md 更新<br/>Test Strategy 反映]
    ArchReview{アーキテクト<br/>レビュー}
    Plan2[PLAN ドキュメント更新<br/>タスク詳細を確定]
    Red[テスト作成 / 更新 — Red 状態]
    Green[実装 — Green 状態]
    PR[PR 作成]
    Merge([マージ])

    Start --> Plan1
    Plan1 --> Req
    Req --> StakeholderReview
    StakeholderReview -- 修正必要 --> Req
    StakeholderReview -- 承認 --> Tech
    Tech --> ArchReview
    ArchReview -- 修正必要 --> Tech
    ArchReview -- 承認 --> Plan2
    Plan2 --> Red
    Red --> Green
    Green --> PR
    PR --> Merge
```

---

## 3. Spec → Test → Implementation の一方向フロー

STDD は **常に Spec を起点とした一方向のウォーターフォール** で進む。
矢印は決して遡行しない。

```mermaid
flowchart LR
    subgraph SSoT["Single Source of Truth (Spec)"]
        Req[REQUIREMENTS.md<br/>What & Why]
        WF[ワイヤーフレーム<br/>HTML / 画面の合意]
        Tech[TECH_DESIGN.md<br/>How + Test Strategy]
        Req --> WF
        WF --> Tech
    end

    Tech --> Test[テスト<br/>E2E / Integration / Unit]
    Test --> Impl[実装]
```

### 変更が発生したときも起点は常に Spec

変更の **トリガー** (バグ報告、要件追加、設計見直しなど) は任意の場所で発生してよいが、
**変更の適用** は必ず Spec から開始し、下流に伝播させる。

```mermaid
flowchart TD
    Trigger[変更トリガー<br/>バグ / 要件追加 / 設計見直し / レビュー指摘]
    Req[1. REQUIREMENTS.md を更新]
    Tech[2. TECH_DESIGN.md を更新]
    Test[3. テストを更新]
    Impl[4. 実装を更新]

    Trigger -. 起点はどこでも .-> Req
    Req --> Tech
    Tech --> Test
    Test --> Impl
```

ポイント:

- Spec が SSoT。実装やテストで発覚した不具合・乖離も、まず Spec を更新し、その後 Test → Impl の順に直す (Spec を後追いさせない)
- 実装側で先に「直したくなる」気持ちが出ても、Spec を飛ばして実装だけ修正すると Spec と実装が乖離し、SSoT 性が壊れる
- これにより Spec が常に最新仕様を保持し、AI エージェントやステークホルダーが Spec だけ読めば最新仕様を把握できる状態を維持する

---

## 4. PLAN を使ったセッション分割

```mermaid
gantt
    title 大規模機能の PLAN 分割例
    dateFormat YYYY-MM-DD
    axisFormat %m-%d

    section Spec
    REQUIREMENTS.md          :done, req1, 2026-05-01, 2d
    TECH_DESIGN.md           :done, tech1, after req1, 2d

    section PLAN セッション
    PLAN 1 - P0 メインフロー  :active, p1, 2026-05-05, 3d
    PLAN 2 - P0 エラーフロー  :p2, after p1, 2d
    PLAN 3 - P1 エッジケース  :p3, after p2, 2d
    PLAN 4 - P2 拡張          :p4, after p3, 2d
```

ポイント:

- 1 つの REQUIREMENTS.md / TECH_DESIGN.md に対して、PLAN は複数発行される
- Priority 順 (P0 → P1 → P2) でセッションを切ると、最重要部分が早期に動く
- 各 PLAN セッション中に Spec の修正が必要になったら、即座に Spec 側を更新する (PLAN だけ独走させない)

---

## 5. Red-Green-Refactor サイクル (1 タスク単位の詳細)

```mermaid
flowchart LR
    Spec[Spec の該当 Journey] --> Write[テストを書く]
    Write --> Run1{テスト実行}
    Run1 -- FAIL を確認 --> Impl[実装を書く]
    Run1 -- PASS してしまう --> Fix[テスト修正<br/>アサーション強化]
    Fix --> Run1
    Impl --> Run2{テスト実行}
    Run2 -- FAIL --> Impl
    Run2 -- PASS --> Refactor[リファクタ]
    Refactor --> Run3{テスト実行}
    Run3 -- FAIL --> Refactor
    Run3 -- PASS --> Done([完了])
```

ポイント:

- "PASS してしまう" 場合のフォールバックを明示している (テストが実装の振る舞いを観察できていないバグ)
- リファクタ後も必ずテストを再実行し、Green を維持する

---

## 6. 関連ドキュメント

- `stdd-methodology.md` — STDD の詳細ガイド
- `../templates/` — 各ドキュメントテンプレ
