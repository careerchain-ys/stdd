---
name: documenting-specifications
description: |-
  REQUIREMENTS.md（業務要件・機能要件・非機能要件）・TECH_DESIGN.md（技術設計）・TEST_PLAN.md（テスト戦略）と、common 階層の ARCHITECTURE / TABLE_DEFINITION / API_SPEC / DESIGN のテンプレートとガイドラインを提供する。STDD 方法論に従った仕様ドキュメントの作成・更新を支援する。
when_to_use: |-
  「spec」「仕様書」「設計書」「要件定義」「REQUIREMENTS.md」「TECH_DESIGN.md」「TEST_PLAN.md」「テーブル定義」「API仕様」「Spec and Test Driven Development」「STDD」「仕様駆動」に関する作業のとき。
allowed-tools: Read, Write, Edit, Glob, Grep
---

# 仕様ドキュメント（REQUIREMENTS / TECH_DESIGN / TEST_PLAN）の作成

STDD（Spec and Test Driven Development）方法論に従って、REQUIREMENTS.md・TECH_DESIGN.md・TEST_PLAN.md（および common 階層の spec）を作成・更新します。

## Quick Start

### 新機能の仕様書を作成する場合

1. **REQUIREMENTS.md を作成**

   ```
   docs/<app>/<path>/REQUIREMENTS.md
   ```

   - **業務要件 → 機能要件 → 非機能要件** の3層で記述
   - 機能要件は **コア**（2.1 ユースケース＋2.2 業務ルール）＋ **拡張**（2.3 指標定義・2.4 UI/UX・2.5 外部IF、該当機能のみ。無ければ章ごと省略）
   - 各ユースケースに 振る舞い（番号付き手順・主語明示）＋ 受入基準（EARS）を併記し、Priority を付与
   - 指標を持つ機能は §2.3 指標定義表を埋める（算出ロジック・データソース・代理注記）
   - [テンプレート（feature）](templates/requirements.md) を参照

2. **ワイヤーフレーム（WF）を生成**（UI を持つ機能の場合）

   ```
   docs/<app>/<path>/wireframes/
   ```

   - REQUIREMENTS.md のユースケースから HTML ワイヤーフレームを生成（低忠実度・主要文言は実値）
   - [generating-wireframes Skill](../generating-wireframes/SKILL.md) を参照
   - 生成後、REQUIREMENTS.md「2.4 UI/UX・画面」から `./wireframes/index.html` にリンクする

3. **TECH_DESIGN.md を作成**

   ```
   docs/<app>/<path>/TECH_DESIGN.md
   ```

   - 章構成: 概要 / 主要な設計判断（任意）/ 画面項目定義（画面 feature は必須）/ ロジック設計（コア）/ エラーハンドリング戦略 / 非機能要件（任意）
   - データ構造は common の `TABLE_DEFINITION.md`、API は common の `API_SPEC.md` を**参照**（再定義しない）
   - [テンプレート](templates/tech-design.md) を参照

4. **TEST_PLAN.md を作成**

   ```
   docs/<app>/<path>/TEST_PLAN.md
   ```

   - テスト戦略（REQUIREMENTS のユースケース＋ TECH_DESIGN のロジック設計を E2E/Integration/Unit にマッピング）
   - [テンプレート](templates/test-plan.md) を参照

> 横断要素（テーブル定義・API 仕様）は common 階層に集約する。新規テーブル / API が生じたら common の
> [`TABLE_DEFINITION.md`](templates/table-definition-common.md) / [`API_SPEC.md`](templates/api-spec-common.md) を更新し、feature からは参照する。

### 既存機能の仕様書を更新する場合

1. 対応する REQUIREMENTS.md / TECH_DESIGN.md / TEST_PLAN.md を確認
2. 変更内容に応じて更新（テーブル・API の変更は common の TABLE_DEFINITION / API_SPEC に反映）
3. テスト戦略（テスト総数・内訳）は TEST_PLAN.md を更新

## Spec の 2 階層構造（common / feature）

本スキルが扱う feature 階層（機能単位）の spec は、上位の **common 階層**（プロジェクト全体）を前提とする。

