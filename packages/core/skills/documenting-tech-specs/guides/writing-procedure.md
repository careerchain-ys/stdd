# 技術 spec を書く前の確認

feature の技術 spec と common の技術文書の作成・更新を始める前に行う確認。構成（`docs.lineup`）・SSOT 原則は [SKILL.md](../SKILL.md) に従う。

## 1. 前提

対象機能の REQUIREMENTS.md が確定している（レビューとユーザーの確認を通っている）こと。確定していなければ、技術設計に入らず要件に戻る。
REQUIREMENTS.md の全ユースケース・受入基準を、技術設計とテスト戦略のどこかに対応させる。

## 2. 読むもの

- `.stdd.config.yml` の `docs.lineup`・`docs.layout`・`docs.structure`・`response_codes`
- 対象機能の REQUIREMENTS.md（全ユースケース・受入基準・業務ルール・非機能要件）
- 書く文書のテンプレート（章立て・記法ルール・チェックリスト）と、類似機能の同じ種類の文書
- common の ARCHITECTURE.md / TABLE_DEFINITION.md / API_SPEC.md / DESIGN.md
- 関連する既存コード（ドメイン層・画面のコンポーネント・データベースのスキーマ定義）
- `AGENTS.md` / `CLAUDE.md` / `.claude/docs/coding-conventions.md`（存在する場合）
- スタック固有の設計の知識は、`.stdd.config.yml` の `plugins` にあるプラグインの skill

## 3. 追記か新規作成か

対象の文書が既にあれば読み、追記か新規作成かを決める。古い版のテンプレートに基づく文書は、テンプレートの更新履歴の手順で新しい版に合わせてから追記する。追記では既存の内容を消さず、構成と形式を保ち、
節番号を重複させない。迷うときはユーザーに確かめる。

## 4. 書かないもの

- 実装例・コード例（型定義・インターフェースのコードブロックと、ロジック設計の擬似コードは書いてよい）
- ファイル構成・実装の順序（PLAN で書く）
- 「実装済み」「新規追加」の分類、チェックボックス
- 業務要件・機能要件・非機能要件そのもの（REQUIREMENTS.md で書く）
- feature でのテーブル・API の再定義（common の TABLE_DEFINITION.md / API_SPEC.md を参照する）

技術設計で出やすい SSOT 原則の違反は、テスト戦略の「〜に統合」「〜に集約」のように以前の形を匂わせる表現と、
設計判断の「〜だったが〜に変更」である。設計判断の理由は「この構成を採る理由」として書く。

## 5. 書き終えたら

- テンプレートと SKILL.md のチェックリストを通す。`bash .claude/hooks/trace-audit.sh` で ID の抜け漏れを確かめる。
- auto-implement から使っているときは、`tech-specs-reviewer` のレビューに進む（[phases.md](../../auto-implement/references/phases.md) Phase 1b）。

## 6. 構成ごとの書く順序

前の文書の行を、後の文書が参照する順に書く。

- **`single`**: TECH_DESIGN.md → TEST_PLAN.md。
- **`layered`**:
  1. `API_DESIGN.md`。画面が受け取るコードはここで決まるので、画面より先に書く。新しい API の形は common の `API_SPEC.md` に足す。
  2. `SCREEN_DESIGN.md`。3.3 で、呼ぶ操作が返すすべてのコードを受ける。
  3. `API_TEST_DESIGN.md` と `SCREEN_TEST_DESIGN.md`。対になる設計書の行を 1 行ずつ列挙する。
  4. `TEST_DESIGN.md`。すべてのユースケースと受入基準の担保先を、層別のテスト設計の行の ID で書く。

`layered` で設計書を後から直したら、対になるテスト設計と TEST_DESIGN の行も同じ変更で直す。
