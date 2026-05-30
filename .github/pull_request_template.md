## 変更概要

何を変更するかを 1〜3 文で記述してください。

## 関連 issue

関連 issue 番号を記載してください（自動クローズしたい場合は GitHub の closing keyword を使用）。

- 関連: #
- 解決対象: #

## 変更の種類

- [ ] 新機能 / 新 skill / 新プラグイン
- [ ] バグ修正
- [ ] ドキュメントのみの変更
- [ ] リファクタリング（振る舞いに変更なし）
- [ ] ビルド・依存関係・メタ作業
- [ ] 破壊的変更を含む

## テスト結果

実行した検証コマンドとその結果を貼り付けてください。

```
（実行したコマンドと出力をここに貼る）
```

例:

- [ ] `npx -y ajv-cli compile -s packages/core/schema/.stdd.config.schema.json` がエラーなく完了
- [ ] `for f in plugins/*/plugin.json; do python3 -m json.tool "$f" > /dev/null && echo OK; done` で全て OK
- [ ] 禁止語 grep のヒットが許容例外のみ

## 評価結果 (eval-result) — 強く推奨

skill / agent を変更する PR では、評価結果（auto-implement quick success rate 等）の添付を **強く推奨** します。Phase 2-C で QA gate として必須化される予定の事前項目です。

- 評価対象 skill / agent:
- 評価コマンド:
- 結果（合格率 / 評価スコア）:

```
（評価結果をここに貼る）
```

該当しない PR ではこの項目は省略可能です。

## チェックリスト

- [ ] すべてのコミットに DCO sign-off (`Signed-off-by:`) を付与した
- [ ] 関連ドキュメント（README / AGENTS / CONTRIBUTING / 該当 skill / Spec）を更新した
- [ ] 破壊的変更が含まれる場合、本文に明記しメンテナの承認を得た
- [ ] [`CODE_OF_CONDUCT.md`](../CODE_OF_CONDUCT.md) を読み、内容を尊重する
- [ ] スクリーンショット・ログを除き、シークレット・個人情報を含めていない

## その他

レビュー時に注目してほしい点・既知の制限事項・後続 PR で扱う予定の項目があれば記述してください。
