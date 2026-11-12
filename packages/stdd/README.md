# @careerchain/stdd

STDD (Spec and Test Driven Development) を**既存・新規どちらのプロジェクトにも 1 コマンドで導入**する CLI です。

選んだエージェントのビュー（Claude=`.claude/`、Codex=`.agents/skills`・`.codex/`・`AGENTS.md`）と
`.stdd.config.yml`・`docs/` を現在のディレクトリに配置します。各ビューは stdd 本体の単一 SSoT（`packages/core`）から生成されたものです。

## 使い方

```bash
cd my-project        # 既存プロジェクト、または新規の空ディレクトリ
npx @careerchain/stdd init   # STDD 一式を導入（既定 both。--agent claude|codex|both）
claude               # Claude Code（または codex）を起動
```

起動後、Claude Code / Codex に「**STDD を導入して**」と伝えると、`setup-stdd` スキルが新規 / 既存を自動判定し、
適切な駆動スキル（新規=`starting-new-with-stdd` / 既存=`introducing-stdd`）へ委譲します。

## コマンド

```bash
npx @careerchain/stdd init [options]
```

> グローバルにインストール（`npm i -g @careerchain/stdd`）した場合は `stdd init` として実行できます。

| option | 説明 |
| --- | --- |
| `--agent <claude\|codex\|both>` | 導入するエージェントビュー（既定: both） |
| `--name <name>` | `.stdd.config.yml` の `project.name`（既定: ディレクトリ名） |
| `--force` | tailoring 済み（編集された）STDD ファイルも最新へ上書きする（除外の記録は上書きしない） |
| `--exclude <kind>:<name>` | skill / agent / フックを導入しない。除外の記録に足し、再実行でも復活させない（`kind` は `skill` / `agent` / `hook`。複数回指定できる） |
| `--include <kind>:<name>` | 除外の記録から外し、導入し直す |
| `--yes`, `-y` | 対話プロンプトをスキップし既定値で進める |
| `--help`, `-h` | ヘルプを表示 |
| `--version`, `-v` | バージョンを表示 |

## 挙動

各エージェントのビューを**ディレクトリ単位ではなくファイル単位で非破壊マージ**します。既存設定や
ユーザー自作ファイルを汚染しません。

Claude ビュー（`--agent claude|both`）:

- **`.claude/`（skill / agent / hook / rules）**: STDD が配布するファイルだけを作成・更新します。
  - ユーザー自作ファイル（STDD パスと衝突しない）はそのまま保持。
  - STDD パスにユーザーが置いた同名ファイルは**上書きせず skip**（手動確認を促す）。
  - ユーザーが編集（tailoring）した STDD ファイルは**保持**（最新化したい場合のみ `--force`）。
  - 配布から外れた旧 STDD ファイル（未編集）は掃除します。
- **`.claude/settings.json`**: **deep-merge**。`permissions.allow` / `enabledMcpjsonServers` /
  `hooks` は union、スカラー競合はユーザー値を優先し、STDD の不足設定のみ追記します。
- **`.mcp.json`**: 無ければ生成、既存は保持。

Codex ビュー（`--agent codex|both`）:

- **`.agents/skills`（同一 SKILL.md 標準）・`.codex/agents`（TOML）・`.codex/hooks` + `.codex/hooks.json`**:
  Claude ビューと同じ非破壊マージ（衝突 skip・tailoring 保持・orphan 掃除）。
- **`AGENTS.md`**: spec-first ルールをマーカーブロック（`STDD:BEGIN/END`）で**非破壊注入**。既存本文は保持し、ブロックのみ更新（冪等）。
- **`.codex/config.toml`（MCP）**: 無ければ生成、既存は保持。

共通:

- **`.stdd.config.yml`**: 無ければ生成、既存は保持。
- **`docs/`**: 無ければ作成。

### 削除した配布物を復活させない（除外の記録）

不要な skill / agent を削除したり、フックの登録を外したりしたあとで `stdd init` を再実行しても、
それらは復活しません。導入しないものを `.stdd/exclusions.json` に記録し、両ビューに適用します。

```json
{
  "skills": ["kaizen"],
  "agents": [],
  "hooks": ["pre-push-check"]
}
```

- **自動で記録する**: manifest に記録のある skill / agent のファイルがすべて消えていたら、利用者が削除したものとみなして記録します。
  `.claude/settings.json` から STDD のフックの登録を外した場合も同じです（前回登録したフックの名前を manifest の `settingsHooks` に残しています）。
  ビューごと消した場合（記録したものが 1 つも残っていない場合）は導入し直しとみなし、記録しません。
  skill の一部のファイルだけが消えている場合は削除とはみなさず、作り直します。
- **明示して記録する**: `stdd init --exclude skill:kaizen` のように指定します。初回の導入から使えます。
  記録した skill / agent の未編集のファイルは削除し、編集済みのファイルは残して報告します。
- **フックの除外**は登録だけを外します（Claude の `.claude/settings.json`、Codex の `.codex/hooks.json`）。
  スクリプトの実体は、ほかの手順から呼ばれることがあるので残します。
- **戻す**ときは `stdd init --include skill:kaizen` を実行します。記録ファイルを直接編集してもかまいません。
- 記録ファイルはリポジトリにコミットしてください。チームの全員が同じ構成で再導入できます。

フックの登録は名前（`hooks/<name>.sh`）の単位で合わせます。利用者が書き換えた登録（`timeout` の変更など）は残し、
STDD の登録を重ねて足しません。配布から外れたフックの登録は外します。

### STDD 由来の明示

導入物は以下で「STDD 由来」と判別できます。

- **manifest**: Claude=`.claude/.stdd/manifest.json`、Codex=`.stdd/codex-manifest.json`。導入した全ファイルの相対パス・`sha256`・`source: "stdd"`
  を記録（更新時の差分・編集検出・将来のアンインストールに利用）。
- **frontmatter マーカー**: Claude ビューの各 skill / agent 先頭に `source: stdd` を付与。

## ライセンス

Apache License 2.0
