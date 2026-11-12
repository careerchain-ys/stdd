報告は `reviewing-changes` の `references/reporting.md` の書式で書く（パスは依頼文で渡される。Claude は `.claude/skills/`、
Codex は `.agents/skills/` の下）。指摘ごとに 4 項目（発生条件・頻度・影響・影響先）と確信の段階を書き、重大度・総合判定・
処置は書かない。直すかどうかと次へ進むかどうかは、呼び出し元が台帳のスクリプトで決める（処置が「直す」の指摘が 0 件なら進む）。
