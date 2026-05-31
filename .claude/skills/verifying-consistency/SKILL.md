---
name: verifying-consistency
description: |-
  Spec（REQUIREMENTS.md / TECH_DESIGN.md）⇔ テスト ⇔ 実装 の整合性を機能単位でチェックする。ブランチ分岐点からの差分を抽出し、要件・設計・テスト・実装の不整合（機能漏れ、テスト漏れ、設計と実装の乖離など）を検出する。
when_to_use: |-
  「整合性チェック」「verify consistency」「Spec準拠確認」「テスト漏れ確認」「STDD整合性」「要件と実装の乖離」「Specと実装の差分」など、STDD に基づく品質確認の依頼があったとき。
allowed-tools: Read, Grep, Glob, Bash
---

# Spec・テスト・実装の整合性チェック

このセッション/ブランチで作成・修正した機能について、Spec・テスト・実装の整合性を確認する。

## 1. 対象ファイルの特定

### ブランチ分岐点からの差分を特定

`.stdd.config.yml` の `project.primary_branch`（PR/統合先ブランチ）を読み、その分岐点からの差分を特定する。

```bash
# <primary_branch> は .stdd.config.yml の project.primary_branch（例: main / develop）
git fetch origin <primary_branch>
git log --oneline origin/<primary_branch>...HEAD
git diff origin/<primary_branch>...HEAD --name-only
```

以下を特定:

- **Specドキュメント**: `docs/` 配下の `REQUIREMENTS.md`, `TECH_DESIGN.md`
- **テスト**: `*.test.ts`, `*.test.tsx`, `e2e/tests/**/*.spec.ts`
- **実装**: `app/`, `components/`, `lib/`, `actions/`, `domain/` 配下のファイル

## 2. 整合性チェック項目

### A. REQUIREMENTS.md ⇔ 実装

- [ ] REQUIREMENTS.md の User Journey が実装で網羅されているか
- [ ] REQUIREMENTS.md の画面仕様（ボタン、フォーム、表示項目）が実装と一致しているか
- [ ] REQUIREMENTS.md に記載された機能要件が全て実装されているか

### B. TECH_DESIGN.md ⇔ 実装

- [ ] TECH_DESIGN.md の「Technical Implementation」セクションの設計方針に従っているか
- [ ] TECH_DESIGN.md の「Decision」セクションの決定事項が実装に反映されているか
- [ ] TECH_DESIGN.md に記載されたファイル構成と実際のファイル構成が一致しているか

### C. TECH_DESIGN.md ⇔ テスト

- [ ] TECH_DESIGN.md に記載されたテスト総数と、実際のテストケース数が一致しているか
- [ ] TECH_DESIGN.md の「Test Strategy」セクションに記載された全テストケースが実装されているか
- [ ] 実装されたテストで、TECH_DESIGN.md に記載されていないものがないか

### D. テスト ⇔ 実装

- [ ] テストが実装を正しく検証しているか（実装の変更でテストが壊れていないか）
- [ ] テストのモック設定が実装の実際の動作と一致しているか

## 3. 出力形式

以下の形式で結果を報告:

```
## 整合性チェック結果

### 対象機能: [機能名]

### チェック結果サマリ
| 項目 | 状態 | 備考 |
|------|------|------|
| REQUIREMENTS.md ⇔ 実装 | OK / WARN / NG | |
| TECH_DESIGN.md ⇔ 実装 | OK / WARN / NG | |
| TECH_DESIGN.md ⇔ テスト | OK / WARN / NG | |
| テスト ⇔ 実装 | OK / WARN / NG | |

### 検出された不整合
1. [不整合の内容]
   - 期待: [Specの記載内容]
   - 実際: [テスト/実装の内容]
   - 推奨アクション: [修正方法]

### 推奨事項
- [改善提案があれば記載]
```

## 4. 注意事項

- Specドキュメントが存在しない場合は、その旨を報告
- 軽微な不整合（コメントの差異など）は WARN として報告
- 重大な不整合（機能の欠落、テスト漏れなど）は NG として報告
- 不整合が見つかった場合、修正の優先度も提示
