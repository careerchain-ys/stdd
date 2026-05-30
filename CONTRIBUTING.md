# 貢献ガイド (CONTRIBUTING)

stdd プロジェクトへのご関心ありがとうございます。本ガイドはコントリビュータが PR を提出するまでのフローと、プロジェクトが採用しているルールを説明します。

---

## 行動規範

本プロジェクトは [Contributor Covenant 2.1](CODE_OF_CONDUCT.md) を採用しています。コントリビュータは [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) を読み、その内容を尊重してください。

---

## コントリビューションの種類

歓迎する貢献の例:

- バグ報告（`.github/ISSUE_TEMPLATE/bug-report.md` を使用）
- 新しい skill / agent の提案（`skill-request.md` を使用）
- プラグインの提案（`plugin-proposal.md` を使用）
- AI エージェント対応の追加要望（`agent-support-request.md` を使用）
- ドキュメントの誤字脱字修正・改善
- 翻訳貢献（将来）

---

## コントリビューションフロー

### 1. Issue を作成する

機能追加・破壊的変更を伴う改善は、PR を出す前に **必ず Issue を作成して合意を得る** ことを推奨します。誤字修正やドキュメント微修正は Issue を経由せず直接 PR でも構いません。

`.github/ISSUE_TEMPLATE/` 配下の 4 種類のテンプレートから適切なものを選んでください。

### 2. フォーク & ブランチ作成

```bash
git clone https://github.com/<your-username>/stdd.git
cd stdd
git checkout -b <type>/<short-description>
```

ブランチ名規則:

| プレフィックス | 用途                                          |
| -------------- | --------------------------------------------- |
| `feat/`        | 新機能 / 新 skill / 新プラグイン              |
| `fix/`         | バグ修正                                      |
| `docs/`        | ドキュメントのみの変更                        |
| `chore/`       | ビルド・依存関係・メタ作業                    |
| `refactor/`    | 振る舞いを変えないコード整理                  |

### 3. 変更を加える

- 既存のコードスタイル（[`AGENTS.md`](AGENTS.md) §コードスタイル）に従う
- ドキュメントは日本語で記述する
- skill / agent / plugin の変更は対応する Spec ドキュメント（`docs/phase*/specs/`）と整合させる

### 4. コミット（DCO sign-off 必須）

本プロジェクトは **Developer Certificate of Origin (DCO)** を採用しています。すべてのコミットに `Signed-off-by:` 行を含めてください。

```bash
git commit -s -m "feat: 新しい skill を追加"
```

`-s` フラグにより、`git config user.name` と `user.email` から `Signed-off-by: Your Name <email>` 行が自動的に末尾に追加されます。

DCO とは、コントリビュータが「自分の貢献がオープンソースライセンスで提供されることに同意する」旨を宣言する仕組みです。詳細は [Developer Certificate of Origin](https://developercertificate.org/) を参照してください。

DCO sign-off がないコミットを含む PR は **マージできません**。`git rebase -i` で修正するか、`git commit --amend -s` で sign-off を追加してください。

### 5. PR を作成する

`.github/pull_request_template.md` のテンプレートに従い、以下を埋めてください。

- **変更概要**: 何を変更するか
- **関連 issue**: Issue 番号（自動クローズ記法を活用）
- **テスト結果**: 実行した検証コマンド・結果の貼り付け
- **評価結果 (eval-result)**: skill / agent 変更時の評価スコア（**強く推奨**。Phase 2-C で必須化予定）
- **チェックリスト**: DCO sign-off / docs 更新 / 破壊的変更の有無

### 6. レビュー対応

メンテナがレビューします。指摘事項に応じて追加コミットを push してください（force push は最終マージ前にメンテナと相談の上で行ってください）。

---

## 検証コマンド

PR 提出前に下記が通っていることを確認してください。

```bash
# JSON Schema 構文検証
npx -y ajv-cli compile -s packages/core/schema/.stdd.config.schema.json

# plugin.json 構文検証
for f in plugins/*/plugin.json; do
  python3 -m json.tool "$f" > /dev/null && echo "OK $f"
done

# 旧プロジェクト名がライセンス/NOTICE/公開URL以外に混入していないか確認
grep -rIn -E '(careerchain|CareerChain|キャリアチェーン)' \
  --exclude-dir='.git' \
  --exclude-dir='node_modules' \
  --exclude='LICENSE' \
  --exclude='NOTICE' \
  .
```

上記コマンドのヒットのうち、以下は意図的な許容例外であり修正不要です:

- `packages/core/README.md` のスキーマ URL と組織名の中立性に関する注記
- `packages/core/schema/.stdd.config.schema.json` の `$id` フィールド
- リポジトリルートの `README.md` および `AGENTS.md` の git clone URL

---

## ライセンス

本リポジトリへの貢献は [Apache License 2.0](LICENSE) のもとで提供されたものとみなされます（DCO sign-off によりこれに同意することを意味します）。

---

## セキュリティ問題の報告

脆弱性等の機密度の高い問題は、公開 Issue ではなく個別連絡を推奨します。公式の `SECURITY.md`（脆弱性報告窓口）は Phase 2-B 〜 Phase 2-C で整備予定です。それまでは GitHub Issue を `bug-report` テンプレートで作成し、機密度が高い場合はメンテナへの個別連絡を併用してください。

---

## 質問

質問は GitHub Discussions（提供時）または Issue で受け付けます。`skill-request` / `plugin-proposal` / `agent-support-request` のテンプレートから適切なものを選んでください。
