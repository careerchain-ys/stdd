<!--
導入PLAN — STDD 導入の進捗を保持するプロジェクト単位の生きたチェックリスト。

位置づけ:
  - feature/session 単位の通常 PLAN とは別。プロジェクト全体の「導入」進捗を 1 ファイルで追跡する。
  - introducing-stdd スキルがこのファイルを読み書きしながら導入を駆動する。
  - 導入が一巡（順行運用へ移行）したら役目を終える。

配置:
  docs/common/plans/stdd-introduction.md

書き換え方:
  プレースホルダを実値に置換。機能は step 1.5 で洗い出した一覧を優先順（P0→P1→P2）で並べる。
  完了した項目は [ ] → [x] にする。フォーマット決定は「決定ログ」に追記する。
-->

# STDD 導入PLAN — [サービス名]

> 進捗トラッカー。詳細手順は `introducing-stdd` スキル / `guide-for-existing-project.md` を参照。
> **開始**: [yyyy-mm-dd] / **基準ブランチ**: [main / develop 等]

---

## 進捗

### 基盤

- [ ] step 0: `.stdd.config.yml` 作成・テンプレ/skill 配置
- [ ] step 1: common ティア生成（`docs/common/REQUIREMENTS.md` + `ARCHITECTURE.md`）
  - [ ] **要確認マーカー**（仮説つき）の解消（人間が是非を確定 → マーカー除去）
- [ ] step 1.5: 機能インベントリ + 優先順を確定（下記「機能ループ」へ反映）
- [ ] step 2: 代表機能のリバース（[機能名]）
- [ ] step 3-4: フォーマット策定 → テンプレ特化（下記「決定ログ」へ）

### 機能ループ（step 5）

優先順（P0 → P1 → P2）。各機能 = `reverse-engineering-feature-spec` → `verifying-consistency`。

- [ ] [機能A]  (P0)
- [ ] [機能B]  (P0)
- [ ] [機能C]  (P1)
- [ ] [機能D]  (P2)

### 移行

- [ ] step 6: 既存機能の spec が一巡 → 以降は `auto-implement`（順行運用）へ

---

## フォーマット決定ログ（step 3-4 / 7）

このプロジェクト固有に決めた spec フォーマットの方針を記録する。

- 必須 spec ファイル: [REQUIREMENTS / TECH_DESIGN / ...]
- common ARCHITECTURE に追加した固有セクション: [認証・認可 / RLS / ...]
- docs.layout パス規約: [docs/<app>/<feature>/...]
- Priority 基準: [このプロジェクトでの P0/P1/P2 の定義]
- テスト層の責務分担: [E2E は P0 のみ 等]

---

## メモ・引き継ぎ

- (セッションを跨ぐ際の注意点・保留事項)
