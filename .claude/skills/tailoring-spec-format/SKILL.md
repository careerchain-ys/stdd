---
name: tailoring-spec-format
description: |-
  このプロジェクト固有の spec フォーマット / ラインナップを策定し、テンプレートや設定へ反映するスキル。STDD 導入の step 3-4（初期フォーマット策定）と step 7（運用中のブラッシュアップ）の両方を担う。common spec と代表 feature spec を素材に、必須/任意の spec ファイル構成・固有セクション・docs.layout・Priority 基準・テスト層責務・命名を決め、決定を導入PLANに記録してテンプレ/設定へ反映する。「specフォーマット策定」「テンプレ特化」「テーラリング」「spec構成を決める」「specフォーマットのブラッシュアップ」「STDDをプロジェクトに合わせる」に関する作業で使用。個別機能の spec 作成は documenting-specifications を使う。
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# spec フォーマット テーラリングスキル

STDD のテンプレートを**このプロジェクト固有**に仕立て直す（テーラリング）。
STDD 導入フローの **step 3-4（初期フォーマット策定）** と **step 7（運用中のブラッシュアップ）** の両方を担う。

> 導入フロー全体は [`introduction-guide.md`](../../../packages/core/docs/introduction-guide.md)、
> 駆動役は [`introducing-stdd`](../introducing-stdd/SKILL.md) を参照。本スキルは単体でも呼べる。

## 設計方針（重要）

- **フォーマットの決定そのものは人間**（ビジネス・チーム判断）。本スキルはそれを**促し・記録し・反映する**手続きに徹する。
- **agent オーケストレーションはしない**。Claude がメインセッションで決定ポイントを 1 つずつ提示し、人間に決めてもらう。
- 決定は **導入PLAN の「フォーマット決定ログ」** に集約（SSOT）。spec 本体に経緯・履歴を書かない。

## 前提（素材）

- **step 3-4（初期）**: `docs/common/`（common spec, step 1）と代表 feature spec 1 つ（step 2）が既にある。
- **step 7（ブラッシュアップ）**: 既に複数の feature spec が運用されている。

---

## 手順

### 1. 素材レビュー

現状を把握する。

```
□ docs/common/REQUIREMENTS.md / ARCHITECTURE.md（common ティアの構成）
□ 代表 feature spec（REQUIREMENTS.md / TECH_DESIGN.md）の実物
□ 現在の .stdd.config.yml（docs.layout / apps / commands）
□ 利用中のテンプレ（packages/core/templates/ または プロジェクト側コピー）
□ (step 7 のみ) 運用中の全 feature spec のばらつき・過不足
```

### 2. 決定ポイントを 1 つずつ提示（★人間が決める）

各項目について **現状 → 選択肢 → 推奨** を提示し、ユーザーに決めてもらう。一度に押し付けない。

| 決定ポイント | 論点 | 反映先 |
| ------------ | ---- | ------ |
| **spec ファイル構成** | 必須/任意（REQUIREMENTS / TECH_DESIGN / SCREEN_ITEMS_DEFINITION / wireframes）をどう組むか | プロジェクトのテンプレ・運用ルール |
| **common 固有セクション** | common ARCHITECTURE に足す横断トピック（認証・認可 / RLS・権限 / 通知 / 監査ログ 等） | `docs/common/ARCHITECTURE.md` |
| **docs.layout パス規約** | 単一/複数アプリ、`feature_path` の切り方、common の置き場 | `.stdd.config.yml` の `docs.layout` |
| **Priority 基準** | このプロジェクトでの P0/P1/P2 の具体定義（何を Critical とするか） | テンプレ注記 + 決定ログ |
| **テスト層の責務分担** | E2E/Integration/Unit の線引き（既存テスト資産に合わせる） | TECH_DESIGN テンプレのテスト戦略節 |
| **命名・用語** | プロジェクト固有語彙（アクター名・ドメイン用語）、テンプレのプレースホルダ実値化 | テンプレ・common spec |

### 3. 決定を記録

`docs/common/plans/stdd-introduction.md`（導入PLAN）の **「フォーマット決定ログ」** に各決定を追記する。
導入PLAN が無い文脈（step 7 単体実行など）では、プロジェクトの spec 規約ドキュメント（例: `docs/common/SPEC_CONVENTIONS.md`）に記録してよい。

### 4. テンプレ・設定へ反映（機械的）

決定に従って、**プロジェクト側**の成果物を更新する（STDD core の `packages/core/templates/` 本体は壊さない）。

```
□ .stdd.config.yml の docs.layout を更新（必要なら common_* を追加/変更）
□ docs/common/ARCHITECTURE.md に固有セクションを追加
□ プロジェクト側テンプレ（コピーを持つ場合）の不要セクション削除 / 固有セクション追加 / プレースホルダ実値化
□ プロジェクト側テンプレを持たない場合は、決定ログに「次に作る feature spec へ適用する方針」として明記
```

### 5. （step 7 のみ）既存 spec への影響を洗い出す

フォーマットを変えた場合、運用中の feature spec に差分が出る。影響範囲を一覧化してユーザーに提示し、修正は別タスク（必要なら PLAN を切る）として扱う。一括自動修正はしない。

---

## 守ること

- **決定は人間**。skill は選択肢提示・記録・反映に徹する。
- 一度に全項目を片付けず、**決定ポイントごとに合意**を取る。
- **STDD core テンプレ（`packages/core/templates/`）を直接編集しない**。反映先はプロジェクト側。
- 決定は決定ログに集約し、spec 本体に経緯・「変更前/後」を書かない（SSOT）。

---

## When NOT to Use This Skill

- **個別機能の spec を書く**: `documenting-specifications` を使う
- **既存実装から spec を起こす**: `reverse-engineering-feature-spec` / `reverse-engineering-common-spec` を使う
- **導入フロー全体を進める**: `introducing-stdd`（本スキルを step 3-4 / 7 で呼ぶ）

---

## 参照ファイル

- **導入ガイド（なぜ/判断基準）**: [introduction-guide.md](../../../packages/core/docs/introduction-guide.md) §step 3-4
- **導入ドライバー**: [introducing-stdd skill](../introducing-stdd/SKILL.md)
- **spec テンプレ**: `packages/core/templates/`（feature） / `packages/core/templates/common/`（common）
- **spec 作成スキル**: [documenting-specifications skill](../documenting-specifications/SKILL.md)
- **設定スキーマ**: `packages/core/schema/.stdd.config.schema.json`
