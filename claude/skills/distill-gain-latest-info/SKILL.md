---
name: distill-gain-latest-info
description: >-
  技術情報を「集めて得る」ときに使う情報収集スキル。watch モード（GitHub /
  サービス changelog / エンジニア発信 / ニュース / dotfiles peer を横断観測し
  Obsidian にダイジェスト蓄積）と research モード（トピックを Web + 自リポジトリ
  横断で深掘り）に加え、sources モード（監視先の一覧を巡回・収穫の実績つきで
  表にし、対話で外す・追加する・直す）を持つ。フラグは本文の「起動」を参照。
argument-hint: "[watch [--only <scope>] [--target X] | research <topic> | sources]"
user-invocable: true
---

<!-- distill-gain-latest-info = "gather intel" + "得る(gain)". A portmanteau: gathering and obtaining tech intel. -->

# distill-gain-latest-info — 情報収集スキル

技術情報を集めて得るための単一スキル。2 モードを持つ。

- **watch（レーダー）**: `sources.yaml` の監視先のうち今週まだ確認していないものだけを対象に、差分をダイジェスト化する
- **research（深掘り）**: トピックを Web 知見 × 自リポジトリ実態で調べる
- **sources（監視先の編集）**: 監視先を実績つきの表で見せ、何を外す・足す・直すかを対話で決めて `sources.yaml` に反映する

watch の収集・ダイジェスト生成フェーズはユーザーに質問しない。対話が要る場面（改善提案の採否）は生成物に書いて返すだけに留め、承認は呼び出し元（`/eod` 本体、または直接起動した対話フロー）が行う。

**開始時アナウンス:** 「distill-gain-latest-info を開始します。」続けて選択されたモード/スコープを明示する。

## 起動

```
/distill-gain-latest-info                                   # 引数なし → 対話メニュー（デフォルト）
/distill-gain-latest-info watch                              # due な監視先のみ実行
/distill-gain-latest-info watch --only <scope> [--target X]  # 単一 scope、対象指定
/distill-gain-latest-info research <topic>                   # 深掘りを直接実行
/distill-gain-latest-info sources                            # 監視先を表で見せて対話で編集
```

- `<scope>`: `peers | github | services | engineers | news`（`sources.yaml` のトップレベルキーと一致）
- `--target X` は選択 scope 内の対象を X に限定する（peers なら handle、github なら repo、services/engineers なら name、news なら query）

ARGUMENTS をパースし、第 1 引数（`watch`/`research`/`sources`）、`--only`、`--target` を抽出する。第 1 引数が無ければ対話メニューへ。

## 対話フロー（引数なし起動時）

AskUserQuestion は 1 問最大 4 択のため 2 段構成にする。人が直接起動した場合にのみ通る経路であり、`/eod` は常に `watch` を明示して呼ぶためこの経路を通らない。

**Q1「何をしますか?」**
1. 全ウォッチ（`sources.yaml` の due な監視先すべて）
2. scope を選んで watch
3. research（深掘り調査）
4. 監視先を編集する（sources モードへ）

**Q2（Q1=2 のときのみ）「どの scope?」** `sources.yaml` の 5 scope（peers/github/services/engineers/news）から選ぶ。1 問 4 択の枠に収まらないため、5 番目は自由入力枠で拾う。

- scope を選んだら続けて**対象を追加質問**する（例: news → 「どのクエリ?」を `sources.yaml` の登録内容 + AI 推測候補 + 自由入力で提示）
- 選んだアドホック対象が `sources.yaml` に未登録なら、実行後に **「今後も watch 対象に追加しますか?」** を AskUserQuestion で確認 → YES で該当セクションに追記（単発 → 永続化）。ユーザー承認なしに追記しない

## watch: 収集フロー

### Step 1: Due 判定

