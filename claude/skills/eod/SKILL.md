---
name: eod
argument-hint: "[--exclude <キーワード>...]"
---

その日の作業を1コマンドで締める。**linear-refresh -> daily-log -> project-update -> CloudLog入力 -> reflect** を順次実行する。

デフォルトで `--exclude siori --exclude generate-video` を適用する。`--exclude` 追加指定があれば合算する。

---

## 実行フロー

### Step 1: Linear Refresh

`/linear-refresh` スキルに従い実行する。

- 収集した Linear チケット情報を以降のステップで再利用する（二重取得しない）

### Step 2: daily-log（セッション + CloudLog）

以下と等価な処理を実行する:

```
/daily-log --session --cloudlog --exclude siori --exclude generate-video [追加 --exclude ...]
```

- Step 1 で取得済みの Linear Done チケットをそのまま使う（`linear issue mine` 再実行しない）
- Claude Code セッション・GitHub・Obsidian・Slack を収集
- 対応表に従い CloudLog エントリを生成

### Step 3: project-update

Step 2 の session-digest 結果を引き継ぎ、`02_projects/` 内の対応ファイルを差分更新する。

- セッション走査は**再実行しない**（Step 2 の結果を使い回す）
- `--exclude` 対象はスキップ

### Step 4: CloudLog 入力

Playwright でブラウザを開き、Step 2 で生成したエントリを自動入力する。

-> 詳細は daily-log の「Step CL: CloudLog 入力実行」を参照。

### Step 5: reflect（振り返り）

`/generate-problem` スキルに従い、本日の作業を問題形式で振り返る。

- Step 2 の session-digest と daily-log の内容を素材として使う（再収集しない）
- 結果は日報と `01_quant/reflect_log.md` に記録される

---

## 完了報告

- 更新した日報ファイルパス
- Linear Refresh 結果（チケット件数）
- CloudLog 入力件数・合計時間
- 走査したセッション数・除外プロジェクト
- reflect 結果（正解率）
