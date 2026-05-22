# STDD ワークフロー図

本ドキュメントは `stdd-methodology.md` のフローを Mermaid 図で示す。
Spec → Test → Implementation の流れを視覚的に把握したい場合に参照する。

---

## 1. 新機能開発フロー

```mermaid
flowchart TD
    Start([新機能の着手])
    Req[REQUIREMENTS.md 作成<br/>User Journey + Priority]
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
    Req --> StakeholderReview
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

## 3. Spec / Test / Implementation の三角関係

```mermaid
flowchart LR
    subgraph SSoT[Single Source of Truth]
        Req[REQUIREMENTS.md<br/>What & Why]
        Tech[TECH_DESIGN.md<br/>How + Test Strategy]
    end

    Req -- Journey を抽出 --> Test
    Tech -- Test Strategy で割当 --> Test
    Test[テスト<br/>E2E / Integration / Unit]
    Test -- 通すために --> Impl[実装]
    Impl -- 仕様を満たす証明 --> Test
    Test -- 仕様乖離を検出 --> Req
    Test -- 仕様乖離を検出 --> Tech
```

ポイント:

- Spec が SSoT。実装やテストとの乖離が出たら Spec を直す方向で同期する (Spec を後追いしない)
- Test は Spec と Implementation の双方向の "鏡" として機能する
- Implementation は Test を通すための手段にすぎない

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
