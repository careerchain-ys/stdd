# subagent と skill のモデルの使い分け

STDD 方法論（[`stdd-methodology.md`](stdd-methodology.md)）の一章。作業の性質に合ったモデルを使い分け、判断の質を保ったまま、
機械的な作業にかかる時間と使用量を減らすための考え方と設定を定める。

**この章は Claude Code 向けの生成物だけが対象である。** Codex 向けの生成物（`.codex/agents/*.toml`）にはモデルを出力しない。
Claude Code のモデルの別名は Codex のモデル ID ではないため、Codex ではセッションの既定のモデルをそのまま使う。

## 1. 原則

| 作業の性質 | 例 | 使うモデル |
| --- | --- | --- |
| 判断が要る作業 | 要件・技術設計の作成、コードの編集、テストの作成、レビュー、指摘の採否 | メインのモデル |
| 機械的な作業 | 広い範囲のファイル検索、ログやテスト結果の要約、テレメトリの集計結果の整理 | 軽いモデルの subagent |

- **判断が中心の agent は、既定でモデルを下げない。** writer・reviewer・implementer・qa-engineer は、メインのモデルを使う。
  特に reviewer を軽いモデルに下げると、見落としが増えるおそれがある。
- **機械的な作業は、結論だけを受け取る形で subagent に任せる。** 任せた subagent の出力は要約であり、判断の根拠にするときは
  元のファイルやログを確かめる。
- **任せる作業に判断を混ぜない。** 「検索して、問題があれば直す」のように判断を含む依頼は、検索の部分だけを任せ、
  直すかどうかはメインのモデルで決める。

## 2. 既定のモデル

STDD が配る agent（`packages/core/agents/*.md`）は、すべて `model: inherit`（メインの会話と同じモデル）を既定にする。

`opus` に固定せず `inherit` にする理由は次のとおり。

- 「判断はメインのモデルで」という原則をそのまま表せる。利用者がメインに選んだモデルより強いモデルにも、弱いモデルにも
  勝手に変えない。
- 環境変数 `CLAUDE_CODE_SUBAGENT_MODEL` で subagent の既定を軽いモデルにしていても、frontmatter の `model` が優先されるので、
  判断が中心の agent まで下がることがない（`model` を省略すると、この環境変数が使われる）。

### 2.1 別名ごとの使いどころ

各モデルの性能・速度・料金は変わるので、選ぶ前に公式の一覧（https://platform.claude.com/docs/ja/models/overview ）を確かめる。
STDD での使いどころの目安は次のとおり。

| 別名 | 公式の位置付け | STDD での使いどころ |
| --- | --- | --- |
| `opus` | 多くの用途で最初に選ぶモデル。長時間のエージェント作業とコーディング向け | メインのモデルの第一候補。判断が中心の agent はメインを通じてこれを使う |
| `fable` | 高度な推論と長時間のエージェント作業向け。`opus` で足りないときに上げる先。`opus` より高価 | 既定にはしない。影響の大きい変更のレビューなど、`opus` で見落としが続く agent だけ上書きで上げる |
| `sonnet` | 速度と性能の釣り合いが最もよい | メインの予算を抑えるとき。agent ごとに下げるなら、結果を機械で確かめられる工程（テストの実行が中心の qa-engineer など）から試す |
| `haiku` | 最も速く安い。分類・抽出・振り分けのような大量の処理向け | `models.mechanical` の既定。検索・抽出・要約に限る。入力が長いと料金の単価が上がるので、任せる範囲を絞って渡す |

- reviewer（requirements-reviewer・tech-specs-reviewer・test-reviewer・code-reviewer）は、`sonnet` 以下に下げない。
  見落としはその場では表に出ず、後の工程の手戻りとして現れるので、所要時間や使用量の比較だけでは損得を判断しにくい。
- writer・plan-writer・implementer は、成果物をレビューと検査が確かめるので、下げたときの影響はレビューの指摘の数と
  修正の往復の回数に表れる。下げるなら、§5 の方法で前後を比べる。

## 3. 設定での上書き

`.stdd.config.yml` の `models` で上書きできる。値はモデルの**別名**（`inherit` / `opus` / `sonnet` / `haiku` / `fable`）だけを書き、
モデルの ID（`claude-` で始まる名前）は書かない。ID は新しいモデルが出るたびに古くなるためである。

```yaml
models:
  agents:            # agent ごとのモデル。書かなかった agent は既定（inherit）のまま
    qa-engineer: sonnet
  mechanical: haiku  # 機械的な作業を subagent に任せるときのモデル（既定 haiku）。inherit ならメインのモデル
```

- `models.agents` は、`stdd init` を実行したときに Claude 向けの agent の定義（`.claude/agents/<name>.md`）の `model` の行へ反映される。
  設定を変えたら `stdd init` を実行し直す。利用者が編集した agent の定義は、ほかの配布物と同じく上書きしない。
- Codex 向けの生成物は、この設定では変わらない。
- `models.mechanical` は、skill の手順で機械的な作業を subagent に任せるときに、その subagent に渡すモデルである
  （Claude Code の Agent ツールの `model` 引数）。`inherit` のときは `model` を渡さない。

## 4. skill の手順での任せ方

- 広い範囲のファイル検索や、コードの所在の調査は、Claude Code の組み込みの検索用 subagent（Explore）で足りるならそれを使う。
  Explore は既定でメインの会話のモデルで動くので、軽いモデルで動かすなら Agent ツールの `model` 引数に `models.mechanical` を渡す。
- ログ・テスト結果・収集スクリプトの出力が長いときは、`models.mechanical` のモデルの subagent に要約させ、メインには結論と
  該当箇所だけを戻す。
- 数字の集計は、subagent にも任せず、スクリプトで行う（例: `measuring-dev-process` の `collect.sh`）。

## 5. 効果の測り方

モデルの使い分けを変えたら、変更の前後を比べる。所要時間とレビューの回数は工程テレメトリ
（[`feedback-loop.md`](feedback-loop.md)）で、使用量はエージェントの利用状況の表示や請求の画面で見る。
所要時間と使用量が減っても、レビューで見逃した欠陥や手戻りが増えていれば戻す。比較は `measuring-dev-process` で行い、
変更は改善施策として登録簿に残す。

## 6. 対象外

- Codex 向けのモデルの対応表。
- 推論の強さ（effort）の設定。必要になったら別に検討する。
