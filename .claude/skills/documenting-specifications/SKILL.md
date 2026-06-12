---
name: documenting-specifications
description: |-
  REQUIREMENTS.md（業務要件・機能要件・非機能要件）と TECH_DESIGN.md（技術設計・テスト戦略）のテンプレートとガイドラインを提供する。STDD 方法論に従った仕様ドキュメントの作成・更新を支援する。
when_to_use: |-
  「spec」「仕様書」「設計書」「要件定義」「REQUIREMENTS.md」「TECH_DESIGN.md」「Spec and Test Driven Development」「STDD」「仕様駆動」に関する作業のとき。
allowed-tools: Read, Write, Edit, Glob, Grep
---

# 仕様ドキュメント（REQUIREMENTS / TECH_DESIGN）の作成

STDD（Spec and Test Driven Development）方法論に従って、REQUIREMENTS.md と TECH_DESIGN.md を作成・更新します。

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

   - 技術設計、テスト戦略（ユースケースを E2E/Integration/Unit にマッピング）を記述
   - [テンプレート](templates/tech-design.md) を参照

4. **SCREEN_ITEMS_DEFINITION.md を作成（オプション）**

   ```
   docs/<app>/<path>/SCREEN_ITEMS_DEFINITION.md
   ```

   - 画面項目定義（フォーム項目、バリデーション、表示形式）を記述
   - REQUIREMENTS.md の派生ドキュメントとして、UI詳細が必要な場合に作成

### 既存機能の仕様書を更新する場合

1. 対応する REQUIREMENTS.md と TECH_DESIGN.md を確認
2. 変更内容に応じて両方を更新
3. テスト戦略（テスト総数・内訳）を更新

## Spec の 2 ティア構造（common / feature）

本スキルが扱う REQUIREMENTS.md / TECH_DESIGN.md は **feature ティア**（機能単位）の spec である。
その上位に、プロジェクト全体を俯瞰する **common ティア** が存在する。

| ティア      | What / Why                | How                       | 配置例                                |
| ----------- | ------------------------- | ------------------------- | ------------------------------------- |
| **common**  | `REQUIREMENTS.md` (全体版) | `ARCHITECTURE.md` (全体版) | `docs/common/`                        |
| **feature** | `REQUIREMENTS.md`         | `TECH_DESIGN.md`          | `docs/<app>/<feature>/`               |

- feature spec は common ティア（サービス目的・アクター・システム構成・レイヤ規約・データモデル）を**前提とする**。common と矛盾しないこと。
- common ティアのテンプレートは [`templates/requirements-common.md`](templates/requirements-common.md) を参照。既存実装からの common spec 作成は `reverse-engineering-common-spec` スキルを参照。
- common / feature とも章立ては **業務要件 → 機能要件 → 非機能要件** の3層で揃える。非機能要件・横断業務ルール・用語は common に集約し、feature は「common 準拠」で参照する。

## ドキュメント配置ルール

| 実装ファイル                  | ドキュメント配置先                                                                                                                                                   |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `<app>/app/<path>/page.tsx`   | `docs/<app>/<path>/REQUIREMENTS.md`<br>`docs/<app>/<path>/TECH_DESIGN.md`<br>`docs/<app>/<path>/SCREEN_ITEMS_DEFINITION.md`（任意）                                  |
| `<app>/components/<name>.tsx` | `docs/<app>/components/<name>/REQUIREMENTS.md`<br>`docs/<app>/components/<name>/TECH_DESIGN.md`<br>`docs/<app>/components/<name>/SCREEN_ITEMS_DEFINITION.md`（任意） |

**例**:

- 実装: `<app.path>/app/login/page.tsx`（`app.path` は `.stdd.config.yml` の `apps[].path`）
- ドキュメント（`docs.layout.*` テンプレートに従う。`<app.id>` は `apps[].id`）:
  - `docs/<app.id>/login/REQUIREMENTS.md`（必須）
  - `docs/<app.id>/login/TECH_DESIGN.md`（必須）
  - `docs/<app.id>/login/SCREEN_ITEMS_DEFINITION.md`（任意）

