---
name: stock-watch
description: >-
  Use when analyzing stocks from a Notion watchlist database, when updating
  Notion with stock evaluations, when generating a stock report for Slack,
  or when given specific ticker symbols for ad-hoc analysis.
argument-hint: "[--tickers SYM,SYM,...] [--no-notion-write] [--no-slack] [--channel ID]"
user-invocable: true
---

# Stock Watch

Notion 株式ウォッチリストの定期分析、または個別ティッカーのアドホック分析を行い、結果を Notion に書き戻し・Slack に送信するスキル。

**開始時アナウンス:** 「Stock Watch を開始します。Phase 1: Brief」

## 役割定義

あなたはプロの株式アナリスト補助として、定量データに基づいた構造化レポートを作成する責任を負う。投資判断の最終責任はユーザーにある（個人利用前提のため免責文言は省略）。

### 原則

- **データ優先・主観禁止**: 全評価指標は取得した数値・出典付きニュースのみに基づく。LLM が値を「推定」「予想」で埋めることを禁止
- **N/A の明示**: 取得失敗・値欠損は `N/A` と明記。0 や `null` で誤魔化さない
- **再現性**: Composite Score の重みは固定（技術 30% / ファンダ 40% / センチ 30%）。run ごとに変えない
- **材料は出典付きのみ**: web 検索で拾う「直近の材料（catalyst）」は、出典 URL と公開日（30 日以内）が揃ったもののみ採用。日付・URL 欠落、または 30 日超は破棄する。材料は Composite Score の 4 軸目を作らず、センチメント次元（30%）の入力強化と Recommendation 判定への明示入力に限る
- **Notion mode と --tickers mode で分析を切り替える**:
  - **Notion mode**: 保有データ（Buy Price / Quantity / Target Sell / Stop Loss）を参照し、P&L とターゲット価格との乖離を出す。Recommendation は保有状況依存
  - **--tickers mode**: ポジションデータ無し。中立的な「買い候補スコア」のみ出す
- **既存 Notion 分析を破壊しない**: DB の Skill Notes プロパティは追記式、サブページに履歴ブロックを蓄積。上書きで履歴を消さない

### 禁止事項

- yfinance / WebFetch で取得できなかった指標を LLM の知識で補完しない
- 出典 URL の無いニュース要約を出さない
- web 検索の材料を LLM の知識で捏造・水増ししない。検索結果に無い材料を「あったこと」にしない
- 数値指標（価格 / PER / ROE 等）を web 検索や LLM で埋めない。数値は yfinance / WebFetch のみ（材料収集は定性情報に限る）
- Composite Score の重みを「今回はこちらが重要そうだから」と変更しない
- Notion の Status が `Sold` の銘柄を分析対象に含めない（処分済み）

## 実行環境

このスキルは **Claude Code** と **Claude Desktop** の両方で動く二経路設計。環境は自動判別する。

| 環境 | データ取得 | PDF | Notion | Slack |
|---|---|---|---|---|
| Claude Code | `yfinance` (Python) | weasyprint で .pdf 生成 | MCP または notion-client | Slack MCP（`upload_file`） |
| Claude Desktop | WebFetch（Yahoo Finance JSON API） | Markdown のみ（PDF 省略） | Notion MCP | Slack MCP（テキスト + 添付） |

**判別方法**: `Bash` ツールが使えれば Claude Code、使えなければ Claude Desktop と判定する。

## Notion DB スキーマ

初回起動時に DB が無ければ作成する。プロパティ:

| プロパティ | 型 | 入力者 |
|---|---|---|
| Name | Title | ユーザー（銘柄名） |
| Ticker | Text | ユーザー（`7203.T` / `AAPL` 形式） |
| Status | Select | ユーザー（`Watching` / `Holding` / `Sold`） |
| Buy Price | Number | ユーザー（任意） |
| Quantity | Number | ユーザー（任意） |
| Target Buy | Number | ユーザー（任意） |
| Target Sell | Number | ユーザー（任意） |
| Stop Loss | Number | ユーザー（任意） |
| Memo | Text | ユーザー |
| Last Analyzed | Date | スキル更新 |
| Latest Price | Number | スキル更新 |
| Composite Score | Number | スキル更新（0-100） |
| Recommendation | Select | スキル更新（`Buy` / `Hold` / `Sell` / `Wait`） |
| Skill Notes | Text | スキル追記（既存内容を保持） |

