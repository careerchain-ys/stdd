# 技術 spec を書く前の確認

TECH_DESIGN.md・TEST_PLAN.md と common の技術文書の作成・更新を始める前に行う確認。章構成・SSOT 原則は [SKILL.md](../SKILL.md) に従う。

## 1. 前提

対象機能の REQUIREMENTS.md が確定している（レビューとユーザーの確認を通っている）こと。確定していなければ、技術設計に入らず要件に戻る。
REQUIREMENTS.md の全ユースケース・受入基準を、技術設計とテスト戦略のどこかに対応させる。

## 2. 読むもの

- 対象機能の REQUIREMENTS.md（全ユースケース・受入基準・非機能要件）
- 類似機能の TECH_DESIGN.md、common の ARCHITECTURE.md / TABLE_DEFINITION.md / API_SPEC.md
- 関連する既存コード（ドメイン層・画面のコンポーネント・データベースのスキーマ定義）
- `AGENTS.md` / `CLAUDE.md` / `.claude/docs/coding-conventions.md`（存在する場合）
- スタック固有の設計の知識は、`.stdd.config.yml` の `plugins` にあるプラグインの skill

## 3. 追記か新規作成か

TECH_DESIGN.md / TEST_PLAN.md が既にあれば読み、追記か新規作成かを決める。追記では既存の内容を消さず、構成と形式を保ち、
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

- SKILL.md のチェックリストを通す。
- auto-implement から使っているときは、`tech-specs-reviewer` のレビューに進む（[phases.md](../../auto-implement/references/phases.md) Phase 1b）。
