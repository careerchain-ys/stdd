# create-stdd-project

STDD (Spec and Test Driven Development) ベースのプロジェクトを 1 コマンドで作成する CLI です。

## 使い方

```bash
npx create-stdd-project my-app
cd my-app
git init && git add -A && git commit -m "chore: bootstrap with stdd"
claude          # Claude Code を起動
```

引数を省略すると対話でプロジェクト名を尋ねます。

```bash
npx create-stdd-project
# ? プロジェクト名: ▍
```

## v0.1.0 の制約

- テンプレートは `templates/minimal/` のみ（`--template` フラグは accept されるが ignore されます。v0.2.0 で追加予定）
- `.claude/` 配下は stdd リポジトリ本体からそのままコピーされ、ハードコード値（`user_app` / `admin_app` 等のサンプル値）は Phase 3 で変数化予定
- 既存ディレクトリへの上書きは行いません（明示エラーで終了）

## ライセンス

Apache License 2.0
