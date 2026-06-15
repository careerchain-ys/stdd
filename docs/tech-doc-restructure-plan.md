# 技術関連ドキュメントの再編 — 設計メモ（SSoT）

> 本メモは「技術関連ドキュメント（ARCHITECTURE / TECH_DESIGN / 画面項目定義 / テスト戦略）」の
> 章構成・ラインナップ再編における**確定設計**を記録する。複数 PR を跨ぐ作業の唯一の真実源（SSoT）。
> 作業完了後はこのメモを削除してよい（恒久ドキュメントではない）。

## 1. 背景・目的

- feature `TECH_DESIGN.md` に「データモデル」「API設計」「テスト戦略」「非機能要件」が同居し、
  common `ARCHITECTURE.md` ともデータモデルが二重化していた。
- 画面項目定義（`SCREEN_ITEMS_DEFINITION.md`）が任意の別ファイルで、TECH_DESIGN と分離していた。
- テンプレが技術スタック依存（REST/TS型/NextAuth 前提）で、ユースケース駆動化した REQUIREMENTS と非整合。
- → **共通設計（common）と個別設計（feature/画面単位）の責務を整理し、横断要素（テーブル定義・API仕様）を
  common に集約、feature は参照する**構成へ再編する。

## 2. To-be ドキュメント・ラインナップ

### 共通設計（common 階層）

| ドキュメント | 状態 | 役割 |
| --- | --- | --- |
| `REQUIREMENTS.md` | 既存・不変 | 全体の業務 / 機能 / 非機能要件 |
| `ARCHITECTURE.md` | 再編（命名維持） | システム概要に集約（データモデル・API は外出し） |
| `TABLE_DEFINITION.md` | 新設 | 全テーブル定義の SSoT（feature から参照） |
| `API_SPEC.md` | 新設 | API 仕様の SSoT（OpenAPI 風 Markdown、feature から参照） |
| `DESIGN.md` | 新設・任意 | デザイン標準 |

### 個別設計（feature 階層・画面単位）

| ドキュメント | 状態 | 役割 |
| --- | --- | --- |
| `REQUIREMENTS.md` | 既存・不変 | ユースケース駆動 |
| `TECH_DESIGN.md` | 再編 | 概要 / 設計判断 / 画面項目定義 / 処理ロジック / エラーハンドリング / 非機能要件 |
| `TEST_PLAN.md` | 新設 | テスト戦略（旧 TECH_DESIGN §8 を移管） |
| ~~`SCREEN_ITEMS_DEFINITION.md`~~ | 廃止 | 内容を TECH_DESIGN「画面項目定義」へ吸収 |

## 3. 各ドキュメントの確定章構成

### ARCHITECTURE.md（common）

`ref/システム概要.md` の節構成をベースにブラッシュアップ。リポジトリ構成・レイヤ規約は 1.1 に内包。

```
1. システム概要
   1.1 システム構成概要（全体構成・特徴・リポジトリ構成・レイヤ規約を内包）
   1.2 使用技術スタック
   1.3 システム間連携
   1.4 データフロー概要（全体の代表フロー）
   1.5 セキュリティ概要
   1.6 インフラ構成概要
付録・関連ドキュメント
```

- 「※要確認」インラインコメント、`[可]/[近似]` 等の確度注記の運用をガイドに含める。
- データモデル → `TABLE_DEFINITION.md` / API → `API_SPEC.md` へ外出し（ARCHITECTURE には持たない）。

### TABLE_DEFINITION.md（common・新設）

- テーブルごとに「カード（見出し＋表）」で表現。**ER 図は持たない**（当面不要）。
- 列は `カラム名 / データ型 / NULL / 説明`。PK はマーク（🔑）で示す。

```
## <table>   （PK: <pk> ・ <n>カラム）

| カラム名 | データ型 | NULL | 説明 |
| --- | --- | --- | --- |
| 🔑 <col> | UUID | NOT NULL | ... |
| <col> | VARCHAR(255) | 許容 | ... |
```

### API_SPEC.md（common・新設）

- OpenAPI/Swagger 風の **Markdown テーブル**（実 YAML ではない）。非 REST（RPC/Server Actions）も表現可。
- エンドポイント単位に: パス / メソッド / 概要 / パラメータ / リクエスト / レスポンス / **エラーコード表**。
- API を持たない構成（例: フロントから DB 直接参照）では本書は空 / N.A. でよい。

### DESIGN.md（common・新設・任意）

- デザイン標準（トークン / コンポーネント規約 / レイアウト原則）。任意。

### TECH_DESIGN.md（feature）

```
1. 概要                  … 機能の目的・スコープ・関連ドキュメント参照（TABLE_DEFINITION / API_SPEC）
2. 主要な設計判断        … 任意：この機能特有の判断（選択＋理由）のみ。なければ章ごと省略
3. 画面項目定義          … 画面 feature は必須 / 非画面 feature は省略。UI × Validation × DB Mapping
4. 処理ロジック          … コア：集計式・変換・ドメインルール・トランザクション境界・副作用・
                            複数テーブル横断の流れを手順 / 擬似コードで（実コードは不可）
5. エラーハンドリング戦略 … API / 処理の失敗を本機能がどう捌くか（リトライ / トースト / リダイレクト等）
6. 非機能要件            … 任意：旧セキュリティ＋パフォーマンスを統一。REQUIREMENTS に記載がある場合のみ実現方法
```

### TEST_PLAN.md（feature・新設）

