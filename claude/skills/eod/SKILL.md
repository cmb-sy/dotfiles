---
name: eod
argument-hint: "[--exclude <キーワード>...]"
---

その日の作業を1コマンドで締める。**Slack+GitHub収集 -> obsidian-refresh -> daily-log -> CloudLog入力 -> generate-problem** を順次実行する。

デフォルトで `--exclude siori --exclude generate-video` を適用する。`--exclude` 追加指定があれば合算する。

---

## 実行フロー

### Step 1: Slack + GitHub 情報収集（並列）

以降のステップで使い回すため、最初に一括取得する。

- **Slack**: 本日の自分の発言・関与したスレッドを `/slackcli` で取得
- **GitHub**: 本日のコミット・PR・レビュー・Issue コメント/更新を `gh` で取得

この結果を Step 2・3 で再利用する（二重取得しない）。

### Step 2: Obsidian Refresh

`/obsidian-refresh` スキルに従い実行する。Step 1 の Slack + GitHub 情報を入力として渡す。

- GitHub Issues（cmb-sy assigned）を収集し `02_projects/task.md` を最新化する
- Step 1 の Slack + GitHub 情報をもとに `02_projects/` の「現在の状況」を差分更新する

### Step 3: daily-log（セッション + CloudLog）

以下と等価な処理を実行する:

```
/daily-log --session --cloudlog --exclude siori --exclude generate-video [追加 --exclude ...]
```

- Step 1 で取得済みの Slack + GitHub 情報をそのまま使う（再取得しない）
- Claude Code セッションログを走査して session-digest を生成
- 対応表に従い CloudLog エントリを生成

### Step 4: CloudLog 入力

Playwright でブラウザを開き、Step 3 で生成したエントリを自動入力する。

-> 詳細は daily-log の「Step CL: CloudLog 入力実行」を参照。

### Step 5: generate-problem（振り返り）

`/generate-problem` スキルに従い、本日の作業を問題形式で振り返る。

- Step 3 の session-digest と daily-log の内容を素材として使う（再収集しない）
- 結果は日報と `01_quant/reflect_log.md` に記録される

---

## 完了報告

- 更新した日報ファイルパス
- obsidian-refresh 結果（新規追加・クローズ更新件数・現在の状況更新件数）
- CloudLog 入力件数・合計時間
- 走査したセッション数・除外プロジェクト
- generate-problem 結果（正解率）
