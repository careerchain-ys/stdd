<!--
立ち上げPLAN — STDD 新規立ち上げの進捗を保持するプロジェクト単位の生きたチェックリスト。

位置づけ:
  - feature/session 単位の通常 PLAN とは別。プロジェクト全体の「立ち上げ」進捗を 1 ファイルで追跡する。
  - starting-new-with-stdd スキルがこのファイルを読み書きしながら立ち上げを駆動する。
  - 立ち上げが一巡（通常運用へ移行）したら役目を終える。
  - 既存プロジェクト導入の導入PLAN（stdd-introduction.md）とは排他（新規 or 既存のどちらか）。

配置:
  docs/common/plans/stdd-bootstrap.md

書き換え方:
  プレースホルダを実値に置換。feature は想定機能を優先順（P0→P1→P2）で並べる。
  完了した項目は [ ] → [x] にする。フォーマット決定は「決定ログ」に追記する。
-->

# STDD 立ち上げPLAN — [サービス名]

> 進捗トラッカー。詳細手順は `starting-new-with-stdd` スキル / `guide-for-new-project.md` を参照。
> **開始**: [yyyy-mm-dd] / **基準ブランチ**: [main / develop 等]

---

## 進捗

### 基盤

- [ ] step 0: `.stdd.config.yml` 点検（common ティア前提）
- [ ] step 1: プロダクトコンセプトのヒアリング（下記「プロダクトコンセプト」へ転記）
- [ ] step 2: アプリ骨組み生成（stack 固有。`apps[].path` / `commands.*` 疎通確認）
- [ ] step 3: common ティアを前方設計（`docs/common/REQUIREMENTS.md` + `ARCHITECTURE.md`。仮説）
- [ ] step 4: 最初の feature を順行 spec 化（[機能名]）
- [ ] step 5: フォーマット策定 → テンプレ特化（下記「決定ログ」へ）

### feature ループ（step 6）

優先順（P0 → P1 → P2）。各 feature = `documenting-plans` → `auto-implement` → `verifying-consistency`。

- [ ] [機能A]  (P0)
- [ ] [機能B]  (P0)
- [ ] [機能C]  (P1)
- [ ] [機能D]  (P2)

### 移行

- [ ] step 7: feature が回り始めた → 以降は `auto-implement`（通常運用）へ

---

## プロダクトコンセプト（step 1）

ユーザーの 1 レスポンスを**そのまま**転記する（要約・拡張を加えない）。詳細度に関わらずこれを起点にして step 2 以降へ進む。

> [step 1 でユーザーから得た 1 レスポンスをここに転記]

---

## フォーマット決定ログ（step 5 / 運用中のブラッシュアップ）

このプロジェクト固有に決めた spec フォーマットの方針を記録する。

- 必須 spec ファイル: [REQUIREMENTS / TECH_DESIGN / ...]
- common ARCHITECTURE に追加した固有セクション: [認証・認可 / RLS / ...]
- docs.layout パス規約: [docs/<app>/<feature>/...]
- Priority 基準: [このプロジェクトでの P0/P1/P2 の定義]
- テスト層の責務分担: [E2E は P0 のみ 等]

---

## 前方設計の要確認事項（common ティア）

前方設計で仮説として置き、ユーザーに是非を確認したい事項。spec 本体にも**要確認マーカー**（`**⚠️要確認**｜仮説: … ／確認: …`）を残し、ここに一覧化して追跡する。確定したら spec のマーカーを除去し、この項目を `- [x]` にする。

- [ ] [仮説1] — 確認: [何を確かめたいか]
- [ ] [仮説2] — 確認: [何を確かめたいか]

---

## メモ・引き継ぎ

- (セッションを跨ぐ際の注意点・保留事項)
