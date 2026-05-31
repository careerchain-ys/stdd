---
name: starting-new-with-stdd
description: |-
  新規（コードがまだ無い）プロジェクトを STDD で立ち上げる作業を、Claude セッションで段階的に駆動するスキル。立ち上げガイドに従い、アプリ骨組み生成→common ティアの前方設計→最初の feature→フォーマット策定→feature ループ→通常運用への移行までを、既存スキル（documenting-specifications / generating-wireframes / tailoring-spec-format / documenting-plans / auto-implement / verify-consistency）を順に呼びながら進める。進捗は立ち上げPLANで保持し、セッションを跨いで再開できる。「新規プロジェクトをstddで立ち上げる」「stddで新規開発を始める」「立ち上げの続き」「start new project with stdd」「greenfield stdd」に関する作業で使用。既に稼働しているコードへの導入は introducing-stdd を使う。
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# STDD 立ち上げドライバースキル（新規プロジェクト）

新規プロジェクトの STDD 立ち上げを、セッションで 1 ステップずつ進めるための**薄い駆動役**。
自前の実装ロジックは持たず、各ステップで**既存スキルを順に呼び**、人間判断ポイントで停止し、進捗を**立ち上げPLAN**に記録する。

> 「なぜ」「各ステップで何を判断するか」は [`guide-for-new-project.md`](../../../packages/core/docs/guide-for-new-project.md) を参照。
> 本スキルはその operational な実行役。既存（稼働中）プロジェクトへの導入は [`introducing-stdd`](../introducing-stdd/SKILL.md)。

## 設計方針（重要）

- **agent オーケストレーションはしない**。Claude がメインセッションで手順を進める軽量ドライバー。
- 立ち上げは判断主体のため、**人間を常にループに入れる**（アーキ判断・フォーマット策定・粒度は必ず確認）。
- 状態は立ち上げPLAN（`docs/common/plans/stdd-bootstrap.md`）にのみ持つ。本スキルはステートレス。
- 新規は**最初から順行**（Spec → Test → 実装）。`reverse-engineering-*`（遡行）は使わない。

---

## 起動時の動作

### 1. 立ち上げPLAN の有無を確認

```
docs/common/plans/stdd-bootstrap.md
```

- **無い場合 → 初回**: 下記「初回フロー」を実行し、立ち上げPLAN を作成する。
- **ある場合 → 再開**: 立ち上げPLAN を読み、最初の未チェック項目（`- [ ]`）を「次にやること」として提示し、該当ステップを実行する。

### 2. 設定確認

`.stdd.config.yml` を読み、`apps[]` / `commands` / `docs.layout`（`common_requirements` / `common_architecture` 含む）を把握する。
`create-stdd-project` で生成済みなら揃っている。無ければ step 0 を案内する。

---

## ステップ実行表

各ステップは「呼ぶスキル」と「停止して人間に確認すること」を持つ。

| step | 実行内容 | 呼ぶスキル | ★停止して確認 |
| ---- | -------- | ---------- | ------------- |
| 0 | scaffold / `.stdd.config.yml` 点検（common ティア前提） | — | 構成（単一/複数アプリ・パス規約） |
| 1 | **アプリ骨組みを対話駆動**（stack 固有） | （stack 手順へ委譲。下記「step 1」詳細） | ★ 構成・コマンド疎通 |
| 2 | **common ティアを前方設計**（docs/common を埋める） | `documenting-specifications` | ★ 目的・アクター・初期アーキ |
| 3 | 最初の feature を順行 spec 化（P0 コアから 1 本） | `documenting-specifications` → `generating-wireframes` | ★ Spec 粒度・スコープ |
| 4 | フォーマット策定 → テンプレ特化 | `tailoring-spec-format` | ★★ フォーマット決定 |
| 5 | feature を順行 STDD でループ | `documenting-plans` → `auto-implement` | ★ 機能ごとの粒度 |
| 6 | 通常運用へ移行 | `auto-implement`（以降） | 立ち上げ完了の確認 |

各 feature 実装後は `verify-consistency` で spec ⇔ test ⇔ 実装 の整合を確認する。

---

## 初回フロー（立ち上げPLAN が無いとき）

