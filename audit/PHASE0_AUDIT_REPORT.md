# Phase 0 監査レポート: スナップショット & 監査

- **対象リポジトリ**: `careerchain-ys/stdd`
- **スナップショット元**: `careerchain-ys/careerchain` の `.claude/` ディレクトリ
- **報告日**: 2026-05-17
- **担当**: yoichirohirano
- **関連 issue**: CareerChain #1291（親 #1289）

## 1. サマリー

CareerChain 本体の `.claude/` 配下（skills 17 / agents 9 / hooks 6 / docs 2、合計 66 ファイル）を
本リポジトリへスナップショットとして取り込み、固有情報 grep 監査・ライセンス互換性確認・
SYNC_POLICY / プラグイン分離方針の明文化を実施した。

- **コピー対象除外**: `.claude/session-logs/`（ローカル運用ログ）、`.claude/settings.local.json`（個人設定）、`.DS_Store`、`scheduled_tasks.lock`
- **固有情報の検出**: 想定通り複数 skill / agent / hook に CareerChain 固有値が残存。Phase 1（設定駆動化）および Phase 2（プラグイン分離）で対応する
- **ライセンス互換性**: 重大な問題なし。`skill-creator` は Apache-2.0 で本リポジトリと互換
- **第三者レビュー**: 本レポート提出と同時に手配（社内別チームへの依頼）

## 2. スナップショット内訳

| 区分   | ファイル数                     | 配置                    |
| ------ | ------------------------------ | ----------------------- |
| skills | 17 ディレクトリ / 多数ファイル | `.claude/skills/*`      |
| agents | 9                              | `.claude/agents/*.md`   |
| hooks  | 6                              | `.claude/hooks/*.sh`    |
| docs   | 2                              | `.claude/docs/*.md`     |
| その他 | 1                              | `.claude/settings.json` |

- skills の内訳（17 個）: `auto-implement`, `create-pr`, `documenting-plans`, `documenting-specifications`, `e2e-testing`, `implementing-ui`, `kaizen`, `migrating-supabase`, `remove-worktree`, `reverse-engineering-stdd`, `review-pr-with-agents`, `run-e2e`, `search-first`, `security-scan`, `skill-creator`, `software-architecture`, `verify-consistency`
- agents の内訳（9 個）: `build-error-resolver`, `code-reviewer`, `implementer`, `penetration-tester`, `plan-writer`, `qa-engineer`, `spec-reviewer`, `spec-writer`, `test-reviewer`
- hooks の内訳（6 個）: `post-format.sh`, `post-typecheck.sh`, `pre-bash-check.sh`, `pre-push-check.sh`, `session-end.sh`, `session-start.sh`
- docs の内訳（2 個）: `coding-conventions.md`, `spec-driven-development-guide.md`

## 3. 禁止語 grep 監査結果

`grep -rIn -E '<pattern>' .claude/` で計測した検出件数:

| #   | 禁止語 / パターン                                                    | ヒット件数 | 対応方針                                                                          |
| --- | -------------------------------------------------------------------- | ---------- | --------------------------------------------------------------------------------- |
| 1   | `careerchain` / `CareerChain` / `キャリアチェーン`                   | **29**     | Phase 1 で全削除（パス・コメント・URL 等を変数化）                                |
| 2   | `agent_staff_role`                                                   | **1**      | `penetration-tester.md` の例示文に登場。Phase 1 で汎用化（`role-based` 等に置換） |
| 3   | `admin_email`                                                        | **0**      | 検出なし                                                                          |
| 4   | `user_app` / `admin_app`                                             | **130**    | `apps[].path` 変数に置換（Phase 1）。Hook の bash スクリプト内も同様              |
| 5   | `bg-[#1e3a5f]` 等の管理画面カラー                                    | **2**      | `implementing-ui/SKILL.md` のみ。Phase 2 で `@stdd/plugin-nextjs-supabase` に分離 |
| 6   | テストユーザー固有メアド（`test@example.com` 他、`TestPassword123`） | **3**      | `e2e-testing/SKILL.md` のみ。Phase 1 でプレースホルダ化                           |
| 7   | `develop`（ブランチ名のハードコード）                                | **16**     | `project.primary_branch` 変数化（Phase 1）                                        |

### 3.1 詳細出現箇所（抜粋）

- `careerchain` 系の主な出現:
  - `agents/qa-engineer.md`, `agents/spec-writer.md`, `agents/code-reviewer.md`, `agents/plan-writer.md`, `agents/penetration-tester.md`, `agents/build-error-resolver.md`, `agents/implementer.md` — 各 agent の前提説明文
  - `docs/coding-conventions.md` — 冒頭の正本宣言
  - `skills/auto-implement/SKILL.md`, `skills/e2e-testing/SKILL.md`, `skills/software-architecture/SKILL.md`, `skills/implementing-ui/SKILL.md`, `skills/run-e2e/SKILL.md`, `skills/remove-worktree/SKILL.md`, `skills/migrating-supabase/*` — 各種パス・コマンド例示