まず `$HOME/dotfiles/bin/gain-state prune $HOME/dotfiles/claude/skills/distill-gain-latest-info/sources.yaml` を実行する。監視先から外した対象の実績が状態ファイルに残り続けると、`## 改善提案` の「実績の無い監視先」が既に消えた対象を挙げる。出力（消した `<scope>\t<key>`）があれば `## 改善提案` に 1 行で残す。

次に `$HOME/dotfiles/bin/gain-state due $HOME/dotfiles/claude/skills/distill-gain-latest-info/sources.yaml` を実行し、`<scope>\t<key>` 形式の行を得る。`--only`/`--target` があればここでその scope/key に絞り込む。

**パスは絶対で書く。** このスキルはどのリポジトリからでも起動されるので、相対パスは CWD が dotfiles のときしか解決しない。

**終了ステータスを先に見る。** 出力が 0 行になる状況は 2 つあり、区別できるのは終了ステータスだけである。

| exit | 意味 | 対応 |
|---|---|---|
| 非 0 | sources.yaml を読めなかった（不在・parse 不能） | `## エラーハンドリング` の該当行に従って報告し終了する。**「確認済み」とは報告しない。** `record` を呼ばないので、**`sources.yaml` を直して再実行すれば同じ週のうちに全件そのまま対象に残る**（週明けを待つ必要はない） |
| 0 かつ 0 行 | 今週は全監視先を確認済み | 「今週は全監視先を確認済み」（`--only` 指定時は「`<scope>` は今週確認済み」）と報告して終了する |

どちらの場合も**ダイジェストファイルは作らない。** 取得失敗を「確認済み」と報告すると、その週の観測が丸ごと飛んだことに誰も気付けない。

### Step 2: 収集（並列）

残った `<scope>\t<key>` を scope ごとにグルーピングし、scope 内は 1 対象 = 1 サブエージェント（`general-purpose`、自己完結プロンプト）で並列 dispatch する（メイン context 保護）。lookback window は 14 日固定とする（`gain-state due` が週次の頻度を保証するため、取りこぼし防止のバッファとして十分）。各エージェントは**構造化データ（YAML）**を返す。

| scope | 取得方法 | 信頼度 |
|---|---|---|
| peers | commit（`gh api /repos/{owner}/{name}/commits?since=<iso8601>`）+ 新規追加ファイル + 注目ファイル（README.md/Brewfile/`*.json`/`*.yaml`/`flake.nix`/`chezmoi*.toml`）更新有無 + star 数 | 高 |
| github | `gh api /repos/{repo}/commits?since=<iso>` + `/releases` | 高 |
| services（`watch: changelog`・既定） | changelog URL を WebFetch → 直近 14 日以内のエントリ抽出 | 中〜高 |
| services（`watch: diff`） | `curl -sSL <url>` の出力を `$HOME/dotfiles/bin/gain-state snapshot <scope> <key>` に渡し、返ってきた差分を読む。空なら「変更なし」 | 高 |
| engineers | blog は RSS/Atom を WebFetch（無ければスクレイプにフォールバック）、SNS は WebSearch で直近の注目投稿 | blog 高 / SNS **低（best-effort）** |
| news | クエリごとに WebSearch → 影響度・新しさでフィルタ | 中 |

**`watch: diff` を使う理由:** 日付つきエントリを持たない文書（リファレンス docs、公開 system prompt）は、日付で抽出するものが無い。既定ルールで取ると毎週「収穫 0」として記録され、**形の不一致が実績の低さとして積み上がって除外候補の判定を狂わせる。** 差分で見れば、変わったときだけ収穫になる。初回は差分が空になる（全文を出すとダイジェストが 1 件で埋まるため）。

**peers の対象解決:** `key` は handle。`peers.overrides` に該当があればその `owner/name`、無ければ `<handle>/dotfiles`。`gh api /repos/{owner}/{name}` で存在確認し、404 は 1 行警告で skip する（skip 分は Step 4 の `gain-state record` を呼ばない）。

SNS 由来のエントリは必ず「信頼度低」ラベルを付す。取得ゼロは正常（「該当なし」と記載し、Step 4 の record は findings=0 で呼ぶ）。