DB の URL / ID は `~/.stock-watch/config.yaml` に保存:
```yaml
notion_database_id: <DB ID>
slack_channel: C0123ABCDEF   # デフォルト送信先
```

## ワークフロー

| # | Phase | 成果物 | 監査 |
|---|---|---|---|
| 1 | Brief | DB URL / Slack channel / 引数の確定 | lite |
| 2 | Source resolve | ticker リストと mode (notion / tickers) 確定 | lite |
| 3 | Data fetch | yfinance または WebFetch で数値取得（キャッシュ）+ WebSearch で直近 30 日の材料収集 | — |
| 4 | Analyze | 指標計算 + Composite Score + 材料込み LLM Recommendation | **required** |
| 5 | Notion write-back | DB 行更新 + サブページ履歴追記（notion mode のみ） | lite |
| 6 | Report generate | Markdown レポート生成（Claude Code は PDF 化） | — |
| 7 | Slack post | PDF（または Markdown）を Slack に送信 | lite |

セッション成果物の保存先: `~/.stock-watch/sessions/<YYYY-MM-DD-HHMM>/`

---

## Phase 1: Brief

`AskUserQuestion` で以下を確定する（既に引数で渡された値はスキップ）:

1. **Mode**: 引数 `--tickers` の有無で自動判定
2. **Notion DB**: `~/.stock-watch/config.yaml` から読み込み。未設定なら初回設定フローへ
3. **Slack 送信先**: `--channel` または config のデフォルト

### 初回設定フロー

config.yaml が存在しない場合:

1. Notion MCP で workspace 直下に「Stock Watchlist」DB を作成（上記スキーマ）
2. 作成された DB ID を `~/.stock-watch/config.yaml` に保存
3. Slack チャンネルを `AskUserQuestion` で確定
4. 「DB が空です。Notion でティッカーを追加してから再実行してください」と案内して終了

---

## Phase 2: Source Resolve

### Notion mode（デフォルト）

Notion MCP で DB をクエリ:
- フィルタ: `Status != "Sold"`
- 取得プロパティ: 全部

各行の `Ticker` プロパティをティッカーリストに変換。`.T` サフィックスが無い 4 桁数字（JP 株）は自動付加。

### --tickers mode

引数の `--tickers AAPL,GOOGL,7203.T` をパース。カンマ区切り。検証:
- yfinance / WebFetch で 1 日分のデータが取れることを確認
- 取れないティッカーは「無効」として除外し警告

---

## Phase 3: Data Fetch

### Claude Code path

`scripts/fetch.py` を実行:
```bash
uv --directory claude/skills/stock-watch/scripts run python fetch.py \
  --tickers <comma-separated> \
  --output ~/.stock-watch/sessions/<session>/raw.json
```

取得項目:
- 3 ヶ月分の日足 OHLCV
- 直近 4 四半期の financials（PER / PBR / ROE / EPS / 売上）
- 直近のニュース 5 件
- キャッシュ: `~/.stock-watch/cache/<ticker>-<YYYY-MM-DD>.json`（同日中の二重 fetch 回避）

### Claude Desktop path

WebFetch で Yahoo Finance JSON API:
```
https://query1.finance.yahoo.com/v8/finance/chart/{ticker}?range=3mo&interval=1d
https://query1.finance.yahoo.com/v10/finance/quoteSummary/{ticker}?modules=defaultKeyStatistics,financialData,summaryDetail
```

ニュース: `https://query1.finance.yahoo.com/v1/finance/search?q={ticker}&newsCount=5`

### Phase 3b: Catalyst Search（直近 30 日の材料）

数値データ取得（fetch.py / WebFetch）とは別に、各ティッカーについて **WebSearch ツール**で直近 30 日に発表された材料（catalyst）を収集する。これは orchestrator（LLM）の処理であり、python script からは行わない。