- 旧 TECH_DESIGN §8（ユースケース別テスト戦略 / テストファイル構成）を移管。feature 単位。

## 4. 責務分界（重複防止の肝）

| 対象 | SSoT |
| --- | --- |
| データ構造（テーブル・カラム） | `TABLE_DEFINITION.md`（common） |
| API 入出力契約・エラーコードカタログ | `API_SPEC.md`（common） |
| **どう計算・処理するか**（アルゴリズム） | TECH_DESIGN §処理ロジック（feature） |
| API レスポンス / 失敗を本機能がどう捌くか | TECH_DESIGN §エラーハンドリング（feature） |
| 画面項目 × バリデーション × DB マッピング | TECH_DESIGN §画面項目定義（feature・画面のみ） |
| テスト戦略 | `TEST_PLAN.md`（feature） |
| システム全体構成・スタック・連携・セキュリティ・インフラ | `ARCHITECTURE.md`（common） |

## 5. 移管マップ（from → to）

| 現状 | 移管先 |
| --- | --- |
| feature TECH_DESIGN §1 機能固有アーキテクチャ | 削除（→ §1 概要 + §4 処理ロジックへ） |
| feature TECH_DESIGN §3 データモデル | `TABLE_DEFINITION.md`（参照化） |
| feature TECH_DESIGN §4 API設計 | `API_SPEC.md`（参照化） |
| feature TECH_DESIGN §5 エラーハンドリング | TECH_DESIGN §5 として残置（目的を「API レスポンスのハンドリング」に明確化） |
| feature TECH_DESIGN §6/§7 セキュリティ / パフォーマンス | TECH_DESIGN §6 非機能要件に統一・任意化 |
| feature TECH_DESIGN §8 テスト戦略 | `TEST_PLAN.md` |
| `SCREEN_ITEMS_DEFINITION.md` 全体 | TECH_DESIGN §3 画面項目定義（必須化） |
| common ARCHITECTURE §4 データモデル | `TABLE_DEFINITION.md` |
| common ARCHITECTURE §2 リポジトリ / §3 レイヤ | ARCHITECTURE §1.1 システム構成概要へ内包 |

## 6. docs.layout キーの増減（schema / config）

- 追加: `common_table_definition` / `common_api_spec` / `common_design`（任意）/ `test_plan`
- 維持: `common_architecture`（ファイル名 `ARCHITECTURE.md` のまま）
- 削除: `screen_items`

## 7. 決定ログ

| 論点 | 決定 |
| --- | --- |
| common 技術ドキュメントの命名 | `ARCHITECTURE.md` 維持（データ・API 外出しで純粋な構成情報に絞られるため） |
| リポジトリ構成 / レイヤ規約 | 独立章にせず §1.1 システム構成概要へ内包 |
| 非画面 feature の画面項目定義 | 画面 feature は必須、非画面 feature は章ごと省略 |
| API_SPEC のフォーマット | Markdown（OpenAPI 風テーブル）。実 YAML ではない |
| エラーハンドリング戦略 | feature TECH_DESIGN にセクション残置（API レスポンスのハンドリング方針） |
| バックエンド処理ロジックの居場所 | feature TECH_DESIGN に「処理ロジック」章を新設（コア） |
| ER 図 | TABLE_DEFINITION では当面不要 |

## 8. 進め方（フェーズ & チェックリスト）

PR 分割: **(A) Phase 1–2** / **(B) Phase 3–4** / **(C) Phase 5**。

```
Phase 0  設計確定（本メモ）
  [x] to-be 構成・命名・docs.layout キー・処理ロジック章を確定

Phase 1  テンプレ層
  [x] ARCHITECTURE.md テンプレを ref ベースに再編
  [x] TABLE_DEFINITION.md テンプレ新設（カード形式・ER 図なし）
  [x] API_SPEC.md テンプレ新設（OpenAPI 風 Markdown）
  [x] DESIGN.md テンプレ新設（任意）
  [x] TECH_DESIGN.md（feature）テンプレ再編（概要 / 設計判断 / 画面項目定義 / 処理ロジック / エラー / 非機能）
  [x] TEST_PLAN.md テンプレ新設
  [x] SCREEN_ITEMS_DEFINITION.md を廃止（内容を TECH_DESIGN へ吸収）

Phase 2  設定・スキーマ層
  [x] schema の docs.layout キー増減（追加: common_table_definition/common_api_spec/common_design/test_plan、test_plan は必須化）
  [x] .stdd.config.yml.tpl（minimal / nextjs-supabase-starter）更新

Phase 3  スキル / エージェント層
  [x] documenting-specifications SKILL.md（doc lineup・必須/任意・参照付替え）
  [x] reverse-engineering-* / tailoring-spec-format / generating-wireframes / introducing-stdd
  [x] auto-implement 系（テスト戦略 → TEST_PLAN）/ 6 agents / implementing-ui プラグイン / spec-first フック除外リスト

Phase 4  方法論・ガイド層
  [x] stdd-methodology.md（2 階層構造・doc lineup・命名）
  [x] guides（new/existing）/ AGENTS.md / README（root/core）

Phase 5  サンプル
  [x] nextjs-supabase-starter: ARCHITECTURE 再編 + TABLE_DEFINITION 追加（API_SPEC/DESIGN サンプルは必要時生成）

Phase 6  検証
  [x] schema 妥当 / sync-assets 成功 / spec-first フックテスト 15/15 / 残存参照ゼロ
```
