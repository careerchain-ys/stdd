# 設定駆動オーサリング規約（config-driven authoring）

stdd の skill / agent / hook は、下流プロジェクト固有の値（アプリのパス、ビルド/テストコマンド、PR ターゲットブランチ等）を**ハードコードしてはならない**。これらは利用者プロジェクトのルートにある `.stdd.config.yml` に宣言され、各 skill / agent / hook が**実行時に読み取って**使用する。

本ドキュメントは、その記述方法（オーサリング規約）を定める。markdown（skill / agent）と bash（hook）でアプローチが異なる。

---

## 1. 原則

- **唯一の真実源は `.stdd.config.yml`**。スキーマは [`packages/core/schema/.stdd.config.schema.json`](../packages/core/schema/.stdd.config.schema.json)。
- skill / agent（markdown, AI が読む）は「`.stdd.config.yml` を読み、該当キーの値を使う」と**指示文として**記述する。具体コマンドや固有パスを断定的に書かない。
- hook（bash, 決定的に実行）は `.stdd.config.yml` を**実行時にパース**して値を使う（`yq` があれば利用、無ければ軽量フォールバック）。
- 例示が必要な場合は、特定プロジェクト固有名（`user_app` / `admin_app` / `npx tsc --noEmit` / `develop` 等）ではなく、**中立なプレースホルダ**（`<app.path>` / `<commands.test>` 等）か、汎用例（`web` / `apps/web`）を使う。

---

## 2. ハードコード → config キー 対応表

| ハードコード値（禁止） | 読み取る config キー | 備考 |
| --- | --- | --- |
| `user_app` / `admin_app`（アプリのパス） | `apps[].path` | 複数アプリは `apps[]` をループ |
| `user_app` / `admin_app`（アプリの識別子） | `apps[].id` | レポート見出し等 |
| `npx tsc --noEmit` | `commands.typecheck` | |
| `npm test` / `npm test --no-cache` 等 | `commands.test` | |
| `npm run build` | `commands.build` | |
| `npm run lint` | `commands.lint` | 任意 |
| `develop`（PR/push ターゲット） | `project.primary_branch` | |
| `claude/`（作成ブランチの接頭辞） | `workflow.branch_prefix` | 既定 `claude/` |
| `docs/user_app/<feature>/REQUIREMENTS.md` 等 | `docs.layout.requirements` 等 | パステンプレートは `docs.layout.*` を使う |

---

## 3. markdown（skill / agent）の記述パターン

### 3.1 コマンド実行

**Before（禁止）:**
```bash
cd user_app && npm test --no-cache
cd admin_app && npm test --no-cache
```

**After（推奨）:**
> `.stdd.config.yml` の `apps[]` を読み、各アプリについて `apps[].path` ディレクトリで `commands.test` を実行する。
>
> ```bash
> # 例（実際の値は .stdd.config.yml に従う）
> cd <apps[].path> && <commands.test>
> ```

ポイント:
- 「`.stdd.config.yml` を読んで」という**指示**を明示する。
- コードブロックを残す場合は `<apps[].path>` / `<commands.test>` のような**プレースホルダ**にし、固有値を書かない。
- 「全アプリについて繰り返す」ことを明記する（単一アプリ構成では 1 回で済む）。

### 3.2 型チェック / ビルド

**Before:** `npx tsc --noEmit` / `npm run build`
**After:** 「`commands.typecheck` を実行」「`commands.build` を実行（定義されている場合）」

### 3.3 アプリ別レポート見出し

**Before:**
```
- **user_app**: ✅ XX passed / ❌ XX failed
- **admin_app**: ✅ XX passed / ❌ XX failed
```

**After:**
> `.stdd.config.yml` の各 `apps[]` について、`apps[].id` を見出しに結果を列挙する。
>
> ```
> - **<apps[].id>**: ✅ XX passed / ❌ XX failed   # apps[] の数だけ繰り返す
> ```

### 3.4 PR / push ターゲットブランチ

**Before:** 「`develop` に対して PR を作成」
**After:** 「`project.primary_branch`（`.stdd.config.yml`）に対して PR を作成」

### 3.5 ドキュメントパス

**Before:** `docs/admin_app/login/REQUIREMENTS.md`
**After:** `docs.layout.requirements`（`.stdd.config.yml`）のパステンプレートに `app` と `feature_path` を適用したパス。例示する場合は中立な `docs/<app.id>/<feature_path>/REQUIREMENTS.md` を使う。

---

## 4. bash（hook）の記述パターン

hook は決定的に実行されるため、`.stdd.config.yml` を実行時にパースする。`yq` には複数の非互換実装（mikefarah 版 / python-yq 版）が存在し可搬性に欠けるため、**外部依存を持たない純 bash（awk）パーサ**で必要キー（`apps[].path` / `commands.test` / `commands.build` / `project.primary_branch`）を抽出する。

設計指針:
- config または必須キー（`commands.test`）が無い場合は、push を**ブロックせず**警告してスキップする（hook が利用者環境を壊さない）。
- アプリは `apps[]` をループし、変更があったアプリだけ検査する。`path: "."`（単一アプリ）は常に対象。

実装例は [`.claude/hooks/pre-push-check.sh`](../.claude/hooks/pre-push-check.sh) を参照。

---

## 5. 例外（ハードコードを許容するもの）

- `.claude/` という**ディレクトリ名**（Claude Code 固有、設定値ではない）
- stdd 自身のリポジトリ構造を説明する記述（`packages/core/` 等）
- スキーマやドキュメント中の**例として明示された**値（「Example: ...」と注記されたもの）

---

## 6. 検証

変数化の完了は次で確認する:

```bash
# 下流固有のハードコードが残っていないこと（例示・ディレクトリ名を除く）
grep -rn "user_app\|admin_app" .claude/ plugins/
grep -rn "npx tsc --noEmit" .claude/ plugins/
grep -rn "origin/develop" .claude/ plugins/
```