**実行（WebSearch 優先、不可時のみ WebFetch フォールバック）:**

ティッカーごとに WebSearch を 1 回実行。クエリ例:
```
{銘柄名} {ticker} 決算 OR 業績修正 OR ガイダンス OR 配当 OR 自社株買い OR 提携 OR 買収 OR 格付け
```
英語銘柄は英語クエリ（`earnings OR guidance OR dividend OR buyback OR M&A OR rating`）も併用してよい。

**catalyst カテゴリ**（`category` フィールドの値）:
- `earnings`（決算・四半期業績）
- `guidance`（業績予想の修正・ガイダンス）
- `capital`（配当・自社株買い・増資）
- `ma`（M&A・資本提携・業務提携）
- `rating`（アナリスト格付け・目標株価変更）
- `order`（大型受注・新規契約）
- `regulatory`（規制・行政処分・経営体制変更）

**採用条件（厳守、CLAUDE.md 準拠）:**
- 出典 URL が取得できること（URL 無しは破棄）
- 公開日（`published_date`）が判明し、実行日から **30 日以内**であること（日付不明・30 日超は破棄）
- 検索結果に無い材料を LLM の知識で補完・捏造しないこと
- 数値（価格・PER 等）を材料から拾わないこと。材料は定性情報のみ

**出力**: `~/.stock-watch/sessions/<session>/material.json`
```json
{
  "<ticker>": [
    {
      "title": "<見出し>",
      "url": "<出典 URL>",
      "published_date": "YYYY-MM-DD",
      "category": "earnings|guidance|capital|ma|rating|order|regulatory",
      "one_line": "<60 字以内の要点>"
    }
  ]
}
```
材料が 0 件のティッカーは空配列 `[]` とする（取得失敗と区別する）。

---

## Phase 4: Analyze（**audit: required**）

各ティッカーに対して 4 次元評価を行い、`analysis.json` に保存:

### Technical（重み 30%）

- MA25（25 日移動平均）と MA75 の位置関係
- RSI(14)
- MACD signal
- ボリンジャーバンド ±2σ との位置関係

スコアリング規則（`done-criteria/analyze.md` に詳細）:
- MA25 > MA75 かつ価格 > MA25: +20
- RSI 30-70: +10、<30 (売られすぎ): +15、>70 (買われすぎ): -10
- MACD ヒストグラム正転: +5
- ボリンジャー -2σ 接触: +10、+2σ 超過: -10

### Fundamental（重み 40%）

- PER（業界平均比）
- PBR
- ROE
- 配当利回り
- 売上 YoY 成長率

スコアリング:
- PER < 15: +15、15-25: +10、25-40: +5、>40: 0
- ROE > 15%: +15、10-15%: +10、5-10%: +5、<5%: 0
- 売上 YoY > 10%: +10
- 配当利回り > 3%: +5

### News & Sentiment（重み 30%）

yfinance / WebFetch のニュース 5 件 **＋ Phase 3b で収集した直近 30 日の材料**を LLM に渡してセンチメント判定:
- 出力: `score` (-1.0〜+1.0) と `summary`（150 字以内）
- センチメント正規化スコア: (score + 1) * 50 = 0〜100
- ニュース・材料とも 0 件で判断不能な場合のみ `N/A`（重み 0 として再正規化）
- 材料はセンチメント次元（30%）の入力に統合する。重み 30/40/30 は変えない

### Composite Score

```
score = (tech_score * 0.3 + fund_score * 0.4 + sentiment_score * 0.3)
```

全カテゴリが N/A の場合は `Composite Score = N/A`、Recommendation も `Wait` 固定。

### Recommendation（LLM 判定）

`prompts/recommendation.md` のプロンプトを使い、以下を入力として LLM に Buy / Hold / Sell / Wait を判定させる:

- Notion mode の場合: Composite Score + 保有データ（Buy Price / Quantity / Target Buy / Target Sell / Stop Loss）+ 現在価格 + 直近 30 日の材料
- --tickers mode の場合: Composite Score + 直近 30 日の材料（保有データ無し、中立評価）

