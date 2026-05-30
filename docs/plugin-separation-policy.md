# プラグイン分離方針

本ドキュメントは Phase 0 にて確定した、stdd OSS におけるプラグイン分離の対象と境界を定める。

## 1. 基本方針

stdd OSS の core（`packages/core/` および `packages/claude-code/skills/` 等）に置く skill は、
**特定の技術スタックや実行環境に依存しない汎用ロジック**に限定する。
500 行規模の固有ノウハウを `.stdd.config.yml` に設定として持たせると config が破綻するため、
技術スタック固有・実行環境固有のノウハウは**プラグイン化**して分離する。

プラグインは独立した npm パッケージ（`@stdd/plugin-*`）として配布し、
利用プロジェクトの `.stdd.config.yml` に明示的に列挙された場合のみロードされる。

```yaml
# .stdd.config.yml 例
plugins:
  - "nextjs-supabase"
  - "playwright"
  - "worktree"
```

## 2. プラグイン化対象 skill（Phase 0 確定）

| skill                | 分離理由                                                                                             | 配置先（予定）                                      |
| -------------------- | ---------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| `implementing-ui`    | shadcn/ui・Tailwind の特定カラーコード・admin_app 固有レイアウト等、技術スタックと UI 仕様に強く依存 | `@stdd/plugin-nextjs-supabase`                      |
| `migrating-supabase` | Supabase 固有のマイグレーション規約・RLS パターンに依存                                              | `@stdd/plugin-nextjs-supabase`                      |
| `e2e-testing`        | Playwright API・Locator パターン・worker 設計に依存                                                  | `@stdd/plugin-playwright`                           |
| `run-e2e`            | devcontainer + worktree + Playwright を組み合わせた実行手順に依存                                    | `@stdd/plugin-playwright` + `@stdd/plugin-worktree` |
| `remove-worktree`    | git worktree + devcontainer を前提とした環境クリーンアップ手順に依存                                 | `@stdd/plugin-worktree`                             |

## 3. プラグインパッケージ構成（予定）

### 3.1 `@stdd/plugin-nextjs-supabase`

Next.js + Supabase スタック向けのプラグイン。

含めるもの:

- `implementing-ui` 相当の UI 実装ガイド（shadcn/ui パターン、Tailwind ブレークポイント等）
- `migrating-supabase` 相当の DB マイグレーションガイド
- Next.js Server Actions / Server Components パターン
- Supabase RLS・GRANT パターン

含めないもの:

- 特定プロジェクト固有の admin 権限モデル（独自ロール名・カスタム権限テーブル等）
- 特定プロジェクト固有のカラーコード（ブランドカラーの固定値等）→ プラグインのデフォルト値も持たず、利用側プロジェクトのトークン参照に委ねる

### 3.2 `@stdd/plugin-playwright`

Playwright を用いた E2E テスト向けのプラグイン。

含めるもの:

- `e2e-testing` 相当の Playwright ベストプラクティス
- `run-e2e` 相当のテスト実行手順（環境変数・ポート設定は `.stdd.config.yml` から取得）

含めないもの:

- 特定の worker 数・並列度などの環境固有設定
- worktree 固有の実行手順 → `@stdd/plugin-worktree` 側に分離

### 3.3 `@stdd/plugin-worktree`

git worktree + devcontainer を用いたマルチ環境並列開発向けのプラグイン。

含めるもの:

- `remove-worktree` 相当のクリーンアップ手順
- worktree 命名規約・INSTANCE_ID 判定ロジック
- devcontainer override 設定の生成ロジック

含めないもの:

- 特定プロジェクトのポート割り当て（`.stdd.config.yml` の `workflow.worktree.port_base` 等から取得）

## 4. Core 側に残す skill（MVP 13 個）

以下は技術スタックに依存しない汎用 skill として core に残す:

1. `documenting-specifications`
2. `documenting-plans`
3. `auto-implement`
4. `verify-consistency`
5. `reverse-engineering-common-spec`
6. `reverse-engineering-feature-spec`
7. `introducing-stdd`
8. `tailoring-spec-format`
9. `create-pr`
10. `review-pr-with-agents`
11. `kaizen`
12. `search-first`
13. `software-architecture`

これらの skill 内に含まれる下流プロジェクト固有値（`user_app` / `admin_app` / `develop` 等のサンプル値）は、
Phase 1 で Handlebars 変数（`{{apps[].path}}` / `{{project.primary_branch}}` 等）に置換する。

## 5. v0.1.0 から物理除外する skill（Phase 2-B 確定）

以下の skill / agent は **v0.1.0 リポジトリから物理除外**する。Phase 2-B (2026-05-30) の確定判断:

| skill / agent        | 扱い                 | 理由                                                                                                                                      |
| -------------------- | -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `skill-creator`      | 物理除外（削除）     | Anthropic 公式の skill であり stdd 独自実装ではない。stdd の STDD コア（Spec→Test→Impl）と直接関係しないため OSS リポジトリには同梱しない |
| `security-scan`      | 物理除外（削除）     | 実装が下流プロジェクト固有のスタック（Supabase RLS / npm audit 等）に強く依存しており、汎用化には大幅な再設計が必要。コア機能には含めない |
| `penetration-tester` | 物理除外（記述削除） | agent 実体はもともと無く、本ポリシーへの記載のみが残っていた。記載を削除                                                                  |

判断方針: ミニマム公開（親 issue #1289, @yuki-sakaue 2026-05-25）を優先し、コア STDD ワークフローの中核から外れる skill は同梱しない。将来必要が出た場合は **プラグイン化** または **専用リポジトリ化** で対応する（v0.2.0 以降の検討事項）。

実施内容（Phase 2-B PR）:

- `.claude/skills/skill-creator/` ディレクトリを `git rm -r` で削除
- `.claude/skills/security-scan/` ディレクトリを `git rm -r` で削除
- `.claude/agents/code-reviewer.md` 内の `/security-scan` コマンド参照を「下記のセキュリティチェックを必ず実施」に一般化（チェック項目本体は別途 Phase 3 で汎用化）

## 6. プラグインインタフェース（暫定）

プラグインの具体的なインタフェース仕様は Phase 1 で確定する。
ここでは Phase 0 時点での想定のみを記載する:

```yaml
# .stdd.config.yml
plugins:
  - "nextjs-supabase" # 文字列指定: 規約に従って `@stdd/plugin-*` を解決
  - id: "playwright"
    options: # プラグイン固有の設定を渡せる
      base_url: "http://localhost:{{apps[0].port}}"
```

各プラグインは以下を提供する:

- `skills/` — プラグインが追加する skill 群（Handlebars テンプレート）
- `agents/` — プラグインが追加する agent 群（任意）
- `templates/` — REQUIREMENTS / TECH_DESIGN テンプレートの追加セクション（任意）
- `schema.json` — プラグイン固有の `options` の JSON Schema

## 7. 改訂履歴

- 2026-05-17 初版（Phase 0: スナップショット & 監査 にて作成）
