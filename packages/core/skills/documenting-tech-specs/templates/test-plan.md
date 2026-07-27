# TEST_PLAN.md テンプレート（feature）

**目的**: 機能（画面単位）のテスト戦略。**REQUIREMENTS のユースケース**と **TECH_DESIGN のロジック設計**の両方を、テストレベル（E2E / Integration / Unit）に漏れなくマッピングする。

**配置**: `docs/<app>/<path>/TEST_PLAN.md`（`.stdd.config.yml` の `docs.layout.test_plan` に従う）

## 章立ての骨格

| 章 | 内容 | 適用 |
| --- | --- | --- |
| 1. ユースケース別テスト戦略 | REQUIREMENTS §2.1 の全ユースケース × テストレベル × 根拠 | 常に |
| 2. その他処理フロー別テスト戦略 | TECH_DESIGN §4.2 その他処理フロー × テストレベル × 根拠 | TECH_DESIGN に §4.2 がある場合 |

- **網羅性の二本立て**: REQUIREMENTS のユースケース（§1）と TECH_DESIGN ロジック設計のその他処理フロー（§2）の**両方**を漏れなくカバーする。
- 各レベルを選ぶ / 選ばない**根拠（Rationale）**を必ず書く。

## テンプレート構造

````markdown
# [機能名] テスト計画

> ビジネス要件は [`REQUIREMENTS.md`](./REQUIREMENTS.md)、技術設計は [`TECH_DESIGN.md`](./TECH_DESIGN.md) を参照。

## 1. ユースケース別テスト戦略

REQUIREMENTS §2.1 の**全ユースケースを 1 行ずつ**列挙する（**対象ID は REQUIREMENTS §2.1 の `**ID**:` 行と一致**・ユースケース名も同名・Priority も引く）。
**振る舞い（手順）→ E2E の骨格**、**受入基準（EARS）→ Unit / Integration** で担保するのが基本対応。

| 対象ID | ユースケース（REQUIREMENTS §2.1） | Priority | E2E | Integration | Unit | 根拠 |
| --- | --- | --- | --- | --- | --- | --- |
| UC-<feature>-01 | [ユースケース名] | P0 | ✅ | ✅ | ✅ | Critical path・ビジネス直結・複数システム統合 |
| UC-<feature>-02 | [ユースケース名] | P1 | ⚠️ 検討 | ✅ | ✅ | 頻度高い・Integration 必須・E2E はコストで判断 |
| UC-<feature>-03 | [ユースケース名] | P2 | ❌ | ⚠️ | ✅ | 低頻度・Unit で十分 |

> **テストコードへの ID タグ付け（必須）**: 各テストのタイトルに対象ID をブラケットで含める（例: `describe('[UC-<feature>-01] …')`）。フレームワーク非依存で grep 可・テストレポートにも表示され、トレーサビリティ監査の「テストリンク」になる。計画（✅）した ID を持つテストが存在しないと「テスト実装漏れ」として検知される。

> 受入基準（EARS）の主要条件（例外・境界・データ制約）は、対応する Unit / Integration の根拠列に検証観点として落とす。

## 2. その他処理フロー別テスト戦略

> TECH_DESIGN §4.2「その他処理フロー」がある場合のみ。各処理フローを 1 行ずつ列挙する（無ければ本章を削除）。

| 対象ID | 処理フロー（TECH_DESIGN §4.2） | E2E | Integration | Unit | 根拠 |
| --- | --- | --- | --- | --- | --- |
| FL-<feature>-01 | [処理フロー名] | ❌ | ✅ | ✅ | バッチ / 内部ロジック・境界値は Unit で網羅 |
````

## 記述基準

- **対象ID・ユースケース名は REQUIREMENTS §2.1 と一致させ、全ユースケースを漏れなく 1 行ずつ記載する**（ID で REQUIREMENTS ↔ TEST_PLAN を 1:1 で機械追跡できるようにする）。Priority も REQUIREMENTS から引く。
- **TECH_DESIGN §4.2 その他処理フローがある場合、§2 に全フロー（対象ID `FL-<feature>-NN`）を 1 行ずつ記載する**（TECH_DESIGN ロジック設計 ↔ TEST_PLAN も ID で 1:1 追跡可能にする）。
- **テストコードには対象ID をタイトルにタグ付けする**（`[UC-<feature>-NN]` / `[FL-<feature>-NN]`）。計画とテスト実体を ID で突合し、抜け漏れ・孤児テストを機械検知する。
- **振る舞い（手順）→ E2E、受入基準（EARS）→ Unit / Integration** の役割で対応づける。
- テストレベルの選択は「✅ 実施 / ⚠️ 検討 / ❌ 不要」で示し、根拠列を空にしない。
- ロジック設計の検証観点（集計式・境界値）は対応する Unit / Integration の根拠に紐づける。

## 記述しない内容（責務分界）

- ユースケース本体（振る舞い＋受入基準） → `REQUIREMENTS.md`
- ロジック設計・画面項目 → `TECH_DESIGN.md`
- テストの実装コード → テストファイル本体
