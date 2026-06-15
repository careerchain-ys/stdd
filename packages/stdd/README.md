# @careerchain/stdd

STDD (Spec and Test Driven Development) を**既存・新規どちらのプロジェクトにも 1 コマンドで導入**する CLI です。

`.claude/`（skill / agent / hook）・`.stdd.config.yml`・`docs/` を現在のディレクトリに配置します。

## 使い方

```bash
cd my-project        # 既存プロジェクト、または新規の空ディレクトリ
npx @careerchain/stdd init   # STDD 一式を現在のディレクトリに導入
claude               # Claude Code を起動
```

起動後、Claude に「**STDD を導入して**」と伝えると、`setup-stdd` スキルが新規 / 既存を自動判定し、
適切な駆動スキル（新規=`starting-new-with-stdd` / 既存=`introducing-stdd`）へ委譲します。

## コマンド

```bash
npx @careerchain/stdd init [options]
```

> グローバルにインストール（`npm i -g @careerchain/stdd`）した場合は `stdd init` として実行できます。

| option | 説明 |
| --- | --- |
| `--name <name>` | `.stdd.config.yml` の `project.name`（既定: ディレクトリ名） |
| `--force` | tailoring 済み（編集された）STDD ファイルも最新へ上書きする |
| `--yes`, `-y` | 対話プロンプトをスキップし既定値で進める |
| `--help`, `-h` | ヘルプを表示 |
| `--version`, `-v` | バージョンを表示 |

## 挙動

`.claude/` は**ディレクトリ単位ではなくファイル単位で非破壊マージ**します。既存の Claude 設定や
ユーザー自作の skill / agent を汚染しません。

- **`.claude/`（skill / agent / hook / rules）**: STDD が配布するファイルだけを作成・更新します。
  - ユーザー自作ファイル（STDD パスと衝突しない）はそのまま保持。
  - STDD パスにユーザーが置いた同名ファイルは**上書きせず skip**（手動確認を促す）。
  - ユーザーが編集（tailoring）した STDD ファイルは**保持**（最新化したい場合のみ `--force`）。
  - 配布から外れた旧 STDD ファイル（未編集）は掃除します。
- **`.claude/settings.json`**: **deep-merge**。`permissions.allow` / `enabledMcpjsonServers` /
  `hooks` は union、スカラー競合はユーザー値を優先し、STDD の不足設定のみ追記します。
- **`.stdd.config.yml`** / **`.mcp.json`**: 無ければ生成、既存は保持。
- **`docs/`**: 無ければ作成。

### STDD 由来の明示

導入物は以下の 2 系統で「STDD 由来」と判別できます。

- **`.claude/.stdd/manifest.json`**: STDD が導入した全ファイルの相対パス・`sha256`・`source: "stdd"`
  を記録（更新時の差分・編集検出・将来のアンインストールに利用）。
- **frontmatter マーカー**: 配布される各 skill / agent の先頭に `source: stdd` を付与。

## ライセンス

Apache License 2.0
