---
name: reverse-engineering-common-spec
description: |-
  既存プロジェクトにSTDDを導入する際、コードベース全体をリバースエンジニアリングしてcommonティアのSpec（docs/common/REQUIREMENTS.md + docs/common/ARCHITECTURE.md）を作成するスキル。サービス概要・システム構成・リポジトリ構成・レイヤ規約・データモデルを俯瞰する正典を、導入時に一度だけ生成する。「STDD導入」「stdd導入」「共通spec生成」「commonティア」「プロジェクト全体のリバースエンジニアリング」「ARCHITECTURE.md作成」「アーキテクチャのドキュメント化」「既存プロジェクトにstdd」に関する作業で使用。機能/ページ単位のリバースエンジニアリングには reverse-engineering-feature-spec を使用する。
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# 共通spec リバースエンジニアリングスキル

既存（稼働中）プロジェクトに STDD を導入する際、コードベース全体を input にして **common ティア**の Spec を作成する。

| 出力 | 内容 |
| ---- | ---- |
| `docs/common/REQUIREMENTS.md` | サービス概要・登場アクター・アプリ構成（プロジェクト全体のビジネス要件） |
| `docs/common/ARCHITECTURE.md` | システム構成・リポジトリ構成・レイヤ規約・データモデル（プロジェクト全体の技術設計） |

テンプレートは `packages/core/templates/common/REQUIREMENTS.md` / `ARCHITECTURE.md` を参照する。

## 位置づけ — 導入時に一度だけ

common ティアはプロジェクト全体で 1 組しか存在しない正典であり、本スキルは **STDD 導入時に一度だけ**実行する想定。
作成後の更新（アーキテクチャ変更時など）は本スキルではなく、通常の Spec 更新として `documenting-specifications` で扱う。

```
STDD 導入フロー（既存プロジェクト）

1. reverse-engineering-common-spec  ← 本スキル（一度だけ）
        ↓  common ティアが揃う
2. reverse-engineering-feature-spec ← 機能ごとに繰り返す
        ↓
3. auto-implement                    ← 以降の新機能は順流 STDD
```

**順序の理由**: 先に common ティア（レイヤ規約・共有ドメインモデル・テーブル一覧）を固定しておくと、後続の機能単位リバース（`reverse-engineering-feature-spec`）の精度と速度が上がる。

---

## 最重要原則 — 実装・設定が真実

common ティアでも **実装が真実（Source of Truth）** である。推測や理想論で書かず、必ず一次情報を確認してから書く。
feature ティアと違い、確認する一次情報は **UI 文言ではなく構成・設定・型定義** である。

| 記述する内容 | 確認元（一次情報） | よくある間違い |
| ------------ | ------------------ | -------------- |
| アプリ構成・責務 | トップレベルディレクトリ / README | 想像でアプリ名・責務を書く |
| パッケージ分割 | `package.json` の workspaces / 依存定義 | モジュール境界を推測で書く |
| レイヤ規約・依存方向 | `domain/` 配下の実構成・lint ルール | 一般論の Clean Architecture を書く |
| 外部サービス連携 | 環境変数・SDK の import 箇所 | 使っていないサービスを書く／使用中を漏らす |
| テーブル一覧・ER | 生成された DB 型定義（`database.types.ts` 等） | テーブル名・カラム名を想像で書く |
| デプロイ・環境 | CI/CD 設定（`.github/workflows` 等） | ブランチ→環境マッピングを推測で書く |

---

## 読む順序とチェックリスト

`ARCHITECTURE.md` の目次がそのまま読む順序になる。

### 1. システム構成（`REQUIREMENTS.md` のサービス概要・アクターもここで把握）

```
□ README / トップレベルディレクトリ構成 → サービスの目的・アプリ構成
□ デプロイ設定 (vercel.json / Dockerfile / .github/workflows) → 環境とブランチ戦略
□ 環境変数・SDK の import → 外部サービス連携 (認証 / DB / ストレージ / メール / 監視 等)
```

### 2. リポジトリ構成

```
□ package.json の workspaces / モジュール分割
□ 依存管理ルール (どの依存がどこに置かれているか、アプリ間 import 制限の有無)
□ 共有パッケージ (packages/shared 等) の責務
```

### 3. レイヤードアーキテクチャ

```
□ domain/ 配下の構成 (models / repository / service / ports)
□ 依存方向ルール (UI → Service → Repository → DB 等)、禁止依存
□ 代表的なデータフロー 1 本 (Server Action / API → Service → Repository)
```

### 4. データモデル・DB設計

```
□ 生成された DB 型定義 (database.types.ts 等) を正としてテーブルを列挙
□ ドメイングループへの分類、中心テーブルごとの ER 図
□ 設計方針 (論理削除 / 主キー / 時系列カラム / マイグレーション規約)
```

---

## 確信が持てない箇所は要確認マーカーを残す

実装からの読み取りに確信が持てない箇所は `<!-- 要確認: ... -->` のインラインコメントで明示する。
これは**一時的な注記**であり、人間レビューで確定したら除去する（恒久的に残さない）。SSoT 原則上、確定済みの Spec に作成プロセスや未確定メモを残してはならない。

```markdown
- **外部ウォレット連携**: 関連テーブルと RPC が存在する。<!-- 要確認: 現行稼働範囲（本番で有効か） -->
```

---

## 完了条件

```
□ docs/common/REQUIREMENTS.md を作成（サービス概要 / アクター / アプリ構成）
□ docs/common/ARCHITECTURE.md を作成（システム構成 / リポジトリ / レイヤ / データモデル）
□ テーブル一覧は生成された型定義ファイルと一致している
□ 固有名詞・社外秘の値を不要に含めていない（公開を想定する場合）
□ 要確認マーカーは「人間に確認すべき項目」としてレビュー依頼にまとめた
```

---

## When NOT to Use This Skill

- **機能 / ページ単位のリバースエンジニアリング**: `reverse-engineering-feature-spec` を使用
- **新規機能の仕様策定**: `documenting-specifications` を使用
- **common ティア作成後のアーキテクチャ更新**: 通常の Spec 更新として `documenting-specifications` で扱う

---

## 次のステップ

1. **機能単位のリバース** → `reverse-engineering-feature-spec`（common ティアを前提に、機能ごとに繰り返す）
2. **新機能の実装** → `auto-implement`（以降は Spec → Test → 実装 の順流 STDD）

---

## 参照ファイル

- **common テンプレート**: `packages/core/templates/common/REQUIREMENTS.md` / `ARCHITECTURE.md`
- **2 ティア構造の解説**: `packages/core/docs/stdd-methodology.md` §3.0
- **機能単位リバース**: [reverse-engineering-feature-spec skill](../reverse-engineering-feature-spec/SKILL.md)
- **Specテンプレート**: [documenting-specifications skill](../documenting-specifications/SKILL.md)
