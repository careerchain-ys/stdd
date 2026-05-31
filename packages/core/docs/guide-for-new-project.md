# STDD 立ち上げガイド（新規プロジェクト）

これから作るプロジェクト（コードがまだ無い）に STDD を入れて立ち上げるための手順と判断基準をまとめる。
**既に稼働しているコードベースへの導入**は [`guide-for-existing-project.md`](./guide-for-existing-project.md) を参照。

> **本ガイドと仕組みの関係**
> - 本ガイド = 「**なぜ**そうするか」「各ステップで**何を判断するか**」を示す reference（人間が読む）
> - `starting-new-with-stdd` スキル = セッションで立ち上げを**実際に駆動する仕組み**（次に何をするかを進める）
> - 立ち上げPLAN（`docs/common/plans/stdd-bootstrap.md`）= **進捗状態**を保持（どの feature まで作ったか等）
>
> 3 者は重複しない。skill は本ガイドを参照し、状態は立ち上げPLANに書く。

---

## 1. 基本の考え方

STDD の定常運用は **Spec → Test → 実装** の一方向。新規プロジェクトには既存実装が無いので、この流れをそのまま回していけばよい。既存プロジェクトで必要になる「実装から Spec を起こす」導入フェーズは無く、遡行スキル（`reverse-engineering-*`）も使わない。

| | 新規（本ガイド） | 既存（[guide-for-existing-project](./guide-for-existing-project.md)） |
| --- | --- | --- |
| SSoT | 最初から **Spec** | 導入時は実装 → 一巡後 Spec |
| common ティア | **前方設計**（仮説として書き、feature で検証） | 実装から **逆生成** |
| 使う中心スキル | `documenting-specifications` / `auto-implement` | `reverse-engineering-*` |

ポイント:

- common ティアは**前方設計**：コードが無いので「目的・アクター・初期アーキ」を**仮説**として置き、feature を作りながら検証・更新する。確定していない箇所は `<!-- 未決: ... -->` で残し、決まったら埋める。
- 最初の feature を 1 本通した時点で立ち上げは実質完了し、以降は通常運用（既存機能の追加・変更）と地続き。

---

## 2. 立ち上げフロー全体

| step | 何をするか | 使うスキル | 人間判断 |
| ---- | ---------- | ---------- | -------- |
| **0** | scaffold / `.stdd.config.yml` 点検（common ティア前提で確認） | — | △ 構成確認 |
| **1** | アプリ骨組み生成（stack 固有） | （stack 手順へ委譲） | ★ 構成・コマンド疎通 |
| **2** | common ティアを**前方設計**（docs/common を埋める） | `documenting-specifications` | ★ 目的・アクター・初期アーキ |
| **3** | 最初の feature を順行 spec 化（P0 コアから 1 本） | `documenting-specifications` → `generating-wireframes` | ★ 粒度・スコープ |
| **4** | spec フォーマット策定 → テンプレ特化 | `tailoring-spec-format` | ★★ フォーマット |
| **5** | feature を順行 STDD でループ | `documenting-plans` → `auto-implement` → `verify-consistency` | ★ 粒度（機能ごと） |
| **6** | 立ち上げ完了 → 通常運用へ地続き | `auto-implement`（以降） | 完了確認 |

★ = 人間主体の判断ポイント（skill はここで停止して確認する）。

---

## 3. 各ステップの判断観点

### step 0: セットアップ

- `create-stdd-project` CLI で生成済みなら `.stdd.config.yml`・`.claude/`・`docs/common/` 雛形が揃っている。点検のみ。
- 単一アプリか複数アプリかで `docs.layout` のパス規約が変わる。common ティアは既定で有効（`docs.layout.common_requirements` / `common_architecture`）。

### step 1: アプリ骨組み生成（stack 固有）

- **stack 依存のため本ガイドにはコマンドを書かない**。具体手順は使用テンプレートの README（nextjs+supabase+playwright なら starter README の「次の手順」）と各プラグイン guide を SSoT とする。
- `starting-new-with-stdd` スキルが、`.stdd.config.yml` の `plugins` / `framework` を見て該当手順を対話的に提示・実行支援する。
- 骨組み生成後、`apps[].path` / `commands.*` を実体に合わせて確認（実際に `commands.test` / `typecheck` が動くか）。

### step 2: common ティアの前方設計 ★

- `docs/common/REQUIREMENTS.md`（サービス目的・登場アクター・アプリ構成）と `ARCHITECTURE.md`（システム構成・レイヤ規約・初期データモデル）を人間と起こす。
- **前方設計ゆえ「実装が真実」は効かない**。確定し切らない部分は**仮説**として置き、feature 開発で検証して更新する前提で書く（過度に作り込まない）。

### step 3: 最初の feature

- P0 のコア機能を 1 つ選び、順行で spec 化（REQUIREMENTS → 必要なら wireframe → TECH_DESIGN）。
- ここで作った spec が step 4 のフォーマット策定の素材になる。**まず 1 本通してから一般化**する（Rule of Three）。
- **Spec 粒度（どの画面・機能を 1 Spec にまとめるか）は必ず確認**。

### step 4: フォーマット策定とテンプレ特化 ★★

- step 2・3 の実物を見ながら、このプロジェクト固有の spec フォーマットを決め反映する。`tailoring-spec-format` スキルが駆動する。
- 新規では common ティアがまだ薄い前提で、決定は仮置きでよい（step 6 以降の運用で `tailoring-spec-format` を再実行して育てる）。

### step 5: feature ループ

- `documenting-plans` で PLAN を切り、テスト（Red）→ 実装（Green）。`auto-implement` で駆動できる。
- 各 feature 完了で `verify-consistency`（spec ⇔ test ⇔ 実装）。E2E は P0 のみ等は `stdd-methodology.md` §5 に従う。

### step 6: 通常運用への地続き化

- feature が回り始めたら立ち上げは完了。以降の追加・変更は通常の順行 STDD（`stdd-methodology.md` §6）と同じ。立ち上げPLAN は役目を終える。

---

## 4. 既存導入との違い 早見表

| 観点 | 新規（本ガイド） | 既存 |
| --- | --- | --- |
| 遡行（逆生成） | **無し** | 有り（導入時のみ） |
| common ティア | 前方設計（仮説） | 逆生成（実装が真実） |
| 最初の向き | 順行 | 遡行 → 順行 |
| 固有 step | アプリ骨組み生成 | 機能インベントリ + 優先順 |
| 駆動スキル | `starting-new-with-stdd` | `introducing-stdd` |

---

## 5. 関連ドキュメント

- セッションで立ち上げを駆動する仕組み: `.claude/skills/starting-new-with-stdd/SKILL.md`
- 既存プロジェクトへの導入: [`guide-for-existing-project.md`](./guide-for-existing-project.md)
- 順行の通常フロー・テスト戦略: `stdd-methodology.md`（§5 テスト戦略 / §6 開発フロー）
- 開発フロー図: `workflow-diagram.md`
- スタック別の骨組み手順: 使用テンプレートの README（例: `nextjs-supabase-starter`）/ 各プラグイン