### Step 3: 統合・分析（メイン実行、サブエージェントに投げない）

**既出照合（URL・タイトル）:** `情報収集/` の直近 14 日分のファイルの URL・タイトルと突合し、重複エントリを除外する。**照合の窓は収集の窓（14 日）と一致させる。** 短くすると、週次実行では前回のダイジェスト（約 7 日前）が照合の外に落ち、4〜14 日前のエントリをそのまま再掲する。

**既出照合（テーマ）:** **同じ週に深掘りした主題は、もう深掘りしない。** URL が違っても
同じ話題なら読み手にとっては繰り返しになる。

- **判定材料**: 同一週（月曜起点）に書いた `情報収集/YYYY-MM-DD.md` の
  `## 深掘り N: <主題>` 見出しを集め、候補の主題と突合する
- **判定基準**: 「先週これを読んだ人が、今週これを読んで新しいことを知るか」。知らないなら落とす
- 落とした候補は**件名だけを 1 行で残し、`（同週に深掘り済み: <日付>）` と添える**。
  見落としでないことを示すため
- **同じ主題でも、結論が変わる新情報があれば深掘りしてよい。** その場合は前回の記述を
  参照し、何が変わったかを冒頭に書く

週が明けたら制限は外れる。同じ主題を継続して追うこと自体は妨げない。

残った候補それぞれに:
- **何が変わったか**: 一次情報を読んで書く（タイトルの引き写しにしない）。専門用語は「そもそも何か」を 1〜2 文で解説
- **自分の環境で何が変わるか**: `$HOME/dotfiles` を実 grep/find/ls で確認し（LLM 推測禁止）、該当する自リポジトリのファイル名まで名指しする
- **次の一手**: 試す / 様子見 / 関係なし のいずれかを選び、理由を添える

全 scope 合算で **3〜5 件**を選んで深掘り記述する。選ばれなかった候補は件名だけを 1 行で残す（見落としでないことを示すため）。

### Step 4: 記録・出力

`$HOME/develop/distill-vault/情報収集/YYYY-MM-DD.md` に書く（無ければ作成、同日ならファイルの既存見出しに追記し重複させない）。

**取得に成功した**監視先ごとに `$HOME/dotfiles/bin/gain-state record <scope> <key> <採用件数>` を呼ぶ。**採用 0 件でも呼ぶ**（「取得はできたが収穫が無かった」という記録自体が翌週までのクールダウンと `## 改善提案` の根拠になる）。取得自体が失敗した監視先は呼ばない（詳細は `## エラーハンドリング` を参照。次回実行時にそのまま対象に残り、一時的な失敗で観測が丸々1週間飛ぶことを避ける）。

**`record` の終了ステータスも見る。** 非 0 で返った監視先は完了報告に 1 行で挙げる。実績が記録されていないので次回そのまま再訪する。ダイジェストは書けているのに実績だけが落ちると、次回に同じ内容を再掲することになる。

| exit | 意味 |
|---|---|
| 64 | 採用件数が数値でない（呼び出し側の誤り） |
| 75 | 30 秒待っても書き込みロックを取れなかった。前回の実行が強制終了して `~/.local/state/gain/sources.tsv.lock` が残っている可能性がある。メッセージの指示に従う |

### 完了報告

```
distill-gain-latest-info watch 完了。対象 <n> / due <m>
記録先: distill-vault/情報収集/<date>.md
```

Step 1 で 0 行だった場合はその旨のみ報告する。

## research モード

トピックを受け取り並列で:
- **Web**: 既存 `deep-research` スキルを invoke（fan-out 検索 + adversarial verify + 出典付き）。利用不可なら内蔵 WebSearch で縮退し、その旨を明示。**縮退時も全主張に出典 URL を付ける**（実在確認済みのみ。確認できない主張は「未検証」と明記）
- **自リポ**: `code-explorer` 系サブエージェントで現リポジトリの関連構造・依存・既存実装を調査

