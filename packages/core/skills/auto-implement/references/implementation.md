# Auto Implement - 実装の手順（Phase 2）

Phase 2 でテストを書き、実装する手順。メインのセッションが行う。順序は「Spec → テスト → 実装」（`rules/stdd-spec-first.md`）。

## 1. 着手の前に

- **Spec を読む**: 対象機能の REQUIREMENTS.md・TECH_DESIGN.md・TEST_PLAN.md と、PLAN（あれば）。
- **規約を読む**: `AGENTS.md` / `CLAUDE.md` / `.claude/docs/coding-conventions.md`（存在する場合）と、common の ARCHITECTURE.md のレイヤ規約。
- **既にあるものを探す**: 自前で書く前に、次の順で同等のものを探す。
  1. プロジェクト内（各 `apps[].path` 配下と共有のディレクトリ）
  2. 依存しているパッケージ・ライブラリ
  3. フレームワーク・プラットフォームの標準機能
- スタック固有の実装の知識（UI・データベースの変更・E2E など）は、`.stdd.config.yml` の `plugins` にあるプラグインの skill を使う。

## 2. テスト（Red）

1. TEST_PLAN.md のテストケースに沿ってテストを書く（Unit → Integration → E2E）。テストには対象の要件 ID を付ける。
2. 書いたテストだけを実行し、失敗することを確かめる。
3. テストをコミットする。`quick` 以外では、ここで Phase 2.5（テストレビュー）に進む。

## 3. 実装（Green）

1. テストを通す最小限の実装をする。
2. 対象のテストだけを実行し、通ることを確かめる。
3. 各アプリで `commands.typecheck` を実行する。ビルド・型のエラーは 1 つずつ直し、直すたびに実行し直す。
4. 実装をコミットする。

## 4. テストの実行の仕方

対象のアプリの `apps[].path` で、作成・変更したテストを引数で指定して `commands.test` を実行する。

```bash
# 例（実際の値は .stdd.config.yml に従う）
cd <apps[].path> && <commands.test> <対象のテストファイル>
```

全件の実行は QA（`qa-engineer`）・pre-push・CI が受け持つ。対象を絞らない実行はフック `test-scope-guard.sh` が知らせる。
共通部品の変更などで全件が必要なときは、`STDD_FULL_TEST_REASON="<理由>" <commands.test>` のように理由を前置する。

テストの出力が長いときは、結果の要約を軽いモデルの subagent に任せてよい。失敗の原因を判断するときは元の出力を確かめる。
