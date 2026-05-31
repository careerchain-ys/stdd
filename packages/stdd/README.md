# stdd

STDD (Spec and Test Driven Development) を**既存・新規どちらのプロジェクトにも 1 コマンドで導入**する CLI です。

`.claude/`（skill / agent / hook）・`.stdd.config.yml`・`docs/` を現在のディレクトリに配置します。

## 使い方

```bash
cd my-project        # 既存プロジェクト、または新規の空ディレクトリ
npx stdd init        # STDD 一式を現在のディレクトリに導入
claude               # Claude Code を起動
```

起動後、Claude に「**STDD を導入して**」と伝えると、`setup-stdd` スキルが新規 / 既存を自動判定し、
適切な駆動スキル（新規=`starting-new-with-stdd` / 既存=`introducing-stdd`）へ委譲します。

## コマンド

```bash
npx stdd init [options]
```

| option | 説明 |
| --- | --- |
| `--name <name>` | `.stdd.config.yml` の `project.name`（既定: ディレクトリ名） |
| `--force` | 確認なしで既存の `.claude/` を上書きする |
| `--yes`, `-y` | 対話プロンプトをスキップし既定値で進める |
| `--help`, `-h` | ヘルプを表示 |
| `--version`, `-v` | バージョンを表示 |

## 挙動

- **`.claude/`**: 配置する。既に存在する場合は確認のうえ上書き（`--force` で無確認、非対話時は保持）。
- **`.stdd.config.yml`**: 無ければ生成する。既存の設定は**上書きしない**（保持）。
- **`docs/`**: 無ければ作成する。

既存プロジェクトのソースコードや設定を破壊しないよう、追加・生成のみを行います。

## ライセンス

Apache License 2.0
