---
name: distill
description: >-
  Distill を Claude Code から操作したいときに使う。紐付けから教材・クイズ生成までを
  一度に通す（full）ほか、紐付け（link）、取り込み（ingest）、公開（publish）、
  状態確認（status）を 1 つの入口にまとめる。サブコマンドは本文の Commands を参照。
argument-hint: "full | link | ingest | publish | status [--no-display] [--days N | --all]"
user-invocable: true
---

Distill の CLI を Claude Code から呼ぶための入口。`distill` は PATH に無いので、
venv 内の実体を絶対パスで叩く。

```bash
DISTILL="$HOME/develop/other/distill-of-ai-process/.venv/bin/distill"
```

## Commands

引数で受け取ったサブコマンドだけを実行する。指定が無ければ `status` を実行し、
何ができるかを提示する。

| 引数 | 実行内容 |
|------|----------|
| `full` | 紐付け → 取り込み → 教材とクイズの生成までを一度に通す |
| `link` | いま作業しているプロジェクトを収集対象として登録し、続けて取り込む |
| `ingest` | セッションログを取り込む（対象は収集フラグに従う） |
| `publish` | 静的サイトを書き出して Cloudflare Pages へデプロイする |
| `status` | 収集対象・教材の生成状況・未反映の有無を報告する |

### full

紐付けからクイズ作成までを一度に通す。それぞれの段は下の個別コマンドと同じものを呼ぶ。

1. **紐付け + 取り込み** — `link` の節と同じ手順を実行する。
2. **生成対象の決定** — 教材がまだ無い日を新しい順に並べる。

```bash
DB="${DISTILL_DB:-$HOME/.distill/distill.db}"
# 対象プロジェクトは cwd で引く。link の出力 1 行目にも同じキーが出る。
sqlite3 "$DB" "PRAGMA query_only=1;
  SELECT DISTINCT substr(s.started_at,1,10) AS d
  FROM sessions s
  JOIN projects p ON p.id = s.project_id
  WHERE p.cwd = '$(pwd)'
    AND NOT EXISTS (
      SELECT 1 FROM day_units u
      WHERE u.project_dir_name = p.dir_name
        AND u.date = substr(s.started_at,1,10))
  ORDER BY d DESC;"
```

3. **生成** — Skill ツールで `distill-learn` を起動し、対象プロジェクトと日付を渡す。
   project_unit が未生成ならそれも作らせる。教材とクイズは distill-learn が作る。
   このスキルは生成そのものを行わない。

**既定は project_unit と最新 3 日分**。`--days N` で件数を変え、`--all` で全未生成日を対象にする。
上限を設けるのは、未生成日が多いと生成が長時間になり、途中で止めにくいため。
対象が 5 日を超えるときは、件数と所要の見込みを伝えて実行してよいか確認する。

4. **報告** — 紐付けたリポジトリ、取り込んだファイル数、生成した project_unit と日付、
   クイズの問数を伝える。あわせて「公開サイトへは `/distill publish` まで反映されない」ことを明示する。

### link

```bash
"$DISTILL" link          # 引数に --no-display があればそのまま渡す
"$DISTILL" ingest
```

`link` は引数を渡さなければ現在の作業ディレクトリを対象にする。git remote があれば
参照リポジトリも登録する。`--no-display` を付けると収集だけ行い、画面と公開サイトには出さない。

### ingest

```bash
"$DISTILL" ingest
```

取り込む対象は Distill 側の収集フラグで決まる。ここでフラグを操作しない。
`database is locked` が出たら、`distill serve` が動いていないかを `lsof` で確認する。
WAL でも、残留したプロセスが掴んでいると書き込めない。

### publish

```bash
cd "$HOME/develop/other/distill-of-ai-process"
rm -rf ./dist && "$DISTILL" export-static --out ./dist
PATH="$HOME/.local/share/mise/installs/node/20.19.0/bin:$PATH" \
  npx --yes wrangler@3 pages deploy ./dist --project-name=distill
```

wrangler は v4 が Node 22 以上を要求するため v3 を明示する。
デプロイ後、本番 URL が未認証で 401 を返すことを確認する。

### status

```bash
DB="${DISTILL_DB:-$HOME/.distill/distill.db}"
sqlite3 "$DB" "PRAGMA query_only=1;
  SELECT '収集 ' || SUM(collect) || ' / 表示 ' || SUM(display) || ' / 全 ' || COUNT(*)
  FROM projects WHERE ignored=0;
  SELECT '教材 project ' || (SELECT COUNT(*) FROM project_units)
      || ' / day ' || (SELECT COUNT(*) FROM day_units);"
```

読み取りは `PRAGMA query_only=1` を前置する。DB は WAL なので `sqlite3 -readonly`
は共有メモリを作れず開けないことがある。

## 報告するとき

- 実行したサブコマンドと結果（取り込んだファイル数、デプロイ先 URL など）を伝える
- `link` と `ingest` は教材を作らない。作るのは `distill-learn` スキル。
  `full` はそれらを順に呼ぶだけで、生成の中身は distill-learn が決める
- 公開サイトは `publish` するまで変わらない。取り込んだだけでは反映されない
