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

---

## 7. 文字数の上限と総量の基準値

skill / agent / rule の定義は、エージェントが読み込むたびにトークンを使う。文章は読みやすさを理由に育ちやすく、
読み込む量の増加はレビューでは見えにくい。そこで定義の文字数を検査で確かめる。

### 7.1 数える対象

読み込まれる時機が違うので、種別ごとに数える（文字数は Unicode のコードポイント。日本語 1 文字 = 1）。

| 種別 | 対象 | 読み込まれる時機 |
| --- | --- | --- |
| `skill` | `packages/core/skills/<name>/SKILL.md` 全体 | skill の起動時 |
| `skill-metadata` | SKILL.md の `description` + `when_to_use` | 全セッションで常に |
| `agent` | `packages/core/agents/<name>.md` 全体 | agent の起動時（システムプロンプトに載る） |
| `agent-description` | agent の `description` | 全セッションで常に |
| `rule` | `packages/core/rules/*.md` | 全セッションで常に |
| `all` | skills / agents / rules 配下の `.md` の合計（`references/`・`templates/` を含む） | — |

### 7.2 ルール

- **1 本あたりの上限**: 種別ごとの上限（`scripts/harness-size-baseline.json` の `limits`）を超える定義を新しく作らない。
  いま上限を超えている定義は `over_limit` に在庫として載せ、その値までは許す。在庫の値は増やさない。
- **総量の基準値**: 種別ごとの合計（`totals`）を基準値より増やす変更は、検査で不合格になる。
  本数を増やす育ち方は 1 本あたりの上限では捉えられないので、総量でも見る。
  増やすと決めたら `node scripts/check-harness-size.mjs --accept-growth` で台帳を更新し、**理由を PR の本文に書く**。
- **減らしたら締め直す**: 総量が減ったとき・在庫が上限内に戻ったときは、`--update-baseline` で台帳を締め直す。
  このオプションは減らす方向にしか書かない。
- 上限は文章の質を測らない。上限に収めるために規範を削らない。

### 7.3 減らし方

- **判定をスクリプトに移す**: 条件の判定や手順の分岐を文章で説明するより、スクリプトにして skill から呼ぶほうが確実に減る。
  skill の文章は手順書にする。
- **毎回は読まない節を `references/` に分ける**: skill の起動時には SKILL.md だけが読まれる。
  条件に当たったときだけ読む節は `references/` に分け、SKILL.md から参照する。
  毎回読む節を分けても、読み込む回数が増えるだけで減らない。
- **経緯を規範から外す**: 「なぜそう決めたか」の経緯は、規範の文から外して設計メモや PR に残す。

### 7.4 検証

```bash
npm run check:harness-size
node --test test/harness-size.test.mjs
```

---

## 8. 検査スクリプトの作法

検査スクリプト（フック・`scripts/` の検査・`trace-audit.sh` など）は、誤って合格を出すと誰も気づかない。
不合格を出す誤りは利用者がすぐ気づくが、合格を出す誤りは、壊れたまま信頼され続ける。次の作法はこれを防ぐためにある。

### 8.1 ルール

- **走査の対象が 0 件のときに合格としない。** 対象が見つからないのは、パスや名前の設定の誤りであることが多い。
  「対象 0 件」と表示し、合格の表示（「抜け漏れなし」など）を出さない。前提の道具（`jq` など）が無くて実施できないときも、
  「未実施」と表示して合格と区別する。
- **読めなかったものを黙って飛ばさない。** 期待した章・列・行が見つからないときは「読めない」として報告する。
  列名を 1 つ変えただけで検査が空振りし、合格になるのを防ぐ。
- **対象の一覧をスクリプトに直接書かない。** ファイル名・章名・列名・ID の接頭辞は、設定（`.stdd.config.yml`）か
  構造定義（`doc-structure.json` など）から読む。既定値を持つときは、その正本（ガイドやテンプレート）と一致することをテストで確かめる。
- **総数を別の方法で数えて突き合わせる。** 読み取った件数が、別の数え方（見出しの数・表の数）と合うかを確かめる。
  たとえば、操作の見出しの数とレスポンスコードの表の数が一致しなければ、どちらかを読み落としている。
  報告には対象の件数を併記し、読んだ量が分かるようにする。
- **判定を関数に分け、振る舞いのテストを持つ。** テスト（`test/` 配下）には、不合格にすべき例（1 か所だけ壊した例）と、
  通さなければならない例（誤検知しやすい正しい書き方）の両方を持たせる。整合した例が合格することも確かめる。
- **環境の差で結果を変えない。** macOS の bash 3.2 と BSD の awk・sed でも、Linux の GNU の道具でも同じ結果になるように書く
  （連想配列・`sed -i`・awk の拡張機能を使わない）。

### 8.2 検証

```bash
bash test/trace-audit.test.sh
bash test/trace-tables.test.sh
```