| 階層      | ドキュメント | 配置例 |
| ----------- | --- | --- |
| **common**  | `REQUIREMENTS.md`（業務要件）/ `ARCHITECTURE.md`（システム概要）/ `TABLE_DEFINITION.md`（テーブル定義）/ `API_SPEC.md`（API 仕様）/ `DESIGN.md`（任意） | `docs/common/` |
| **feature** | `REQUIREMENTS.md` / `TECH_DESIGN.md` / `TEST_PLAN.md` | `docs/<app>/<feature>/` |

- feature spec は common 階層（サービス目的・アクター・システム構成・テーブル定義・API 仕様）を**前提とし、参照する**。common と矛盾しないこと。**テーブル・API は feature で再定義しない**。
- common 階層のテンプレート: [`requirements-common.md`](templates/requirements-common.md) / [`architecture-common.md`](templates/architecture-common.md) / [`table-definition-common.md`](templates/table-definition-common.md) / [`api-spec-common.md`](templates/api-spec-common.md) / [`design-common.md`](templates/design-common.md)。既存実装からの common spec 作成は `reverse-engineering-common-spec` スキルを参照。
- REQUIREMENTS は common / feature とも **業務要件 → 機能要件 → 非機能要件** の3層で揃える。非機能要件・横断業務ルール・用語は common に集約し、feature は「common 準拠」で参照する。

## ドキュメント配置ルール

| 実装ファイル                  | ドキュメント配置先 |
| ----------------------------- | --- |
| `<app>/app/<path>/page.tsx`   | `docs/<app>/<path>/REQUIREMENTS.md`<br>`docs/<app>/<path>/TECH_DESIGN.md`<br>`docs/<app>/<path>/TEST_PLAN.md` |
| `<app>/components/<name>.tsx` | `docs/<app>/components/<name>/REQUIREMENTS.md`<br>`docs/<app>/components/<name>/TECH_DESIGN.md`<br>`docs/<app>/components/<name>/TEST_PLAN.md` |

**例**:

- 実装: `<app.path>/app/login/page.tsx`（`app.path` は `.stdd.config.yml` の `apps[].path`）
- ドキュメント（`docs.layout.*` テンプレートに従う。`<app.id>` は `apps[].id`）:
  - `docs/<app.id>/login/REQUIREMENTS.md`（必須）
  - `docs/<app.id>/login/TECH_DESIGN.md`（必須。画面項目定義は画面 feature のみ）
  - `docs/<app.id>/login/TEST_PLAN.md`（必須）

## 絶対ルール: SSOT原則（最優先）

⚠️ **Specドキュメントは「現在の最新仕様」だけを記述するSingle Source of Truth（SSOT）である**。履歴・経緯・対応中のissue・「今回の変更」は一切書かないこと。読者は「いま何が正しいか」だけを知りたい。履歴はgit log・PR description・issueに任せる。

### 禁止事項

以下は **すべての spec ドキュメント（REQUIREMENTS / TECH_DESIGN / TEST_PLAN / common 各種）で禁止**:

1. **issueへの言及**: `issue #123 で対応`, `#456 にて追加`, `本issueでは`, `Closes #...` 等
2. **経緯・履歴の記載**: `変更前` / `変更後` / `更新前` / `更新後` / `変更理由` / `削除理由` / `旧仕様` / `〜だったが〜に変更` 等
3. **過程に関する記載**: `今回追加`, `今回変更`, `新たに`, `既存`, `実装済み`, `新規追加`, `今回のスコープ`, `本対応で` 等
4. **作成プロセスの注記**: `このドキュメントはリバースエンジニアリングで作成`, `〜を参考に作成`, `下記をベースに作成` 等
5. **比較形式の記述**: `Before / After`, `旧 / 新`, `変更前後の差分` の形式

### 違反例と修正例

❌ **悪い例（履歴・経緯を記述）**:

```markdown
### メール送信実装

**変更前**: Supabase Auth経由でメール送信
**変更後**: Resend経由でHTMLメール送信
**変更理由**: テンプレートのカスタマイズ性のため
```

