---
name: distill
description: >-
  Distill（Obsidian の 99_distill を静的サイトにして読む仕組み）を Claude Code から
  操作したいときに使う。状態確認（status）、陳腐化したプロジェクト概要の洗い出しと
  書き直し（refresh）、サイトの再生成（build）、公開サイトへの反映（deploy）を
  1 つの入口にまとめる。サブコマンドは本文の Commands を参照。
argument-hint: "status | stale | refresh [N] | build | deploy | url <vault 内のファイル>"
user-invocable: true
---

Distill の CLI を Claude Code から呼ぶための入口。`distill` は PATH に無いので、
venv 内の実体を絶対パスで叩く。

```bash
DISTILL="$HOME/develop/other/distill-of-ai-process/.venv/bin/distill"
```

**データベースは無い。** 正本は Obsidian の `99_distill/` だけで、CLI は vault を
読んで静的サイトを書き出す。教材そのものを作るのは `distill-project` skill で、
この skill は生成を行わない。

## Commands

引数で受け取ったサブコマンドだけを実行する。指定が無ければ `status` を実行し、
何ができるかを提示する。

| 引数 | 実行内容 |
|------|----------|
| `status` | サイトの規模・陳腐化件数・自動化の稼働状況を報告する |
| `stale` | 概要.md が古くなっているプロジェクトを一覧する |
| `refresh [N]` | 陳腐化した概要を書き直す（既定 2 件、`0` で下見のみ） |
| `build` | vault を読んでローカルのサイトを再生成する |
| `deploy` | 公開サイト（Cloudflare Pages）へ反映する |
| `url <path>` | vault 内のファイルが出るページの URL を 1 行で出す |

### status

3 つを順に出す。

```bash
"$DISTILL" build --out "$HOME/.distill/site" | tail -2   # 規模
"$DISTILL" stale                                          # 陳腐化
launchctl print "gui/$(id -u)/com.distill.refresh" 2>/dev/null | grep -E "state|last exit"
```

自動化は 3 本ある。**動いているかを推測で答えない。** 上の `launchctl print` と
ログの日付で確かめる。

| ラベル | 何を | いつ |
|---|---|---|
| `com.snakashima.distill-serve` | `~/.distill/site` を 8080 で配信 | 常時 |
| `com.snakashima.distill-publish` | vault が変わっていればビルドして公開 | 5 分ごと |
| `com.distill.refresh` | 陳腐化した概要を書き直す | 1 日 1 回 |

### stale

```bash
"$DISTILL" stale
```

`概要.md` の frontmatter の `sha`（書いたときの commit）と手元のクローンの HEAD を
比べ、未反映の commit 数を出す。**「判定できません」は「古くない」ではない** —
sha が無いか、その commit が手元に無い状態を指す。書き直せば sha が入る。

### refresh

```bash
cd "$HOME/develop/other/distill-of-ai-process"
./scripts/refresh-overviews.sh 2            # 2 件まで書き直す
./scripts/refresh-overviews.sh 0            # 対象を出すだけ
./scripts/refresh-overviews.sh 1 dotfiles   # 名指しで 1 件
```

各対象について、そのクローンを作業ディレクトリにしてヘッドレスの Claude を起動し、
`distill-project` skill に概要だけを書き直させる。**1 回の実行で処理する件数を
絞る。** 概要 1 本の書き直しはリポジトリ全体を読む作業なので、溜まった分を一度に
回すと時間もトークンも青天井になる。残りは次の実行で対象になる。

ログは `~/.distill/logs/refresh-overviews.log`。失敗しても launchd は黙るので、
報告するときはここを読む。

### build

```bash
"$DISTILL" build --out "$HOME/.distill/site"
```

**ビルドは出力先を丸ごと作り直す。** 配信中のサーバーがそのディレクトリを掴んで
いると古いページを返し続けるので、手で確かめるときは配信を入れ直す。

### deploy

```bash
cd "$HOME/develop/other/distill-of-ai-process"
./node_modules/.bin/wrangler pages deploy "$HOME/.distill/site" \
    --project-name=distill --branch=main
```

`--branch=main` を必ず付ける。付けないとプレビュー環境に出て、本番 URL が古いまま
残る。通常は `com.snakashima.distill-publish` が 5 分ごとに自動で行うので、
**手で叩くのは vault ではなくコードを変えたとき**（自動配信は vault の変化しか見ない）。

### url

```bash
"$DISTILL" url "<vault 内の md ファイル>"
```

書いたファイルがどのページに出るかを 1 行で返す。完了報告にはこの URL を出す。

## 報告するとき

- 実行したサブコマンドと、観測した出力（件数・URL・失敗の実文）を伝える
- **この skill は教材を作らない。** 作るのは `distill-project`。`refresh` はそれを
  無人で呼ぶだけで、中身の判断は `distill-project` が持つ
- 公開サイトの反映は自動配信に任せる。急ぐときだけ `deploy` を叩く
