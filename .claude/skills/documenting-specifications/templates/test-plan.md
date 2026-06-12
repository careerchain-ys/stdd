# TEST_PLAN.md テンプレート（feature）

**目的**: 機能（画面単位）のテスト戦略。REQUIREMENTS のユースケースをテストレベル（E2E / Integration / Unit）にマッピングし、テストファイル構成を定義する。

**配置**: `docs/<app>/<path>/TEST_PLAN.md`（`.stdd.config.yml` の `docs.layout.test_plan` に従う）

## 章立ての骨格

| 章 | 内容 |
| --- | --- |
| 1. ユースケース別テスト戦略 | ユースケース × テストレベル × 根拠 |
| 2. テストファイル構成 | E2E / Integration / Unit の配置 |

- REQUIREMENTS のユースケース（Priority 付き）を、どのテストレベルで担保するかにマッピングする。
- 各レベルを選ぶ / 選ばない**根拠（Rationale）**を必ず書く。

## テンプレート構造

````markdown
# [機能名] テスト計画

> ビジネス要件は [`REQUIREMENTS.md`](./REQUIREMENTS.md)、技術設計は [`TECH_DESIGN.md`](./TECH_DESIGN.md) を参照。

## 1. ユースケース別テスト戦略

| ユースケース | E2E | Integration | Unit | 根拠 |
| --- | --- | --- | --- | --- |
| P0: [メインフロー] | ✅ | ✅ | ✅ | Critical path・ビジネス直結・複数システム統合 |
| P1: [重要なエラーケース] | ⚠️ 検討 | ✅ | ✅ | 頻度高い・Integration 必須・E2E はコストで判断 |
| P2: [エッジケース] | ❌ | ⚠️ | ✅ | 低頻度・Unit で十分 |

## 2. テストファイル構成

- **E2E**: `e2e/tests/[app]/[feature].spec.ts`
- **Integration**: `[app]/components/[name].test.tsx`
- **Unit**: `[app]/lib/*.test.ts`, `[app]/domain/models/*.test.ts`
````

## 記述基準

- ユースケースは REQUIREMENTS の Priority（P0 / P1 / P2）と対応させる。
- テストレベルの選択は「✅ 実施 / ⚠️ 検討 / ❌ 不要」で示し、根拠列を空にしない。
- 処理ロジックの検証観点（集計式・境界値）は対応する Unit / Integration の根拠に紐づける。

## 記述しない内容（責務分界）

- ユースケース本体（振る舞い＋受入基準） → `REQUIREMENTS.md`
- 処理ロジック・画面項目 → `TECH_DESIGN.md`
- テストの実装コード → テストファイル本体