1. **scaffold 確認**: `create-stdd-project` 生成物（`.stdd.config.yml`・`.claude/`・`docs/common/` 雛形）が揃っているか点検。未生成なら CLI を案内。
2. **step 1（アプリ骨組み）**: 下記「step 1」手順で stack 固有の骨組み生成を対話駆動。
3. **step 2（★人間判断）**: `documenting-specifications` で `docs/common/REQUIREMENTS.md` + `ARCHITECTURE.md` を**前方設計**（仮説として埋める）。
4. **step 3（★人間判断）**: P0 コア機能を 1 つ選び、順行で feature spec を作る。
5. **立ち上げPLAN 生成**: `templates/bootstrap-plan.md` を雛形に `docs/common/plans/stdd-bootstrap.md` を作成し、想定 feature を優先順で並べる。
6. 「次は step 4（フォーマット策定）」を提示して停止。

---

## 再開フロー（立ち上げPLAN があるとき）

1. 立ち上げPLAN を読み、完了済み（`- [x]`）と未着手（`- [ ]`）を把握。
2. 最初の未着手項目を「次にやること」として 1 つ提示。
3. ユーザーの了承後、該当ステップのスキルを呼んで実行。
4. 完了したら立ち上げPLAN の該当項目を `- [x]` に更新し、フォーマット決定があれば「決定ログ」に追記。
5. 次の未着手を提示して停止（**一度に 1 ステップ**。バッチ全自動にしない）。

---

## step 1: アプリ骨組みの対話駆動（詳細）

新規はアプリ本体がまだ無いので、stack 固有の骨組み（フレームワーク・DB・E2E）を立てる。
**本スキルは stack 非依存**なので、コマンドの実体は持たず、使用中の stack 手順を SSoT として参照・実行支援する。

### 1-1. stack の特定

`.stdd.config.yml` の `plugins` / `apps[].framework` を読み、骨組み手順の所在を決める。

```
□ plugins に "nextjs-supabase" / "playwright" → nextjs+supabase+playwright スターター手順
   （生成元テンプレートの README「次の手順」が SSoT）
□ それ以外 / 不明 → ユーザーに stack と骨組み手順を確認
```

### 1-2. 骨組み生成を対話駆動

該当手順のコマンド（例: `create-next-app` / `supabase init` / Playwright 導入）を**1つずつ提示し、ユーザーの確認のもと実行**する。具体コマンドは本スキルに書かず、参照先（テンプレート README / プラグイン guide）の記述に従う。

### 1-3. 設定の実体合わせ（★確認）

```
□ apps[].path / apps[].port が実体と一致
□ commands.test / typecheck / build / db_* が実際に動く
```

> 骨組みが既に用意されている場合は step 1 を飛ばして step 2 へ。

---

## 守ること

- **一度に 1 ステップ**。複数 feature を無確認で連続処理しない。
- **★ポイントでは必ず停止**してユーザーに聞く（アーキ判断・粒度・フォーマット）。
- common ティアは**前方設計＝仮説**。作り込みすぎず、feature 開発で検証して更新する。確定しない箇所は `<!-- 未決: ... -->` で残す。
- 立ち上げPLAN 以外に進捗・履歴を持たない（SSOT 原則。spec 本体に「今回」「変更前」等を書かない）。
- 遡行スキル（`reverse-engineering-*`）は使わない（新規にはコードが無い）。

---

## When NOT to Use This Skill

- **既に稼働しているコード**への STDD 導入: `introducing-stdd` を使う
- **単一機能の spec を書く / 実装する**だけ: `documenting-specifications` / `auto-implement` を直接使う
- **フォーマット策定だけ**やり直したい: `tailoring-spec-format` を直接使う

---

## 参照ファイル

- **立ち上げガイド（なぜ/判断基準）**: [guide-for-new-project.md](../../../packages/core/docs/guide-for-new-project.md)
- **立ち上げPLAN テンプレート**: [templates/bootstrap-plan.md](templates/bootstrap-plan.md)
- **common / feature spec 作成**: [documenting-specifications skill](../documenting-specifications/SKILL.md)
- **ワイヤーフレーム**: [generating-wireframes skill](../generating-wireframes/SKILL.md)
- **フォーマット策定・テーラリング**: [tailoring-spec-format skill](../tailoring-spec-format/SKILL.md)
- **PLAN 作成**: [documenting-plans skill](../documenting-plans/SKILL.md)
- **順行実装**: [auto-implement skill](../auto-implement/SKILL.md)
- **整合性チェック**: [verify-consistency skill](../verify-consistency/SKILL.md)
- **既存プロジェクトへの導入**: [introducing-stdd skill](../introducing-stdd/SKILL.md)