オーケストレーターが両者を統合:
- 技術選定 → 導入可否・影響範囲・既存コードとの整合性
- 外部リポ理解 → 設計/実装の要約 + 自リポへの取り込みポイント

出力: `$HOME/develop/distill-vault/情報収集/YYYY-MM-DD.md` に `## Research: <topic>` 節として追記する。同日に watch を実行済みで既に `## 改善提案` 節がある場合は、その節の直前に挿入する（`## 改善提案` は常にファイル末尾に置く）。

## sources モード（監視先の編集）

`sources.yaml` を手で開かずに、監視先を見直して反映するための経路。**表を出す → 何を変えるか決める → 検証して書く → 差分を見せて確定する**の順で進め、順を飛ばさない。

### Step 1: 現状を表で出す

`$HOME/dotfiles/bin/gain-state list $HOME/dotfiles/claude/skills/distill-gain-latest-info/sources.yaml` を実行する。1 行 1 監視先で `scope / key / 最終 / 巡回 / 収穫 / 説明` がタブ区切りで出る。

**`list` の終了ステータスを先に見る。** 非 0 なら表を出さずに、`## エラーハンドリング` に従って報告し終了する。状態ファイルが壊れている（ディレクトリ・FIFO 等）ときも行自体は出るので、**出力の見た目では気付けない。** そのまま表にすると、全件を「未巡回」と誤って見せる。

scope ごとに表にして見せる。列は `key | 巡回 | 収穫 | 最終 | 説明`。

- **巡回 1 以上で収穫 0** の行は「外す候補」として太字にする。外すかどうかの主材料はここにしかない
- **巡回 0**（最終が `-`）は「未巡回」と書く。実績が無いのではなく、まだ見ていない
- 巡回 1 回だけで収穫 0 のものを外す判断は早い。スキルの基準は「2〜3 回続けて同水準なら除外候補」で、1 回で外すなら**そう明示した判断**として扱う

続けて、直近の `$HOME/develop/distill-vault/情報収集/YYYY-MM-DD.md` の `## 改善提案` を読み、未反映の提案を日付つきで表の下に並べる。無ければ「未反映の改善提案: なし」と書く。提案は表と**同じ画面**で見せる。別々に見せると、提案の根拠（実績）と提案が結び付かない。

**反映済みかどうかは `gain-state list` の出力と突き合わせて判定する。** 記憶や読み返しに頼らない。ダイジェストが増えるほど手で辿るのは重くなり、間違いやすくなる。

| 提案の型 | 反映済みの判定 |
|---|---|
| 追加（`<scope>` に `<key>` を足す） | その `<key>` が `list` の出力に有る |
| 除外（`<key>` を外す） | その `<key>` が `list` の出力に無い |
| URL・説明の変更 | `sources.yaml` の現在値が提案後の値と一致する |
| 作業の提案（監視先の変更ではないもの） | **判定対象外**と明記して並べる。消さない |

### Step 2: 何を変えるか決める

`AskUserQuestion`（header: `監視先`、1 問）で「外す / 追加する / URL・説明を直す / 何もしない」を選ばせる。

- **外す**: 外す候補を先頭に並べ、key を列挙してもらう。候補が 4 件以下なら `multiSelect: true` の選択肢にし、超えるなら自由入力で受ける
- **追加する**: scope・key・`note`（なぜ見るのか）を受ける。`note` が無ければ 1 問で聞く。次に自分で見返したときに「なぜこれを見ているのか」が分からない監視先は、除外候補になった時点で判断できない
- **URL・説明を直す**: 対象の key と新しい値を受ける

1 回のやり取りで複数の変更をまとめてよい。変更のたびに聞き直さない。

### Step 3: 検証して書く

書く前に確かめる。確かめずに書いた 1 行が、翌週の watch を 1 scope まるごと止める。