## 絶対ルール: SSOT原則（最優先）

⚠️ **Specドキュメントは「現在の最新仕様」だけを記述するSingle Source of Truth（SSOT）である**。履歴・経緯・対応中のissue・「今回の変更」は一切書かないこと。読者は「いま何が正しいか」だけを知りたい。履歴はgit log・PR description・issueに任せる。

### 禁止事項

以下は **REQUIREMENTS.md / TECH_DESIGN.md / SCREEN_ITEMS_DEFINITION.md のいずれでも禁止**:

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

- データモデル・集計実装・API → TECH_DESIGN.md ／ 画面項目 × バリデーション × DB マッピング → SCREEN_ITEMS_DEFINITION.md
- 実装ファイルへの参照・関数名・クラス名、テスト実装の詳細

### TECH_DESIGN.md（設計書）

**目的**: 機能実装のための技術設計とテスト戦略

**記述する内容**:

- 技術視点（How）
- テスト戦略: 各ユースケースをテストレベルにマッピング
- アーキテクチャ、API 設計、エラーハンドリング
- **テスト総数と内訳**（例: 合計 33 件 - Unit 18 件, Integration 9 件, E2E 6 件）

**記述しない内容**:

- 実装例・コード例（関数・メソッドの実装、Server Actions の実装、処理フローのコード）
- ただし、**型定義・インターフェース**（Entity型、UI型、Request/Response型）や **データモデル**（ER図）はコードブロックで記述可

### SCREEN_ITEMS_DEFINITION.md（画面項目定義書）- オプション

**目的**: 画面の入力項目・表示項目の詳細定義

**作成タイミング**: 以下の場合に作成を検討

- フォーム項目が多い画面
- 複雑なバリデーションルールがある
- 表示形式（フォーマット、単位など）の定義が必要

**記述する内容**:

- 項目ID、項目名、データ型
- 入力/表示の区分
- バリデーションルール（必須、桁数、形式など）
- 表示形式（日付フォーマット、通貨フォーマットなど）
- 初期値、選択肢

**記述しない内容**:

- ユースケース（REQUIREMENTS.md に記載）
- 技術設計・実装詳細（TECH_DESIGN.md に記載）

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

- **テンプレート**
  - [REQUIREMENTS.md テンプレート（feature）](templates/requirements.md)
  - [REQUIREMENTS.md テンプレート（common）](templates/requirements-common.md)
  - [TECH_DESIGN.md テンプレート](templates/tech-design.md)
  - [SCREEN_ITEMS_DEFINITION.md テンプレート](templates/screen-items-definition.md) ← 画面項目定義（オプション）
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
□ SCREEN_ITEMS_DEFINITION.md が必要か検討（フォーム項目が多い場合）
```

### TECH_DESIGN.md 作成時

```
□ アーキテクチャ図（Mermaid）
□ 主要な設計判断（Decision）- 選択と理由を明記
□ データモデル（ER 図、TypeScript 型定義）
□ API 設計（エンドポイント、型定義）
□ エラーハンドリング戦略
□ テスト戦略（ユースケース別テストマッピング）
□ テスト総数と内訳（Unit/Integration/E2E）
□ 実装例・コード例が含まれていないことを確認（型定義・I/F は除く）
□ SCREEN_ITEMS_DEFINITION.md が存在する場合、整合性を確認
```

### SCREEN_ITEMS_DEFINITION.md 作成時（任意）

```
□ 画面単位で項目を整理
□ 各項目に一意のIDを付与
□ データ型を明記（string, number, date, select など）
□ バリデーションルール（必須、桁数、形式、範囲）
□ 表示形式（日付フォーマット、通貨、単位など）
□ 選択肢がある場合はすべての選択肢を列挙
□ REQUIREMENTS.md の UI/UX デザインと整合性を確認
```
