# Figma UIキャプチャガイド - Playwright MCPを使った画面キャプチャとFigma取り込み

リバースエンジニアリング時に、実装済みのUIをPlaywright MCPで操作・キャプチャし、Figmaデザインファイルとして整理する手順。

---

## 目的

- 実装済みUIの**視覚的なドキュメント**をFigmaに集約する
- REQUIREMENTS.mdの「UI/UXデザイン」セクションからFigmaリンクで参照できるようにする
- デザインの現状を正確に記録し、今後のUI改善・レビューの基盤とする

---

## 前提条件

- 対象アプリがローカル環境で起動していること
- Playwright MCPが利用可能であること
- Figmaアカウントがあること

---

## 作業フロー

```
1. キャプチャ計画の作成（画面一覧・状態の洗い出し）
   ↓
2. Playwright MCPでアプリを操作し、各画面のスクリーンショットを取得
   ↓
3. Figmaファイルを作成し、スクリーンショットをフレームとして配置
   ↓
4. REQUIREMENTS.mdの「UI/UXデザイン」セクションにFigmaリンクを記載
   ↓
5. スクリーンショットファイルを削除（gitにはコミットしない）
```

---

## Step 1: キャプチャ計画の作成

コードリーディング（Phase 1）の結果を元に、キャプチャすべき画面と状態を一覧化する。

### 洗い出すべき画面状態

| カテゴリ | 状態例 |
|---------|--------|
| **初期状態** | データなし（空）、ローディング中 |
| **データあり** | 1件表示、複数件表示 |
| **フォーム** | 未入力、入力済み、バリデーションエラー |
| **モーダル** | 開いた状態（新規追加/編集） |
| **操作結果** | 成功トースト、削除確認ダイアログ |
| **レスポンシブ** | デスクトップ（1280px）、モバイル（375px） |

### 計画テンプレート

```markdown
## キャプチャ計画: [機能名]

### デスクトップ（1280x800）
| # | 画面名 | 状態 | 操作手順 |
|---|--------|------|---------|
| 1 | 一覧画面 | データあり | ログイン → 対象ページへ遷移 |
| 2 | 一覧画面 | データなし | テストデータなしユーザーでログイン |
| 3 | 追加モーダル | 空フォーム | 「追加」ボタンクリック |
| 4 | 追加モーダル | 入力済み | フォーム項目を入力 |
| 5 | 編集モーダル | 既存データ読み込み済み | 編集ボタンクリック |
| 6 | 削除確認 | ダイアログ表示 | 削除ボタンクリック |

### モバイル（375x812）
| # | 画面名 | 状態 | 操作手順 |
|---|--------|------|---------|
| 1 | 一覧画面 | データあり | （同上、ビューポート変更） |
| 2 | 追加モーダル | 空フォーム | （同上、ビューポート変更） |
```

---

## Step 2: Playwright MCPでスクリーンショット取得

### 操作ルール

CLAUDE.mdの「Playwright MCPでのブラウザ操作ルール」に従う:

```
1. ブラウザを開く
2. ログイン（テストユーザーを使用）
3. 対象画面に遷移
4. 各状態のスクリーンショットを取得
5. ログアウト
6. ブラウザを閉じる
```

### スクリーンショット取得のポイント

**1. ビューポートサイズを明示的に設定する**

```
デスクトップ: 1280x800
モバイル: 375x812
```

**2. 状態を正確に再現してからキャプチャする**

```
❌ 悪い例: ページを開いた直後にキャプチャ（ローディング中の可能性）
✅ 良い例: データが表示されたことを確認してからキャプチャ
```

**3. 画面全体をキャプチャする（フルページ）**

スクロールが必要な長い画面は、フルページスクリーンショットを取得する。

**4. ファイル名は一貫した命名規則に従う**

```
{feature}-{screen}-{state}-{viewport}.png

例:
dashboard-overview-with-data-desktop.png
dashboard-projects-add-modal-empty-desktop.png
dashboard-projects-list-mobile.png
```

**5. スクリーンショットの一時保存先**

```
docs/<app>/<feature-path>/screenshots/
```

例:
```
docs/<app.id>/dashboard/common/screenshots/
docs/<app.id>/dashboard/projects/screenshots/
```

⚠️ **重要: スクリーンショットはFigma取り込み後に削除すること。gitにはコミットしない。**
詳細は「Step 5: スクリーンショットの削除」を参照。

---

## Step 3: Figmaファイル作成

### Figmaファイル構成

```
Figmaファイル名: <app>-<Feature-Name>
例: <app.id>-Dashboard-Common

ページ構成:
├── Desktop（1280px）
│   ├── フレーム1: [画面名 - 状態]
│   ├── フレーム2: [画面名 - 状態]
│   └── ...
└── Mobile（375px）
    ├── フレーム1: [画面名 - 状態]
    └── ...
```