| 変更 | 確認 |
|---|---|
| URL を追加・変更 | `curl -sS -o /dev/null -w '%{http_code} %{num_redirects} %{url_effective}' -L <url>` を実行する。200 でなければ止める。**転送があれば着地先（`url_effective`）を書く。** 転送元を書くと、転送を追わない取得経路で失敗する |
| github の repo を追加 | `gh api /repos/<owner>/<repo>` で存在を確認する。404 なら止める |
| peers の handle を追加 | `gh api /repos/<handle>/dotfiles` で確認する。無ければ `peers.overrides` に `owner/name` を書くか、止める |
| news の query を追加 | 事前確認の手段は無い。同じ意図のクエリが既に無いかだけ見る |
| すべて | 同じ key が**別の scope**に無いか見る。あれば伝える（同じ対象が 2 枠を消費する） |

`sources.yaml` を書き換えたら:

1. `python3 -c "import yaml; yaml.safe_load(open('<path>', encoding='utf-8'))"` で parse できることを確かめる。`key: []` と実体リストの共存は不正な YAML になる
2. `$HOME/dotfiles/bin/gain-state due <path>` の行数が、意図した増減になっていることを確かめる

### Step 4: 差分を見せて確定する

1. `git -C $HOME/dotfiles diff -- $HOME/dotfiles/claude/skills/distill-gain-latest-info/sources.yaml` を見せる
2. 外した監視先があれば `$HOME/dotfiles/bin/gain-state prune <path>` を実行し、消えた実績を 1 行で報告する
3. **`sources.yaml` だけを stage して** commit し、push する。dotfiles には無関係な未コミット変更が残っていることが多く、`add -A` はそれを巻き込む。commit message には変更の理由（ユーザーが述べた動機）を書く
4. 追加した監視先はまだ未巡回。`/distill-gain-latest-info watch --only <scope> --target <key>` で今すぐ回せることを伝える

### 完了報告

```
distill-gain-latest-info sources 完了。外した <n> / 追加した <m> / 直した <k>
commit: <短縮ハッシュ>
```

変更が無ければ「変更なし」とだけ報告する。

## ダイジェストの構造（Obsidian）

出力は `情報収集/YYYY-MM-DD.md` の 1 ファイルに一本化する。Obsidian の callout・表・Mermaid を活用し、以下の構造で書く。

**全 scope 共通の深さ原則:** 「何が起きたか（事実）」ではなく **「何がどう変わったか + なぜ重要か + 自分の環境でどう変わるか」** を主役にする。リリースノートやニュース見出しをそのまま訳しただけの項目は不可。

````markdown
---
date: YYYY-MM-DD
type: gain-digest
tags: [情報収集, tech-radar]
scopes: [peers, github, services, engineers, news]
---
# 情報収集 YYYY-MM-DD

> [!abstract] 今回の3行
> - 最重要トピックを3行以内で（読者が本文を読むかを決める材料）

## サマリー

| scope | 件数 | 最注目 | 次の一手 |
|---|---|---|---|
| GitHub | n | <item> | 試す/様子見/関係なし |

## GitHub

### owner/repo — <テーマ>

**何が変わったか**（4〜8文。差分を前後対比で書く）

**自分の環境で何が変わるか**: 実 grep/find/ls に基づく判定。該当ファイル名まで書く。

> [!tip] 次の一手: 試す
> 理由を2〜3文で。

**source**: <URL>

## サービス更新
## エンジニア発信（blog / SNS・信頼度低）
## ニュース
## peers（dotfiles 採用ワークフロー）

（見出しごとの構成は GitHub と同じ。処理したが選ばれなかった候補は件名のみ 1 行で列挙する）

## 改善提案

`~/.local/state/gain/sources.tsv` の `runs`/`findings` を根拠に挙げる。
- **実績の無い監視先**: 一定回数処理して findings が積み上がらない監視先（除外候補）
- **繰り返し現れた話題**: 直近数回のダイジェストを読み返し、複数回言及したテーマ（追加候補）
- **掃除した監視先**: Step 1 の `gain-state prune` が消した `<scope>\t<key>`（あれば 1 行）

