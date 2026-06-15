---
name: documenting-tech-specs
description: |-
  技術 spec (tech_specs) — TECH_DESIGN.md（技術設計）・TEST_PLAN.md（テスト戦略）と、common 階層の ARCHITECTURE / TABLE_DEFINITION / API_SPEC / DESIGN — のテンプレートとガイドラインを提供する。STDD 方法論における「技術設計（How）」の SSoT を担う。要件（What & Why）は documenting-requirements を使う。
when_to_use: |-
  「技術設計」「TECH_DESIGN.md」「TEST_PLAN.md」「テスト戦略」「ロジック設計」「画面項目定義」「ARCHITECTURE.md」「テーブル定義」「TABLE_DEFINITION」「API仕様」「API_SPEC」「DESIGN.md」「エラーハンドリング設計」に関する作業のとき。業務・機能・非機能要件は documenting-requirements を使う。
allowed-tools: Read, Write, Edit, Glob, Grep
---

# 技術 spec (tech_specs) — TECH_DESIGN / TEST_PLAN / common 技術階層の作成

STDD（Spec and Test Driven Development）方法論に従って、技術系の設計書（総称 **技術 spec / tech_specs**）を作成・更新します。対象は feature の TECH_DESIGN.md・TEST_PLAN.md と、common 階層の ARCHITECTURE.md / TABLE_DEFINITION.md / API_SPEC.md / DESIGN.md（→ `stdd-methodology.md` §2）。

> **前提**: 技術設計は REQUIREMENTS.md（要件）が確定していることを前提とする。要件（業務・機能・非機能）の作成は [documenting-requirements Skill](../documenting-requirements/SKILL.md) を使う。**SSOT原則・要確認マーカーのSSoTも documenting-requirements にある**ため、本スキルでもそれに従う（後述「絶対ルール」参照）。

## Quick Start

### 新機能の技術設計を作成する場合

REQUIREMENTS.md（要件）が確定している前提で:

1. **TECH_DESIGN.md を作成**

   ```
   docs/<app>/<path>/TECH_DESIGN.md
   ```

   - 章構成: 概要 / 主要な設計判断（任意）/ 画面項目定義（画面 feature は必須）/ ロジック設計（コア）/ エラーハンドリング戦略 / 非機能要件（任意）
   - データ構造は common の `TABLE_DEFINITION.md`、API は common の `API_SPEC.md` を**参照**（再定義しない）
   - [テンプレート](templates/tech-design.md) を参照

2. **TEST_PLAN.md を作成**

   ```
   docs/<app>/<path>/TEST_PLAN.md
   ```

   - テスト戦略（REQUIREMENTS のユースケース＋ TECH_DESIGN のロジック設計を E2E/Integration/Unit にマッピング）
   - [テンプレート](templates/test-plan.md) を参照

> 横断要素（テーブル定義・API 仕様）は common 階層に集約する。新規テーブル / API が生じたら common の
> [`TABLE_DEFINITION.md`](templates/table-definition-common.md) / [`API_SPEC.md`](templates/api-spec-common.md) を更新し、feature からは参照する。

### common 階層の技術ドキュメントを作成する場合

```
docs/common/ARCHITECTURE.md / TABLE_DEFINITION.md / API_SPEC.md / DESIGN.md
```

- **ARCHITECTURE.md**: システム概要（構成 / スタック / 連携 / セキュリティ / インフラ）。データモデル・API は持たない。[テンプレート](templates/architecture-common.md)
- **TABLE_DEFINITION.md**: 全テーブル定義のSSoT（カード形式・ER 図なし）。feature が参照する。[テンプレート](templates/table-definition-common.md)
- **API_SPEC.md**: API 契約のSSoT（OpenAPI 風 Markdown）。feature が参照する。[テンプレート](templates/api-spec-common.md)
- **DESIGN.md**（任意）: デザイン標準。[テンプレート](templates/design-common.md)

既存実装からの common 技術 spec 作成は `reverse-engineering-common-spec` スキルを参照。

### 既存機能の技術設計を更新する場合

1. 対応する TECH_DESIGN.md / TEST_PLAN.md を確認
2. 変更内容に応じて更新（テーブル・API の変更は common の TABLE_DEFINITION / API_SPEC に反映）
3. テスト戦略（テスト総数・内訳）は TEST_PLAN.md を更新

## Spec の 2 階層構造（common / feature）

技術設計も feature 階層（機能単位）と common 階層（プロジェクト全体）の2層で扱う。

| 階層      | 技術ドキュメント | 配置例 |
| ----------- | --- | --- |
| **common**  | `ARCHITECTURE.md`（システム概要）/ `TABLE_DEFINITION.md`（テーブル定義）/ `API_SPEC.md`（API 仕様）/ `DESIGN.md`（任意） | `docs/common/` |
| **feature** | `TECH_DESIGN.md` / `TEST_PLAN.md` | `docs/<app>/<feature>/` |

