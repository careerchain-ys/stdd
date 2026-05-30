---
name: introducing-stdd
description: |-
  既存（稼働中）プロジェクトへの STDD 導入を、Claude セッションで段階的に駆動するスキル。導入ガイドに従い、共通spec生成→機能インベントリ→代表機能リバース→フォーマット策定→機能ループ→順行運用への移行までを、既存スキル（reverse-engineering-common-spec / reverse-engineering-feature-spec / auto-implement / verify-consistency）を順に呼びながら進める。進捗は導入PLANで保持し、セッションを跨いで再開できる。「STDD導入」「stdd導入を進める」「既存プロジェクトにstddを入れる」「導入の続き」「introduce stdd」「導入ブートストラップ」に関する作業で使用。単一機能のリバースのみなら reverse-engineering-feature-spec を直接使う。
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# STDD 導入ドライバースキル

既存プロジェクトへの STDD 導入を、セッションで 1 ステップずつ進めるための**薄い駆動役**。
自前の実装ロジックは持たず、各ステップで**既存スキルを順に呼び**、人間判断ポイントで停止し、進捗を**導入PLAN**に記録する。

> 「なぜ」「各ステップで何を判断するか」は [`introduction-guide.md`](../../../packages/core/docs/introduction-guide.md) を参照。
> 本スキルはその operational な実行役。

## 設計方針（重要）

- **agent オーケストレーションはしない**。Claude がメインセッションで手順を進める軽量ドライバー。
- 導入は一度きり・判断主体のため、**人間を常にループに入れる**（フォーマット策定・優先順・粒度は必ず確認）。
- 状態は導入PLAN（`docs/common/plans/stdd-introduction.md`）にのみ持つ。本スキルはステートレス。

---

## 起動時の動作

### 1. 導入PLAN の有無を確認

```
docs/common/plans/stdd-introduction.md
```

- **無い場合 → 初回**: 下記「初回フロー」を実行し、導入PLAN を作成する。
- **ある場合 → 再開**: 導入PLAN を読み、最初の未チェック項目（`- [ ]`）を「次にやること」として提示し、該当ステップを実行する。

### 2. 設定確認

`.stdd.config.yml` を読み、`apps[]` / `docs.layout`（`common_requirements` / `common_architecture` 含む）を把握する。無ければ step 0 を案内する。

---

## ステップ実行表

各ステップは「呼ぶスキル」と「停止して人間に確認すること」を持つ。

| step | 実行内容 | 呼ぶスキル | ★停止して確認 |
| ---- | -------- | ---------- | ------------- |
| 0 | `.stdd.config.yml` 作成 / テンプレ・skill 配置 | — | 構成（単一/複数アプリ・パス規約） |
| 1 | common ティア生成 | `reverse-engineering-common-spec` | 生成後の `<!-- 要確認 -->` 一覧 |
| 1.5 | 機能インベントリ + 優先順 → 導入PLAN へ記載 | — | ★ 機能一覧と優先順（P0 から） |
| 2 | 代表機能 1 つをリバース | `reverse-engineering-feature-spec` | ★ Spec 粒度・スコープ |
| 3-4 | フォーマット策定 → テンプレ特化 | — | ★★ フォーマット決定（テーラリング） |
| 5 | 残り機能を優先順でループ | `reverse-engineering-feature-spec` | ★ 機能ごとの粒度 |
| 6 | 順行運用へ移行 | `auto-implement`（以降） | 導入完了の確認 |

各機能リバース後は `verify-consistency` で spec ⇔ test ⇔ 実装 の整合を確認する。

---

## 初回フロー（導入PLAN が無いとき）

1. **プロジェクト点検**: ディレクトリ構成・`package.json`・ルーティングをざっと把握。
2. **step 0 確認**: `.stdd.config.yml` が無ければ作成を案内（`apps` / `commands` / `docs.layout`）。
3. **step 1 実行**: `reverse-engineering-common-spec` を呼び、common ティアを生成。`<!-- 要確認 -->` を一覧化して人間に提示。
4. **step 1.5（★人間判断）**: ルーティング・主要ドメインから機能を洗い出し、**優先順をユーザーと合意**。
5. **導入PLAN 生成**: `templates/introduction-plan.md` を雛形に `docs/common/plans/stdd-introduction.md` を作成し、機能を優先順で並べる。
6. 「次は step 2（代表機能のリバース）」を提示して停止。

---

## 再開フロー（導入PLAN があるとき）

1. 導入PLAN を読み、完了済み（`- [x]`）と未着手（`- [ ]`）を把握。
2. 最初の未着手項目を「次にやること」として 1 つ提示。
3. ユーザーの了承後、該当ステップのスキルを呼んで実行。
4. 完了したら導入PLAN の該当項目を `- [x]` に更新し、フォーマット決定があれば「決定ログ」に追記。
5. 次の未着手を提示して停止（**一度に 1 ステップ**。バッチ全自動にしない）。

---

## 守ること

- **一度に 1 ステップ**。複数機能を無確認で連続処理しない。
- **★ポイントでは必ず停止**してユーザーに聞く（優先順・粒度・フォーマット）。
- 遡行フェーズでは「実装が真実」。推測で spec を書かない。
- 導入PLAN 以外に進捗・履歴を持たない（SSOT 原則。spec 本体に「今回」「変更前」等を書かない）。

---

## When NOT to Use This Skill

- **単一機能のリバースだけ**したい: `reverse-engineering-feature-spec` を直接使う
- **common ティアだけ**作りたい: `reverse-engineering-common-spec` を直接使う
- **新規機能を実装**したい（導入済みプロジェクト）: `auto-implement` を使う
- **新規プロジェクト**（コードがまだ無い）への導入: 本スキルの対象外

---

## 参照ファイル

- **導入ガイド（なぜ/判断基準）**: [introduction-guide.md](../../../packages/core/docs/introduction-guide.md)
- **導入PLAN テンプレート**: [templates/introduction-plan.md](templates/introduction-plan.md)
- **common ティアのリバース**: [reverse-engineering-common-spec skill](../reverse-engineering-common-spec/SKILL.md)
- **機能単位のリバース**: [reverse-engineering-feature-spec skill](../reverse-engineering-feature-spec/SKILL.md)
- **整合性チェック**: [verify-consistency skill](../verify-consistency/SKILL.md)
- **順行運用（新機能実装）**: [auto-implement skill](../auto-implement/SKILL.md)