このスキル自身は適用しない。承認は呼び出し元が行う。
````

**callout の使い分け（次の一手と対応させる）:**

| 次の一手 | callout |
|---|---|
| 試す | `> [!tip]` |
| 様子見 | `> [!warning]` |
| 関係なし | `> [!quote]` |
| セキュリティ・障害系の注意情報 | `> [!danger]` |

**深さの基準:** 選ばれた 3〜5 件は 1 件あたり 10〜20 行を目安に、「何が変わったか」は前提概念から書く（CLAUDE.md 技術メモと同じ教育深度）。比較対象が3つ以上あるときは表を必須とする。Mermaid 図は構造・フローの理解を速めるときだけ使い、装飾目的では使わない。

- vault の commit/push はしない（`/eod` に委譲）

## エラーハンドリング

| 状況 | 対応 |
|---|---|
| `sources.yaml` が見つからない | 実行せず「sources.yaml が見つかりません: `<path>`」とパスを添えて報告し終了（`gain-state: no sources file at ...` が出る）。YAML の構文を疑わせない |
| `sources.yaml` が parse 不能 | 実行せず「sources.yaml の YAML が不正です（`key: []` と実体リストの共存に注意）」と該当箇所を添えて報告し終了 |
| scope のソース定義が空（`[]`） | 「<scope>: ソース未登録のためスキップ」と 1 行報告して次 scope へ（エラー扱いしない） |
| `gh` 未認証 | 「`gh auth login` を実行してください」と表示し該当 scope 終了 |
| リポジトリ 404 | 1 行警告で skip、他は続行（`gain-state record` は呼ばない） |
| RSS/changelog 取得失敗 | 当該ソースを skip、他は続行（`gain-state record` は呼ばない。取得自体の失敗は次回そのまま再訪する。一時的な回線断で週次の枠を消費しない） |
| SNS 取得ゼロ | 正常扱い（「該当なし」。取得は成功しているため `gain-state record` は findings=0 で呼ぶ） |
| 全ソース取得失敗 | 「データを取得できませんでした」と報告し終了（ファイルは作らない） |
| `gain-state prune` が失敗 | 1 行報告して `due` へ進む。掃除は実績の見栄えの問題で、収集は止めない |
| deep-research 未利用可（research モード） | Web を内蔵 WebSearch で縮退実行し明示 |

**`gain-state record` を呼ぶかどうかの基準は「取得に成功したか」であり「findings があったか」ではない。** 取得自体が失敗した監視先（404 / RSS・changelog 取得失敗など）は `record` を呼ばず、次回実行時にそのまま対象に残す。取得に成功して収穫が 0 件だった場合（SNS 取得ゼロ等）は `record` を findings=0 で呼び、来週まで再訪しない。

## Red Flags（やってはいけないこと）

- watch の収集・ダイジェスト生成中にユーザーへ確認を求める（対話が要る事項は `## 改善提案` に書いて返すだけに留める）
- 教育解説で専門用語を読み手任せにする / 「自分の環境で何が変わるか」を省略する
- diff 判定を LLM 推測で行う（必ず grep/find/ls）
- サブエージェントの生出力を統合せずダイジェストへ転送する
- SNS を「信頼度低」ラベルなしで他ソースと同列に出す
- ユーザー承認なしに `sources.yaml` へアドホック対象を追記する
- `## 改善提案` の内容をこのスキル自身が `sources.yaml` に適用する（承認は呼び出し元が行う）
- distill-gain-latest-info が vault を自動 commit する（`/eod` に委譲）
- sources モードで、表を出さずに編集に入る（外す判断の材料が無い）
- 転送元の URL を `sources.yaml` に書く（着地先を書く）
- 存在を確認せずに repo や handle を足す
- 日付つきエントリを持たないページを changelog として扱う（`watch: diff` を使う）
- `sources.yaml` 以外の変更を巻き込んで commit する