- feature の TECH_DESIGN は common 階層（システム構成・テーブル定義・API 仕様）を**前提とし、参照する**。**テーブル・API は feature で再定義しない**。
- 要件階層（REQUIREMENTS）は [documenting-requirements Skill](../documenting-requirements/SKILL.md) が扱う。

## ドキュメント配置ルール

| 実装ファイル                  | 技術設計の配置先 |
| ----------------------------- | --- |
| `<app>/app/<path>/page.tsx`   | `docs/<app>/<path>/TECH_DESIGN.md`<br>`docs/<app>/<path>/TEST_PLAN.md` |
| `<app>/components/<name>.tsx` | `docs/<app>/components/<name>/TECH_DESIGN.md`<br>`docs/<app>/components/<name>/TEST_PLAN.md` |

配置先は `.stdd.config.yml` の `docs.layout.*`（`docs.layout.tech_design` 等）テンプレートに、対象アプリの `app`（`apps[].id`）と `feature_path` を適用して決定する。

**例**: 実装 `<app.path>/app/login/page.tsx` → `docs/<app.id>/login/TECH_DESIGN.md`, `docs/<app.id>/login/TEST_PLAN.md`

## 絶対ルール: SSOT原則・要確認マーカー（最優先）

⚠️ **Specドキュメントは「現在の最新仕様」だけを記述するSingle Source of Truth（SSOT）である**。履歴・経緯・対応中のissue・「今回の変更」は一切書かない。

技術設計ドキュメントでも特に出やすい違反:

- テスト戦略表で `✅ (更新に統合)` `2 ケースに集約` `1 テストにまとめる方針` のように「以前は別だったが今はまとめてある」ことを匂わせる表現
- ロジック・設計判断で `変更前/変更後` `〜だったが〜に変更した` `今回追加した設計` 等

常に**現在の構成事実のみ**を記述する（例: `プロフィール情報を更新する テスト内のステップとして検証`）。設計判断の理由は「**この構成を採る**理由」として書き、「変更そのものの理由」は書かない。

> **SSOT原則・要確認マーカーの完全な定義（禁止語リスト・Self-check・違反例・マーカー構文）は [documenting-requirements SKILL「絶対ルール: SSOT原則」「要確認マーカー」](../documenting-requirements/SKILL.md) がSSoT**。技術設計でも同じルール・同じ Self-check（禁止語 grep）を適用すること。詳細な違反例は [STDD違反例と対策](../documenting-requirements/guides/stdd-violations.md) を参照。

---

## 基本原則: TECH_DESIGN.md（設計書）

**目的**: 機能（画面単位）の技術設計。実装者が**ロジックを起こせる粒度**で記述する。

**章構成**: 概要 / 主要な設計判断（任意）/ 画面項目定義（画面 feature は必須）/ ロジック設計（コア）/ エラーハンドリング戦略 / 非機能要件（任意）

**記述する内容**:

- **ロジック設計**: 集計式・変換・ドメインルール・トランザクション境界・副作用・複数テーブル横断の流れ（手順 / 擬似コード / 計算式）
- **画面項目定義**: UI × バリデーション × DB マッピング（画面 feature のみ。DB カラムは TABLE_DEFINITION を参照）
- **エラーハンドリング戦略**: API / 処理の失敗を本機能がどう捌くか → [エラーハンドリングガイド](guides/error-handling.md)
- データ構造・API は common の `TABLE_DEFINITION.md` / `API_SPEC.md` を**参照**（再定義しない）

**記述しない内容**:

- 実装例・コード例（関数・メソッドの実装、Server Actions の実装）。擬似コード・型 I/F・計算式は可
- テーブル・カラム定義（→ common `TABLE_DEFINITION.md`）/ API 契約（→ common `API_SPEC.md`）
- テスト戦略（→ `TEST_PLAN.md`）
- 業務要件・機能要件・非機能要件（→ REQUIREMENTS.md）
- ファイル構成・実装順序（→ PLANドキュメント）

## 基本原則: TEST_PLAN.md（テスト計画書）

**目的**: 機能のテスト戦略。**REQUIREMENTS のユースケース**と **TECH_DESIGN のロジック設計（その他処理フロー）**の両方をテストレベル（E2E / Integration / Unit）に漏れなくマッピングする。

**記述する内容**:

- §1 ユースケース別テスト戦略（REQUIREMENTS §2.1 の全ユースケース × テストレベル × 根拠）
- §2 その他処理フロー別テスト戦略（TECH_DESIGN §4.2 がある場合）
- **テスト総数と内訳**（例: 合計 33 件 - Unit 18 件, Integration 9 件, E2E 6 件）
- 振る舞い（手順）→E2E、受入基準（EARS）→Unit/Integration の対応で組む
- REQUIREMENTS の Priority（P0/P1/P2）と対応させる

## 基本原則: common 階層の技術ドキュメント

