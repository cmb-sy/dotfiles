---
name: gain
description: >-
  技術情報を「集めて得る」ときに使う情報収集スキル。watch モード（GitHub /
  サービス changelog / エンジニア発信 / ニュース / dotfiles peer を横断観測し
  Obsidian にダイジェスト蓄積）と research モード（トピックを Web + 自リポジトリ
  横断で深掘り）を持つ。旧 peer-watch を吸収。フラグは本文の「起動」を参照。
argument-hint: "[watch|research|peers] [--only <scope>] [--target X] [--days N] [--dry-run]"
user-invocable: true
---

<!-- gain = "gather intel" + "得る(gain)". A portmanteau: gathering and obtaining tech intel. -->

# gain — 情報収集スキル

技術情報を集めて得るための単一スキル。2 モードを持つ。

- **watch（レーダー）**: `sources.yaml` を駆動し、前回以降の差分をダイジェスト化する
- **research（深掘り）**: トピックを Web 知見 × 自リポジトリ実態で調べる

**開始時アナウンス:** 「gain を開始します。」続けて選択されたモード/スコープを明示する。

## 起動

```
/gain                                   # 引数なし → 対話メニュー（デフォルト）
/gain watch                             # 全ウォッチを直接実行
/gain watch --only <scope> [--target X] # 単一スコープ、対象指定
/gain research <topic>                  # 深掘りを直接実行
/gain peers [--user <handle>] [--days N] [--dry-run]  # 旧 peer-watch 互換
```

- `<scope>`: `peers | github | services | engineers | sns | news`
- `engineers` は blog + SNS の両方、`sns` は engineers の SNS のみ
- `--days` は peers スコープの観測窓（default 30）
- `--dry-run` は peers スコープの採用対話・保存をスキップ

ARGUMENTS をパースし、第 1 引数（`watch`/`research`/`peers`）、`--only`、`--target`、`--days`、`--dry-run` を抽出する。第 1 引数が無ければ対話メニューへ。

## 対話フロー（引数なし起動時）

AskUserQuestion は 1 問最大 4 択のため 2 段構成にする。

**Q1「何をしますか?」**
1. 全ウォッチ（sources.yaml 全ソース）
2. ソースを選んで watch
3. research（深掘り調査）
4. dotfiles peer 観測（採用ワークフロー）

**Q2（Q1=2 のときのみ）「どのソース?」**
1. GitHub（一般リポジトリ）
2. SNS
3. changelog（サービス更新）
4. ニュース

- 単一スコープ / research を選んだら、続けて**対象を追加質問**する（例: SNS → 「誰の SNS?」を `sources.yaml` の登録者 + AI 推測候補 + 自由入力で提示）
- 選んだアドホック対象が `sources.yaml` に未登録なら、実行後に **「今後も watch 対象に追加しますか?」** を AskUserQuestion で確認 → YES で該当セクションに追記（単発 → 永続化）。ユーザー承認なしに追記しない