### Figmaへの取り込み手順

1. Figmaで新しいファイルを作成
2. 「Desktop」「Mobile」のページを作成
3. 各スクリーンショットをフレームとして配置
4. フレーム名を設定（画面名 + 状態を含める）
5. 必要に応じてアノテーション（注釈）を追加

### フレーム命名規則

```
[画面名] - [状態]

例:
Overview Tab - データあり
Projects Tab - 一覧表示
Projects - 追加モーダル（空）
Projects - 追加モーダル（入力済み）
Projects - 削除確認ダイアログ
```

---

## Step 4: REQUIREMENTS.mdへの記載

オンボーディングのREQUIREMENTS.mdを参考に、以下のフォーマットで記載する。

### 記載フォーマット

```markdown
## 3. UI/UXデザイン

### Figmaデザイン

**Figmaファイル**: [<ファイル名>](<FigmaファイルURL>)

#### [画面名1]

- [状態A](<FigmaファイルURL>?node-id=<node-id>)
- [状態B](<FigmaファイルURL>?node-id=<node-id>)

#### [画面名2]

- [状態A](<FigmaファイルURL>?node-id=<node-id>)
- [状態B](<FigmaファイルURL>?node-id=<node-id>)
```

### 記載例（ダッシュボードの場合）

```markdown
## 3. UI/UXデザイン

### Figmaデザイン

**Figmaファイル**: [<app.id>-Dashboard-Common](https://www.figma.com/design/xxxxx/<app.id>-Dashboard-Common)

#### OverviewTab

- [実績サマリ表示](https://www.figma.com/design/xxxxx/<app.id>-Dashboard-Common?node-id=1-2)

#### タブ切り替え

- [Overviewタブ（アクティブ）](https://www.figma.com/design/xxxxx/<app.id>-Dashboard-Common?node-id=2-2)
- [Projectsタブ（アクティブ）](https://www.figma.com/design/xxxxx/<app.id>-Dashboard-Common?node-id=3-2)

#### WelcomeSection

- [ウェルカムバナー表示](https://www.figma.com/design/xxxxx/<app.id>-Dashboard-Common?node-id=4-2)
```

### node-idの取得方法

1. Figmaでフレームを選択
2. 右クリック → 「リンクをコピー」
3. URLの`node-id=`パラメータが該当のnode-id

---

## Step 5: スクリーンショットの削除

⚠️ **スクリーンショットはFigmaへの取り込みが完了したら必ず削除する。gitにはコミットしない。**

### 理由

- スクリーンショットはFigmaに取り込むための**一時ファイル**であり、Figmaが正（Single Source of Truth）
- 画像ファイルはgitリポジトリを肥大化させる
- UIの更新はFigma上で管理する

### 削除手順

```bash
# Figma取り込み完了後、screenshotsディレクトリごと削除
rm -rf docs/<app>/<feature-path>/screenshots/

# 例
rm -rf docs/<app.id>/dashboard/common/screenshots/
rm -rf docs/<app.id>/dashboard/projects/screenshots/
```

### 削除タイミング

```
スクリーンショット取得 → Figma取り込み → node-idリンク記載 → スクリーンショット削除 → コミット
```

Figmaリンクの記載が完了し、node-idが正しいことを確認してから削除する。削除後にコミットすることで、スクリーンショットがgit履歴に残ることを防ぐ。

---

## チェックリスト

### キャプチャ計画時

```
□ コードリーディングで全画面・全状態を洗い出した
□ デスクトップ・モバイル両方の計画を作成した
□ フォーム状態（空/入力済み/エラー）を網羅した
□ モーダル・ダイアログの状態を含めた
```

### スクリーンショット取得時

```
□ テストユーザーでログインした
□ ビューポートサイズを正しく設定した
□ データが表示されたことを確認してからキャプチャした
□ 命名規則に従ったファイル名を付けた
□ 操作完了後にログアウトした
```

### Figma作成時

```
□ ファイル名が命名規則に従っている
□ Desktop/Mobileのページを分けた
□ フレーム名が画面名+状態を含んでいる
□ 全スクリーンショットをフレームとして配置した
```

### REQUIREMENTS.md記載時

```
□ FigmaファイルURLを記載した
□ 各画面のnode-id付きリンクを記載した
□ 複数状態がある画面は状態ごとにリンクを記載した
```

### スクリーンショット削除時

```
□ Figmaへの取り込みが完了した
□ REQUIREMENTS.mdのnode-idリンクが正しいことを確認した
□ screenshotsディレクトリを削除した
□ スクリーンショットがgit stagingに含まれていないことを確認した
```