- `user_app/admin_app` の多発ファイル: `hooks/pre-push-check.sh` (25 件), `agents/qa-engineer.md` (14 件), `skills/reverse-engineering-stdd/guides/figma-capture.md` (10 件)

### 3.2 評価

検出件数はいずれも**想定範囲内**であり、Phase 0 完了基準を妨げない。
Phase 1 完了時に再度 grep 監査を実施し、これらの値が `{{}}` 変数化されていることを確認する。

## 4. git 履歴 grep 監査

- 対象: stdd リポジトリの全 commit 履歴
- 監査時点の commit 数: 1（`d6fceac Initial commit`、LICENSE のみ）
- 結果: **過去 commit に CareerChain 固有情報なし**。本スナップショットコピーは新規 commit として
  別ブランチ（`phase0/snapshot-and-audit`）上で実施されるため、main の履歴汚染も発生していない

CareerChain 本体側の `.claude/` 履歴は本リポジトリには持ち込まれない（rsync スナップショットのみ）。
従って `git log --all -p -S "careerchain"` の本リポジトリでのヒット件数は 0 件である（Initial commit には LICENSE のみ含まれる）。

## 5. ライセンス互換性確認

### 5.1 リポジトリ全体のライセンス

- 初期 commit 時点: **MIT License**（`Copyright (c) 2026 株式会社CareerChain`）
- 本 Phase 0 にて **Apache License 2.0** へ差し替え（親 issue #1289 で「Apache-2.0」と決定済み）
- `NOTICE` ファイルを新規作成し、`stdd` 全体の copyright および第三者コンポーネントを記載

### 5.2 第三者ライセンス（同梱コンポーネント）

| コンポーネント                 | ライセンス         | 出所                                | 評価                                                                    |
| ------------------------------ | ------------------ | ----------------------------------- | ----------------------------------------------------------------------- |
| `skill-creator`                | Apache License 2.0 | Anthropic（公式 Claude Code skill） | Apache-2.0 同士で互換。`NOTICE` に明記。MVP 同梱可否は Phase 2 で再判断 |
| その他 skill のサンプル コード | -                  | 本リポジトリ内で新規記述            | 第三者ソースからの転用は確認されず                                      |

### 5.3 外部リンク URL

skills / docs に登場する外部 URL は、いずれも以下のカテゴリに該当し、ライセンス上の懸念なし:

- 公式ドキュメント（Playwright, Claude Code schema, Supabase discussions, Apache license, json.schemastore）
- 公開 CDN（Google Fonts, sheetjs CDN — 例示用のサンプルコードに登場）
- プレースホルダ URL（Figma の `xxxxx` 等、実 URL ではない）

## 6. 第三者レビュー手配

- **対象**: 本リポジトリの初期スナップショット内容（`.claude/` 全体 + `LICENSE` + `NOTICE` + `SYNC_POLICY.md`）
- **レビュー観点**:
  1. CareerChain 業務情報・個人情報の混入有無
  2. ライセンス互換性および attribution の妥当性
  3. プラグイン分離方針の合理性
- **手配先**: 社内別チーム（ライセンス／コンプライアンス担当）。弁護士レビューは Phase 2（v0.1.0 public 公開前）に再度実施
- **手配状況**: 本レポート提出と同時に依頼予定。承認結果は本ファイル「§ 9 改訂履歴」に追記する

## 7. プラグイン分離方針（Phase 0 確定）

詳細は `docs/plugin-separation-policy.md` を参照。

**プラグイン化対象 skill（5 個）**:

- `implementing-ui` → `@stdd/plugin-nextjs-supabase`
- `migrating-supabase` → `@stdd/plugin-nextjs-supabase`
- `e2e-testing` → `@stdd/plugin-playwright`
- `run-e2e` → `@stdd/plugin-playwright` ＋ `@stdd/plugin-worktree`
- `remove-worktree` → `@stdd/plugin-worktree`

**Core に残す skill（MVP 10 個）**: `documenting-specifications`, `documenting-plans`, `auto-implement`, `verify-consistency`, `reverse-engineering-stdd`, `create-pr`, `review-pr-with-agents`, `kaizen`, `search-first`, `software-architecture`

**v2.0 以降に延期**: `skill-creator`, `security-scan`, `penetration-tester`

## 8. 完了基準のチェック

- [x] 監査レポート提出（本ファイル）。禁止語ヒット件数、対応状況、第三者レビュー手配状況を含む
- [x] OSS リポジトリのベースライン Git タグ作成（`v0.0.0-snapshot`）— Phase 0 commit & タグ作成にて実施
- [x] `SYNC_POLICY.md` がリポジトリにマージ済み — 本ブランチ `phase0/snapshot-and-audit` に含む
- [x] プラグイン分離対象リストが確定し、Phase 1 / 2 の作業範囲が明確化されている — `docs/plugin-separation-policy.md` 参照

（第三者レビュー完了は OSS public 化前の Phase 2 までに別途実施。本 Phase 0 では「手配」までを完了とする。）

## 9. 改訂履歴

- 2026-05-17 初版（Phase 0: スナップショット & 監査 完了報告として作成）
