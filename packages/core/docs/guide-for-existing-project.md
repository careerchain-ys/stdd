# STDD 導入ガイド（既存プロジェクト）

既に稼働しているコードベースへ STDD を導入するための手順と判断基準をまとめる。
**新規プロジェクト（コードがまだ無い）の立ち上げ**は [`guide-for-new-project.md`](./guide-for-new-project.md) を参照。

> **本ガイドと仕組みの関係**
> - 本ガイド = 「**なぜ**そうするか」「各ステップで**何を判断するか**」を示す reference（人間が読む）
> - `introducing-stdd` スキル = セッションで導入を**実際に駆動する仕組み**（次に何をするかを進める）
> - 導入PLAN（`docs/common/plans/stdd-introduction.md`）= **進捗状態**を保持（どの機能がリバース済みか等）
>
> 3 者は重複しない。skill は本ガイドを参照し、状態は導入PLANに書く。

---

## 1. 基本の考え方 — 導入は「遡行ブートストラップ」

STDD の定常運用は **Spec → Test → 実装** の一方向（順行）。
だが既存プロジェクトには実装が先に存在するため、**導入時だけ** 矢印を逆に流し、
**実装 → Spec → Test** で「動いている実装を正典化（ドキュメント化・テスト化）」する。

| フェーズ | 方向 | SSoT（真実の出所） | 使うスキル |
| --- | --- | --- | --- |
| **導入（ブートストラップ）** | 実装 → Spec → Test | **実装** | `reverse-engineering-common-spec` / `reverse-engineering-feature-spec` |
| **運用（定常）** | Spec → Test → 実装 | **Spec** | `auto-implement` |

ポイント:

- 遡行は **導入時の一度きり**。一巡したら順行に切り替わる。
- 遡行フェーズでは「実装が真実」。理想論や推測で Spec を書かず、必ず実装・設定・型定義を確認する。
- 確信が持てない箇所は `<!-- 要確認: ... -->` の一時マーカーを残し、人間レビューで確定したら除去する。

---

## 2. 導入フロー全体

| step | 何をするか | 使うスキル | 人間判断 |
| ---- | ---------- | ---------- | -------- |
| **0** | セットアップ（`.stdd.config.yml` 作成、テンプレ・skill 配置） | — | △ 構成確認 |
| **1** | コードベース全体 → common ティア生成 | `reverse-engineering-common-spec` | △ 要確認の解消 |
| **1.5** | 機能インベントリ作成 + 優先順決定 → 導入PLAN 作成 | — | ★ 優先順 |
| **2** | 代表機能 1 つをリバース（spec + test） | `reverse-engineering-feature-spec` | ★ 粒度・スコープ |
| **3-4** | spec フォーマット策定 → テンプレへ反映（テーラリング） | `tailoring-spec-format` | ★★ フォーマット |
| **5** | 残り機能を導入PLANの優先順でループ | `reverse-engineering-feature-spec` | ★ 粒度（機能ごと） |
| **6** | 以降の新機能は順行 STDD で実装 | `auto-implement` | 通常運用 |
| **7** | フォーマット・テンプレを運用しながらブラッシュアップ | `tailoring-spec-format` | ★ 随時 |

★ = 人間主体の判断ポイント（skill はここで停止して確認する）。

---

## 3. 各ステップの判断観点

### step 0: セットアップ

- `.stdd.config.yml` をプロジェクト構成に合わせて作成（`apps[]`, `commands`, `docs.layout`）。
- 単一アプリか複数アプリかで `docs.layout` のパス規約が変わる。
- common ティアを使うなら `docs.layout.common_requirements` / `common_architecture` を設定。
- 具体的な対話手順（点検 → 草案 → 確認 → 書き込み → schema 検証）は `introducing-stdd` スキルの「step 0: 対話的セットアップ」を参照。

### step 1: common spec のリバース

- `reverse-engineering-common-spec` を実行し `docs/common/REQUIREMENTS.md` + `ARCHITECTURE.md` を生成。
- 出力の `<!-- 要確認 -->` は「人間に確認すべき項目」として後で潰す。

### step 1.5: 機能インベントリと優先順 ★

- ルーティング・ページ・主要ドメインから「機能の一覧」を洗い出す。
- **どの順でリバースするか**を決める（P0 のビジネス中核機能から先に）。全機能を一括でやらない。
- 結果を**導入PLAN**に落とす（チェックリスト化）。

### step 2: 代表機能のリバース

- まず 1 機能だけ `reverse-engineering-feature-spec` で通す。
- ここで得た spec の形が、step 3-4 のフォーマット策定の素材になる。
- **Spec 粒度（どの画面・機能を 1 Spec にまとめるか）は必ず開発者に確認**。

### step 3-4: フォーマット策定とテンプレ特化 ★★（ガイドの肝）

step 1・2 の実物を見ながら、このプロジェクト固有の spec フォーマットを決め、テンプレに反映する。
この策定〜反映は `tailoring-spec-format` スキルが駆動する（決定は人間、skill は選択肢提示・記録・反映を担う）。
**テーラリング・チェックリスト**:

```
□ 必須/任意の spec ファイルを決める（REQUIREMENTS / TECH_DESIGN / SCREEN_ITEMS_DEFINITION / wireframes）
□ common ARCHITECTURE にプロジェクト固有セクションを足すか（認証・認可 / RLS / 通知 / 権限境界 等）
□ docs.layout のパス規約を確定（単一/複数アプリ、feature_path の切り方）
□ Priority(P0/P1/P2) 基準をこのプロジェクトのビジネス優先度に合わせて言語化
□ テスト層の責務分担（E2E は P0 のみ 等）を既存テスト資産に合わせて調整
□ 命名・用語をプロジェクト固有語彙に揃える（テンプレのプレースホルダを実値へ）
□ 決定事項は導入PLANの「フォーマット決定ログ」に残す
```

- テンプレ本体（`packages/core/templates/`）は壊さず、自プロジェクトの `docs/` 配下にコピーして特化するのが基本。

### step 5: 機能ループ

- 導入PLANの優先順で、残り機能を `reverse-engineering-feature-spec` で順に処理。
- 機能ごとに粒度・スコープを確認（バッチ全自動にしない）。
- 各機能完了で導入PLANのチェックを更新。`/verify-consistency` で spec ⇔ test ⇔ 実装 を確認。

### step 6: 順行運用へ

- 既存機能の spec が一通り揃ったら、以降の新機能・変更は `auto-implement`（Spec → Test → 実装）で進める。
- ここで導入（遡行）フェーズは終了。

### step 7: ブラッシュアップ ★

- 運用しながらフォーマットの過不足を調整。変更はテンプレと運用中 spec の両方に反映。
- step 3-4 と同じ `tailoring-spec-format` スキルを再実行する（運用中 spec への影響洗い出しを含む）。
- SSOT 原則を守る（履歴・経緯・「今回の変更」を spec に書かない）。

---

## 4. 関連ドキュメント

- セッションで導入を駆動する仕組み: `.claude/skills/introducing-stdd/SKILL.md`
- 2 ティア構造と方法論: `stdd-methodology.md` §3.0
- 開発フロー図: `workflow-diagram.md`
- common ティアのリバース: `.claude/skills/reverse-engineering-common-spec/SKILL.md`
- 機能単位のリバース: `.claude/skills/reverse-engineering-feature-spec/SKILL.md`