✅ **良い例（現在の仕様のみ）**:

```markdown
### メール送信実装

`admin.generateLink()` でリンクを生成し、Resend経由でHTMLメールを送信する。
HTMLテンプレートは `lib/email/templates/` で管理。
```

❌ **悪い例（issue・今回への言及）**:

```markdown
## 機能要件

#### 新規ユーザー登録（issue #1234 で追加）

今回のリリースで対応する新規登録フロー。
```

✅ **良い例**:

```markdown
## 機能要件

#### 新規ユーザー登録

**Priority**: P0
```

### Self-check（コミット前に必ず実行）

書き終えたら以下の禁止語を grep し、ヒットしたら必ず除去すること:

```
# 履歴・経緯・過程の記述
今回 | 既存 | 新規追加 | 実装済み | 変更前 | 変更後 | 更新前 | 更新後
変更理由 | 削除理由 | 旧仕様 | issue # | Closes # | リバースエンジニアリング
本対応 | 本issue | 今回のスコープ | 今回の変更

# テスト/ユースケース再構成の履歴を暗示するフレーミング
に統合 | を統合 | に集約 | を集約 | にまとめ | をまとめ | にマージ | をマージ
別テストに分割 | テストを分けた | 元々は | 当初は | 以前は
```

「ユースケース名」や「アーキテクチャ判断の理由」など現在仕様の説明として正当な「理由」は問題ない。禁止しているのは**変更そのものの理由**（なぜ仕様を変えたか）と、**過去構成からの再編を暗示するフレーミング**。

> 特に注意: テスト戦略表で `✅ (更新に統合)` `2 ケースに集約` `1 テストにまとめる方針` のように「以前は別だったが今はまとめてある」ことを匂わせる表現は SSOT 違反。常に**現在の構成事実のみ**を記述し（例: `プロフィール情報を更新する テスト内のステップとして検証`）、設計判断の理由は注記/設計判断セクションで「**この構成を採る**理由」として書く。

---

## 要確認マーカー（不明点は仮説とセットで明示する）

Spec を書く過程で、確信が持てない／ユーザーに確定してもらう必要がある箇所は、**章を省略したり空欄にしたりせず**、その箇所に **要確認マーカー** を置く。テンプレートの章構成は常に維持し、埋められない部分も「仮説＋要確認」で埋めることで spec の**網羅性を担保**する。

> このマーカーは STDD 全体で**唯一の確認用マーカー**。前方設計（新規・`starting-new-with-stdd`）／逆生成（既存・`reverse-engineering-*`）でも同じ構文を使う。各スキルはここを SSoT として参照する。

### 唯一の構文（可視インライン）

- 標準形（箇条書き・段落の直下）:

  ```markdown
  **⚠️要確認**｜仮説: <現時点で最も妥当と考える答え>／確認: <ユーザーに是非を確かめたいこと>
  ```

- 表・行内の短縮形:

  ```markdown
  | 認証 | Supabase Auth ⚠️要確認(仮説: メール＋OAuth で足りる / 確認: SSO 要件の有無) |
  ```

旧来の `<!-- 未決: ... -->` / `<!-- 要確認: ... -->` / `※要確認` は**使わない**。マーカーは要確認マーカーに一本化する。

### 3 つのルール

1. **必ず仮説とセット**。「要確認」だけを単独で置かない。不明点はまず現時点で最も妥当な**仮説**を立て、その**是非をユーザーに確認させる**形にする（深掘りヒアリングの代わりに、仮説提示で前進する）。
2. **章は省略しない**。テンプレートの構成を維持し、情報が無い箇所も仮説＋要確認マーカーで埋める。空欄・章削除による「見かけ上の完成」を作らない。
3. **可視・一時的**。マーカーはレンダリングで見える一時注記。ユーザーが是非を確定したら、仮説を確定値に書き換えてマーカーを除去する。確定済み spec にマーカーを残さない（SSoT 原則）。

### 例

✅ 良い例（仮説とセット・章を保つ）:

