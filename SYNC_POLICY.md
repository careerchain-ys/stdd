# SYNC_POLICY.md

本リポジトリ（`careerchain-ys/stdd`、以下「stdd OSS」）と社内プロジェクト
`careerchain-ys/careerchain`（以下「CareerChain 本体」）の関係性および同期ポリシーを定める。

## 1. 基本方針: 完全分離・本体 fork 独自進化

stdd OSS は CareerChain 本体の `.claude/` ディレクトリ（skills / agents / hooks / docs）を
**初期スナップショット**として取り込んで発足した。
ただし発足以降、両リポジトリは**完全に分離した別プロジェクトとして独自に進化する**。

| 観点                 | CareerChain 本体                                 | stdd OSS                                                |
| -------------------- | ------------------------------------------------ | ------------------------------------------------------- |
| リポジトリ           | `careerchain-ys/careerchain`（プライベート）     | `careerchain-ys/stdd`（パブリック）                     |
| ライセンス           | 社内プロプライエタリ                             | Apache License 2.0                                      |
| 主対象               | CareerChain プロダクト開発                       | あらゆる Web プロジェクトに適用可能な汎用 STDD ツール群 |
| 抽象化レベル         | 技術スタック・ドメインに固有の実装をハードコード | 設定駆動（`.stdd.config.yml`）＋ プラグイン経由で具象化 |
| 主な利用エージェント | Claude Code（社内運用）                          | Claude Code 専用（v1.0）、将来的に他エージェント対応    |
| 主言語               | 日本語                                           | 日本語（README/AGENTS.md 含む。英訳は実施しない）       |

stdd OSS は CareerChain 本体の「上流リポジトリ」ではなく、CareerChain 本体は stdd OSS の
「下流リポジトリ」でもない。両者は **発足時のスナップショットのみを共有する独立したプロジェクト**である。

## 2. 同期に関する原則

### 2.1 順方向同期（CareerChain → stdd OSS）

**原則として推奨しない。**

CareerChain 本体の `.claude/` には業務ロジック・固有情報が含まれるため、
変更を機械的に stdd OSS へ取り込むと業務情報の漏洩リスクが高い。

CareerChain 本体で発生した改善・知見を stdd OSS に反映したい場合は、
以下のプロセスを経ること:

1. CareerChain 本体側で改善内容を確認
2. 業務ロジック・固有情報を**人手で**抽象化・除去
3. stdd OSS の設定駆動アーキテクチャ（`.stdd.config.yml` / プラグイン）に合うよう再構築
4. stdd OSS 側で通常の PR フロー（issue → ブランチ → PR → レビュー → merge）を経て取り込み

CareerChain 本体の commit を `git cherry-pick` 等で機械的に持ち込むことは禁止する。

### 2.2 逆方向同期（stdd OSS → CareerChain）

**原則として禁止する。**

stdd OSS は Apache License 2.0 で公開されており、第三者からの contribution を受け入れる。
これを CareerChain 本体に取り込むと、社内プロプライエタリコードベースに OSS 由来コードが
混入し、ライセンス遵守の検証コストが恒常的に発生する。

CareerChain 本体は stdd OSS の通常リリース（npm パッケージ等の公式配布物）を
**外部依存として利用する**形を取り、ソースの cherry-pick やコピーは行わないこと。

例外的に逆方向取り込みが必要な場合は、ライセンス部門の事前承認を必須とし、
取り込んだ範囲を社内 NOTICE に記録する。

## 3. 業務情報の流出防止

CareerChain 本体に固有の以下の情報は、stdd OSS には**いかなる形でも持ち込まない**:

- プロダクト名・ブランド名（`CareerChain` / `careerchain` / `キャリアチェーン` 等）
- ドメイン固有のスキーマ・テーブル名（`agent_staff_role` / `admin_email` 等）
- 業務固有のデプロイ環境・URL・テストユーザー情報
- 管理画面の UI 仕様・カラーコード（`bg-[#1e3a5f]` 等）
- 顧客・社員・取引先に関する任意の情報

stdd OSS の PR レビュー時は、上記禁止語を grep で機械チェックすることを推奨する
（CI で自動化する方針: Phase 2 で導入予定）。

## 4. 例外対応・問い合わせ

本ポリシーに対する例外（CareerChain 本体 ⇔ stdd OSS の双方向に踏み込んだ同期等）が
必要な場合は、stdd OSS のメンテナとライセンス部門の合意を経ること。

問い合わせは GitHub Issue（`careerchain-ys/stdd`）または社内のメンテナチームに行う。

## 5. 改訂履歴

- 2026-05-17 初版（Phase 0: スナップショット & 監査 にて作成）