- **ARCHITECTURE.md**: システム概要（構成 / スタック / 連携 / セキュリティ / インフラ）。データモデル・API は持たない。
- **TABLE_DEFINITION.md**: 全テーブル定義のSSoT（カード形式・ER 図なし）。feature が参照する。
- **API_SPEC.md**: API 契約のSSoT（OpenAPI 風 Markdown）。feature が参照する。
- **DESIGN.md**（任意）: デザイン標準。

### Priority（優先度）ガイドライン

テスト戦略は REQUIREMENTS の Priority に従う。

| Priority | 定義                                                     | テスト戦略                 |
| -------- | -------------------------------------------------------- | -------------------------- |
| **P0**   | Critical Path - ビジネスに直結、高頻度、複数システム統合 | E2E 必須 + Integration     |
| **P1**   | Important - 重要だが Critical Path ではない              | E2E 検討、Integration 必須 |
| **P2**   | Nice to Have - エッジケース、低頻度                      | Integration または Unit    |

## 次のステップ

技術設計（TECH_DESIGN + TEST_PLAN）の作成・レビュー（人間レビュー含む）が完了したら:

1. **PLANドキュメントを作成** → [documenting-plans Skill](../documenting-plans/SKILL.md)
2. PLANドキュメントに従ってテスト作成・実装を進める

## 参照ファイル

- **テンプレート（feature）**
  - [TECH_DESIGN.md](templates/tech-design.md) ← 概要 / 設計判断 / 画面項目定義 / ロジック設計 / エラーハンドリング / 非機能要件
  - [TEST_PLAN.md](templates/test-plan.md) ← テスト戦略
- **テンプレート（common）**
  - [ARCHITECTURE.md](templates/architecture-common.md) ← システム概要
  - [TABLE_DEFINITION.md](templates/table-definition-common.md) ← テーブル定義
  - [API_SPEC.md](templates/api-spec-common.md) ← API 仕様
  - [DESIGN.md](templates/design-common.md) ← デザイン標準（任意）
- **ガイド**
  - [エラーハンドリングガイド](guides/error-handling.md)
  - [STDD違反例と対策](../documenting-requirements/guides/stdd-violations.md) ← SSOT原則（SSoTは documenting-requirements）
- **関連スキル**
  - [documenting-requirements Skill](../documenting-requirements/SKILL.md) ← 要件（前提・SSOTSSoT）
- **次のステップ**
  - [PLANドキュメント作成スキル](../documenting-plans/SKILL.md)

## When NOT to Use This Skill

- **要件のみ**: 業務要件・機能要件・非機能要件・ユースケース → documenting-requirements
- **単純なバグ修正 / リファクタリング**: 技術設計（外部から見える挙動）が変わらない場合
- **テストの追加のみ**: 既存仕様に基づくテスト追加（ただし TEST_PLAN.md のテスト総数は更新が必要）

## チェックリスト

### TECH_DESIGN.md 作成時

```
□ 1. 概要（目的・スコープ）＋ 1.1 対応ユースケース表 ＋ 1.2 使用 API（API を持つ機能）
□ REQUIREMENTS の全ユースケースが §1.1 対応表に載り、設計（§3/§4）に紐づいている（設計漏れなし）
□ 2. 主要な設計判断 - この機能特有の判断のみ（無ければ章ごと省略）
□ 3. 画面項目定義 - 画面 feature は必須（UI × バリデーション × DB マッピング ＋ 画面状態〔通常/空/ローディング/エラー〕）。非画面は省略
□ 4. ロジック設計 - 4.1 ユースケース別ロジック（常に）＋ 4.2 その他処理フロー（機能固有ロジックがあれば）
□ 5. エラーハンドリング戦略 - API/処理の失敗を本機能がどう捌くか
□ 6. 非機能要件 - REQUIREMENTS に記載がある場合のみ実現方法（無ければ章ごと省略）
□ テーブル・API を再定義していない（common の TABLE_DEFINITION / API_SPEC を参照）
□ 実装例・コード例が含まれていないことを確認（擬似コード・型 I/F・計算式は除く）
□ SSOT原則の禁止語が含まれていない（Self-check 通過）
```

### TEST_PLAN.md 作成時

```
□ §1: REQUIREMENTS §2.1 の全ユースケースが 1 行ずつ載っている（名前一致・漏れなし）
□ §2: TECH_DESIGN §4.2 その他処理フローがある場合、全フローが 1 行ずつ載っている
□ 振る舞い（手順）→E2E、受入基準（EARS）→Unit/Integration の対応で組まれている
□ 各テストレベルの選択に根拠（Rationale）がある
□ REQUIREMENTS の Priority（P0/P1/P2）と対応している
```

### common 階層（テーブル定義 / API 仕様）更新時

```
□ TABLE_DEFINITION.md: 新規/変更テーブルをカード形式で記載（型は論理型・FK は説明欄）
□ API_SPEC.md: 新規/変更エンドポイントを記載（レスポンス実体は TABLE_DEFINITION へリンク）
□ 参照する feature TECH_DESIGN との整合を確認
```