```markdown
### 想定スケール

初期は同時接続 100 程度を想定。
**⚠️要確認**｜仮説: ローンチ後 3 ヶ月で MAU 1,000 規模／確認: 想定ユーザー数と成長見込み。
```

❌ 悪い例（仮説が無い・章を消す）:

```markdown
### 想定スケール

**⚠️要確認**   ← 仮説が無い。何を確認したいかも不明
```

---

## 基本原則

### REQUIREMENTS.md（要件定義書）

**目的**: 機能の要件を「業務要件 → 機能要件 → 非機能要件」の3層で定義し、後続（TECH_DESIGN / テスト / コード）の一次インプットにする

**章立ての3層**:

| 層 | 答える問い | 書くもの |
| --- | --- | --- |
| **業務要件** | なぜ作るか（Why） | ビジネス課題・目標・KPI・対象ユーザー・利用シーン |
| **機能要件** | 何が見える/できるか（What） | **コア**: ユースケース（振る舞い〔手順〕＋受入基準〔EARS〕）・業務ルール ／ **拡張（該当機能のみ）**: 指標定義・UI/UX・外部IF |
| **非機能要件** | どれだけうまく（How well） | 性能・可用性・セキュリティ・アクセシビリティ（機能固有のみ。共通は common §6 を参照） |

**記法**:

- 各ユースケースは **振る舞い（番号付き手順）＋ 受入基準（EARS）** の2部構成で記述する
- **振る舞い → 番号付き手順**（1. 2. 3. …）。各ステップの主語を明示（「ユーザーは〜」「システムは〜」）し、ユーザー操作とシステム応答の主要フロー（ハッピーパス＋主要分岐）を表す。E2E テストの骨格になる。抽象（ビジネス言語）に保ち、テストデータ・セレクタはテストコード側に置く
- **受入基準・業務ルール → EARS**（常時 / WHEN / WHILE / IF / WHERE）。フローが満たすべき詳細条件・例外・データ制約を網羅。手順と重複させず、エッジケースは IF / WHERE で統合

**記述しない内容**:

- データモデル・集計実装・API・画面項目 → TECH_DESIGN.md（データ構造・API は common の TABLE_DEFINITION / API_SPEC）
- 実装ファイルへの参照・関数名・クラス名、テスト実装の詳細

### TECH_DESIGN.md（設計書）

**目的**: 機能（画面単位）の技術設計。実装者が**ロジックを起こせる粒度**で記述する。

**章構成**: 概要 / 主要な設計判断（任意）/ 画面項目定義（画面 feature は必須）/ ロジック設計（コア）/ エラーハンドリング戦略 / 非機能要件（任意）

**記述する内容**:

- **ロジック設計**: 集計式・変換・ドメインルール・トランザクション境界・副作用・複数テーブル横断の流れ（手順 / 擬似コード / 計算式）
- **画面項目定義**: UI × バリデーション × DB マッピング（画面 feature のみ。DB カラムは TABLE_DEFINITION を参照）
- **エラーハンドリング戦略**: API / 処理の失敗を本機能がどう捌くか
- データ構造・API は common の `TABLE_DEFINITION.md` / `API_SPEC.md` を**参照**（再定義しない）

**記述しない内容**:

- 実装例・コード例（関数・メソッドの実装、Server Actions の実装）。擬似コード・型 I/F・計算式は可
- テーブル・カラム定義（→ common `TABLE_DEFINITION.md`）/ API 契約（→ common `API_SPEC.md`）
- テスト戦略（→ `TEST_PLAN.md`）

### TEST_PLAN.md（テスト計画書）

**目的**: 機能のテスト戦略。**REQUIREMENTS のユースケース**と **TECH_DESIGN のロジック設計（その他処理フロー）**の両方をテストレベル（E2E / Integration / Unit）に漏れなくマッピングする。

**記述する内容**:

- §1 ユースケース別テスト戦略（REQUIREMENTS §2.1 の全ユースケース × テストレベル × 根拠）
- §2 その他処理フロー別テスト戦略（TECH_DESIGN §4.2 がある場合）
- **テスト総数と内訳**（例: 合計 33 件 - Unit 18 件, Integration 9 件, E2E 6 件）