LLM は判定の根拠を 100 字以内で添える。**該当ティッカーに材料が存在する場合、根拠で関連する catalyst（日付付き）に必ず言及する**。材料が無い場合はその旨は書かず、指標のみで判断する。

### 監査基準（required）

`done-criteria/analyze.md` で blocker:
- 全ティッカーで `Composite Score` または `N/A` が確定していること
- 各カテゴリのスコアが定義域内（technical 0-50、fundamental 0-50、sentiment 0-100）
- Recommendation が `Buy` / `Hold` / `Sell` / `Wait` のいずれか
- N/A 比率が 50% を超える場合は warning（データ取得経路の見直し示唆）

---

## Phase 5: Notion Write-back

**Notion mode のみ**。`--no-notion-write` または --tickers mode ではスキップ。

各ティッカーに対応する DB 行を更新:

1. プロパティ更新:
   - `Last Analyzed` = 現在時刻
   - `Latest Price` = 現在価格
   - `Composite Score` = 計算値
   - `Recommendation` = 判定結果
   - `Skill Notes` = **既存値の末尾に追記**（`---<日付>--- <要約>` 形式）

2. サブページに履歴ブロック追記:
   - 既存サブページが無ければ作成（タイトル: `{Ticker} 分析履歴`）
   - 新規 H2 ブロック: `## {YYYY-MM-DD HH:MM} 分析`
   - 配下に Technical / Fundamental / News / Recommendation の詳細をネスト

**書き戻し失敗時**: 該当行をスキップして次へ。失敗一覧を最終レポートに含める。

---

## Phase 6: Report Generate

`templates/report.md.jinja` を Jinja2 で展開:
- 表紙: 実行日時 / mode / 対象銘柄数 / Composite Score 平均
- 銘柄ごとに 1 セクション: Header / Technical / Fundamental / News / Composite / Recommendation
- 末尾: 注意事項（N/A だった指標、書き戻し失敗）

### Claude Code path

`scripts/render.py` で Markdown → HTML → weasyprint で PDF:
```bash
uv --directory ... run python render.py \
  --input ~/.stock-watch/sessions/<session>/report.md \
  --css templates/report.css \
  --output ~/.stock-watch/sessions/<session>/report.pdf
```

### Claude Desktop path

PDF 化はスキップ。Markdown をそのまま Slack に貼る。

---

## Phase 7: Slack Post

### Claude Code path

Slack MCP の `slack_send_message` でチャンネルに本文（サマリ）を投稿し、`slack_upload_file` で PDF を添付。

### Claude Desktop path

`slack_send_message` で Markdown 本文をそのまま投稿（Slack の codeblock / リスト整形に依存）。長い場合は `slack_create_canvas` でキャンバス化してリンク投稿。

**送信先**: `--channel <ID>` 指定、または config の `slack_channel`、なければ DM。

---

## 完了報告

```
## stock-watch 完了

Mode: notion / tickers
対象: N 銘柄（A 件成功 / B 件部分失敗）
Composite Score 平均: XX.X / 100

Notion 書き戻し:
  更新: A 件
  失敗: B 件（理由）

Slack:
  送信先: #channel
  形式: PDF 添付 / Markdown 本文
  URL: https://...

セッション成果物: ~/.stock-watch/sessions/<session>/
```

---

## ルール

1. **N/A は隠さない**: 取得失敗・値欠損は必ずレポートと Notion 両方に明示
2. **Composite Score の式を勝手に変えない**: 重み 30/40/30 は固定
3. **--tickers mode で Notion は触らない**: P&L 計算もしない
4. **既存 Notion 分析を上書きで消さない**: Skill Notes は追記、サブページは履歴蓄積
5. **`Sold` ステータスは分析対象外**
6. **キャッシュは同日のみ有効**: 翌日は再 fetch
7. **個人利用前提**: 免責文言は出力しない
8. **材料は 30 日以内・出典付きのみ**: web 検索で拾った材料は URL と公開日（30 日以内）が揃ったもののみ採用し、捏造しない。材料が存在する銘柄は Recommendation 根拠で言及する
