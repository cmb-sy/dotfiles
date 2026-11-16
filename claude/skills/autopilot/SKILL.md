---
name: autopilot
description: >-
  設計を 1 回承認したら、計画・実装・検証を途中で止まらずに最後まで進め、
  報告 md（研鑽つき）で締めたいときに使う。経路で「任せきり」を選んだときに起動する。
  superpowers の brainstorming → writing-plans → subagent-driven-development を
  そのまま使い、判断の表・止まらない規則・報告 md の 3 つだけを足す。
argument-hint: "[作業の内容]"
user-invocable: true
---

# autopilot — 承認 1 回で最後まで進める

## 流れ

```
superpowers:brainstorming（判断をここで出し切る）
→ 設計 md（判断の表つき）を承認してもらう
→ superpowers:writing-plans（承認を取らずに進む）
→ superpowers:subagent-driven-development（止まらない）
→ 報告 md を書き、link をチャットに出す
```

- **承認は設計の 1 回だけ。** superpowers の各 skill の手順はそのまま使い、中身を写さない
- **writing-plans の承認は取らない。** 書いた計画は自分で点検し、そのまま実行に入る。実行方式は Subagent-Driven にする
- 計画を書く途中で、設計の判断の表に答えの無い判断が出たら「計画の前提が崩れた」として止まる

## 設計に足す判断の表

brainstorming で書く設計 md に、承認を求める前に次の表を足して埋める。

| 途中で出そうな判断 | 答え | 理由 |
|---|---|---|

- 実装・検証の途中で迷いそうな点（命名、置き場所、既存との互換、テストの範囲、失敗時の扱い）を先に出し切る
- 空欄を残したまま承認を求めない
- チャットには結論と判断の表を書き、設計の全文は link で開けるようにする（link の出し方は「置き場所と git 管理外」）

## 実行中は止まらない

止まってよいのは次の 3 つだけ。

1. 外向き操作（GitHub・Slack への書き込み、PR 作成、外部への共有）。草案を出して承認を待つ
2. 戻せない操作（本番データ、force push、追跡外ファイルの削除）
3. 計画の前提が崩れた（設計に無い判断が要る、前提の API・ファイルが無い、同じ理由のテスト失敗が 3 回続く）

「任せきり」を選んだことを、その実行中の commit の許可とみなす（どのリポジトリでも 3 択を出さない）。push は CLAUDE.md のとおりにする。自動 commit/push が有効なリポジトリでは自動で push し、それ以外では push を外向き操作として最後に 1 回だけ確かめる（commit ごとには問わない）。

それ以外の予定外の判断は推奨で決めて進む。決めたら報告用の記録に 1 行足す（判断・選んだ答え・理由）。

## 置き場所と git 管理外

| もの | 置き場所 |
|---|---|
| 設計 | superpowers:brainstorming の既定の置き場所 |
| 計画 | `docs/superpowers/plans/YYYY-MM-DD-<topic>.md` |
| 報告 | `docs/superpowers/reports/YYYY-MM-DD-<topic>-report.md` |

計画と報告、md-view が生成する html は git 管理外にする。最初の書き込みと最初の md-view（設計の link を出す前）の前に確かめる。

```bash
git check-ignore -q docs/superpowers/plans/x.md || echo 'docs/superpowers/plans/' >> "$(git rev-parse --git-path info/exclude)"
git check-ignore -q docs/superpowers/reports/x.md || echo 'docs/superpowers/reports/' >> "$(git rev-parse --git-path info/exclude)"
git check-ignore -q docs/superpowers/x/x.html || echo 'docs/superpowers/**/*.html' >> "$(git rev-parse --git-path info/exclude)"
```

- 足す先は `.git/info/exclude`（worktree でも `git rev-parse --git-path` で本体のものを指す）。リポジトリの .gitignore とグローバル gitignore は触らない
- md をチャットで見せるときは `"$HOME/dotfiles/bin/md-view" <md>` を実行し、出力された `file://` の URL をそのままチャットに貼る

## 報告 md

次の 4 節で書く。

```
## やったこと
## 確かめた証拠
## 推奨で決めた判断
## 研鑽
```

- やったこと: 計画のタスクごとに結果を 1 行
- 確かめた証拠: 実際に実行したコマンドと、観測した出力（抜粋）。コードを読んだだけのものは証拠にしない
- 推奨で決めた判断: 実行中の記録の 1 行ずつ。無ければ「無し」
- 書き終えたら md-view で link を出し、チャットには結論と link を書く

## 研鑽

次の 6 軸から、この作業で実際に場面があった軸を 1〜2 個選ぶ。

| 軸 |
|---|
| 問題の定義 |
| 設計の天秤 |
| AI の出力の検証 |
| 壊れ方と観測 |
| データの意味 |
| 安全と統制 |

- 軸ごとに、この作業で実際に起きた場面と、そこで何を判断したか・何が危うかったかを書く。起きていない場面を作らない
- 最後に「自分で確かめる問い」を 1 つ置く（答えは書かない）

### distill へ写す

研鑽の節を distill の正本へ写す。写すのは次の両方を満たすときだけ。

1. `"$HOME/dotfiles/bin/distill-repo-name"` で作業リポジトリのプロジェクト名を得られる
2. その名前が `$HOME/develop/distill-vault/対象.md` の `## プロジェクト` の下に `- <名前>` として載っている

写し先は `$HOME/develop/distill-vault/プロジェクト/<名前>/記録/<YYYY-MM-DD-HHMM>.md`。

- 本文の先頭を `# 研鑽: <topic>` の H1 にし、続けて研鑽の節の中身を置く
- 同じ名前のファイルがあれば上書きせず、分を 1 つ進める
- `プロジェクト/<名前>/` の直下に別のディレクトリを作らない（記録として表示されない）
- 条件を満たさないときは写さず、報告 md の中だけに残す