### common 階層の技術ドキュメント

- **ARCHITECTURE.md**: システム概要（構成 / スタック / 連携 / セキュリティ / インフラ）。データモデル・API は持たない。
- **TABLE_DEFINITION.md**: 全テーブル定義の SSoT（カード形式・ER 図なし）。feature が参照する。
- **API_SPEC.md**: API 契約の SSoT（OpenAPI 風 Markdown）。feature が参照する。
- **DESIGN.md**（任意）: デザイン標準。

### Priority（優先度）ガイドライン

| Priority | 定義                                                     | テスト戦略                 |
| -------- | -------------------------------------------------------- | -------------------------- |
| **P0**   | Critical Path - ビジネスに直結、高頻度、複数システム統合 | E2E 必須 + Integration     |
| **P1**   | Important - 重要だが Critical Path ではない              | E2E 検討、Integration 必須 |
| **P2**   | Nice to Have - エッジケース、低頻度                      | Integration または Unit    |

## 次のステップ

Specドキュメント（REQUIREMENTS.md + TECH_DESIGN.md）の作成・レビュー完了後:

1. **PLANドキュメントを作成** → [documenting-plans Skill](../documenting-plans/SKILL.md)
2. PLANドキュメントに従ってテスト作成・実装を進める

## 参照ファイル

詳細なテンプレートとガイドは以下を参照:

- **テンプレート（feature）**
  - [REQUIREMENTS.md](templates/requirements.md)
  - [TECH_DESIGN.md](templates/tech-design.md) ← 概要 / 設計判断 / 画面項目定義 / ロジック設計 / エラーハンドリング / 非機能要件
  - [TEST_PLAN.md](templates/test-plan.md) ← テスト戦略
- **テンプレート（common）**
  - [REQUIREMENTS.md](templates/requirements-common.md)
  - [ARCHITECTURE.md](templates/architecture-common.md) ← システム概要
  - [TABLE_DEFINITION.md](templates/table-definition-common.md) ← テーブル定義
  - [API_SPEC.md](templates/api-spec-common.md) ← API 仕様
  - [DESIGN.md](templates/design-common.md) ← デザイン標準（任意）
- **関連スキル**
  - [generating-wireframes Skill](../generating-wireframes/SKILL.md) ← UI を持つ機能の WF 生成
- **ガイド**
  - [STDD違反例と対策](guides/stdd-violations.md) ← 実装開始前に必読
  - [エラーハンドリングガイド](guides/error-handling.md)
- **次のステップ**
  - [PLANドキュメント作成スキル](../documenting-plans/SKILL.md)

## When NOT to Use This Skill

以下の場合はこのスキルを使用しない:

- **単純なバグ修正**: 仕様変更を伴わない場合
- **リファクタリング**: 外部から見える挙動が変わらない場合
- **ドキュメント修正のみ**: README や CLAUDE.md の更新
- **テストの追加のみ**: 既存仕様に基づくテスト追加（ただし TECH_DESIGN.md のテスト総数は更新が必要）

## チェックリスト

### REQUIREMENTS.md 作成時

```
□ 業務要件・機能要件・非機能要件の3層が揃っている（非機能が「common 準拠」でも明記）
□ 各記述が3層のいずれかに分類されている（フラットな未分類項目が無い）
□ 全ユースケースに Priority＋振る舞い（番号付き手順）＋受入基準（EARS）がある
□ 振る舞い手順は主要フロー（抽象）に保たれ、テストデータ・セレクタが混入していない
□ 受入基準（EARS）が詳細条件・例外・データ制約を網羅している（エッジケースは IF/WHERE）
□ 指標を持つ機能は §2.1 指標定義表が埋まっている（算出/データソース/代理注記）
□ 近似・代理指標は「注記表示=必須」が明記されている
□ UI/UX デザイン（HTML ワイヤーフレームを生成し「2.5 UI/UX デザイン」からリンク）→ generating-wireframes Skill
□ 受入基準に曖昧語（適切に/正しく）が無い／How（テーブル名・関数・API）が混入していない
□ スコープ外
```

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
