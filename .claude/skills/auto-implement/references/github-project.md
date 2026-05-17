# GitHub Projectステータス更新

`auto-implement` skill のStep 4.5 / Phase 5 から参照される、GitHub Projectのステータスを変更する手順。

## 1. issueに対応するProject Item IDを取得

```bash
gh api graphql -f query='
mutation {
  addProjectV2ItemById(input: {
    projectId: "PVT_kwDODMaq2s4BOnqv"
    contentId: "<ISSUE_NODE_ID>"
  }) {
    item { id }
  }
}'
```

ISSUE_NODE_IDは以下で取得:

```bash
gh issue view <番号> --json id -q '.id'
```

既にProjectに追加済みの場合も同じmutationで既存Item IDが返る。

## 2. ステータスを更新

```bash
gh api graphql -f query='
mutation {
  updateProjectV2ItemFieldValue(input: {
    projectId: "PVT_kwDODMaq2s4BOnqv"
    itemId: "<ITEM_ID>"
    fieldId: "PVTSSF_lADODMaq2s4BOnqvzg9RK3M"
    value: { singleSelectOptionId: "<OPTION_ID>" }
  }) {
    projectV2Item { id }
  }
}'
```

### Option IDマッピング

| ステータス  | OPTION_ID  |
| ----------- | ---------- |
| In progress | `47fc9ee4` |
| In review   | `df73e18b` |

## 注意

- `project` スコープが必要
- スコープがない場合はステータス更新をスキップしてフローを継続する
- 失敗してもPR作成や実装フローはブロックしない
