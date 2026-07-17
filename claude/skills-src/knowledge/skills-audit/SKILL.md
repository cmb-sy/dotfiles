---
name: skills-audit
description: >-
  skills を棚卸しするときに使う。利用ログ集計で未使用・低使用スキルを特定し、
  全スキルペアの責務重複と、鮮度（壊れたパス・死んだ外部前提・stale URL・ハーネス新機能での簡素化機会）も
  体系スキャンして、Keep / Improve / Merge / Delete を判定。承認された提案は実行まで行う
  （削除・統合してオプション分岐化・陳腐化修正・導線/ルーティング追記の適用）。
  対象期間・件数・分析のみで止める場合は argument-hint を参照。
argument-hint: "[--window <days>] [--top <n>] [--focus <skill-name>] [--report-only]"
user-invocable: true
---

# Skills Audit — スキル棚卸し

`claude/skills` の利用実績と責務重複を監査し、「改善 / 統合 / 削除」の判断から承認つき適用までを行う棚卸しスキル。

**開始時アナウンス:** 「Skills Audit を開始します。Phase 1: Inventory」

## 目的

- 未使用スキルを感覚ではなくデータで特定する
- 使われない理由を構造的に分析する
- 責務が重複するスキルペアを利用実績と独立に検出する
- 各スキルに対して `Keep / Improve / Merge / Delete` の推奨を出す
- 承認された提案（削除・統合・改善）を実行まで完遂する

## 引数

- `--window <days>`: 利用実績の分析期間（日数）。デフォルト `30`
- `--top <n>`: 詳細分析する低使用スキル上位件数。デフォルト `10`
- `--focus <skill-name>`: 指定スキルを優先して深掘りする
- `--report-only`: 分析と提案だけで止める（Phase 6 の適用を行わない）。デフォルトは提案後に 1 件ずつ承認を取り適用まで行う

## フェーズ

### Phase 1: Inventory（スキル台帳の作成）

1. `claude/skills/**/SKILL.md` を再帰走査し、以下を抽出:
   - `name`
   - `description`
   - `argument-hint`
   - 依存（他スキル名への invoke 記述）
2. スキル一覧テーブルを作る（欠損メタも記録する）
3. パスからカテゴリを抽出して `category` 列を持たせる（例: `claude/skills/review/code-review/SKILL.md` -> `review`）

## Phase 2: Usage Collection（利用実績の収集）

期間内の transcript / chat log から以下を収集する。

- 直接利用: `/skill-name` 形式
- 間接利用: 他スキル内から invoke された痕跡
- 代替利用: 似た目的で別スキルが使われた痕跡

可能なら以下を優先して探索:
- 現在のエージェント transcript 群
- `~/.claude/projects` 配下の session transcript

各スキルごとに次を算出:

- `direct_count`
- `indirect_count`
- `last_used_at`
- `window_days`

## Phase 3: Unused Classification（未使用判定）

以下のルールで分類する:

- `never-used`: direct=0 かつ indirect=0（観測期間内）
- `dormant`: 利用履歴ありだが `window` 内は 0
- `hidden-dependency`: direct=0 だが indirect>0
- `active`: direct>0

`never-used` と `dormant` を「要分析対象」とする。

## Phase 4: Root Cause Analysis（使われない理由の分析）

各対象スキルに対し、最低 1 つ以上の根本原因を判定する。

原因カテゴリ:

1. **Discoverability不足**  
   description が曖昧、トリガー語が弱い、名前から用途が連想しにくい
2. **導線不足**  
   上位オーケストレータから呼ばれない、README/運用導線に登場しない
3. **重複**  
   他スキルと責務が重なり、より有名なスキルに吸収されている
4. **実行コスト**  
   引数や前提が多く、起動コストが高い
5. **陳腐化**  
   現在のワークフローでは役割が消滅した
6. **信頼性懸念**  
   過去ログで失敗・不安定・結果品質低い記録がある

判定時は evidence を必ず付ける:

- transcript 断片
- 比較対象スキル名
- 呼び出し経路（ある/なし）

## Phase 4.5: Duplicate Scan（責務重複の体系スキャン）

利用実績と**独立に**、全スキルの責務重複を走査する（active 同士でも重複は指摘する）。

1. Phase 1 の台帳から各スキルの「目的・対象・入出力・トリガー語」を 1 行要約に正規化する
2. 全ペアを突合し、次のいずれかに該当するペアを候補化する:
   - 目的が同種（例: どちらも「レビュー」「情報収集」「棚卸し」）で対象が重なる
   - description のトリガー語が相互に響き合い、ユーザーがどちらを呼ぶべきか迷う
   - 片方が他方のサブセット（機能包含）
3. 候補ペアごとに記録する:
   - `overlap: high | medium`（high = ユースケースの過半が重なる / medium = 一部場面で競合）
   - 重なりの具体的な記述（どの機能・どの場面が重複か）
   - 統合方向の仮説（どちらへ吸収し、吸収元の固有機能を統合先の**オプション/引数/モード**としてどう残すか）
4. スキャンは名前・description だけでなく **SKILL.md 本文の目的節・フェーズ構成まで読んで**判定する。名前の類似だけで重複と断定しない

Phase 5 の `MERGE` 判定は、利用実績起点（Phase 4 原因3）と本スキャンの両方を入力にする。

## Phase 4.6: Update Scan（鮮度・アップデート検査）

利用実績と独立に、スキル内容が**現在も正しく動く前提の上にあるか**を検査する（過去の実例: triage の Linear 登録が Linear 廃止で死んでいた / 03_skillup パスが vault 再編で陳腐化 / watch ソースの URL が stale キャッシュ化 / feature-dev がフロー導線の欠如で素通りされていた）。

**機械チェック（全スキル対象、grep/存在検証で行い LLM 推測で判定しない）:**

1. 本文中のファイルパス・ディレクトリの実在（`$HOME` 配下・vault 配下・リポジトリ内）
2. 参照している他スキル名の実在（改名・削除への追従漏れ）
3. 参照コマンド/CLI の存在（`which`）と、URL の生存（HTTP ステータス確認。ただし外部アクセスは件数を絞る）

**前提チェック（要分析対象 + active 上位 + `--focus` 対象に絞る、コスト管理のため）:**

4. 外部サービス・plugin の生存を auto memory（MEMORY.md）と突合する（例: 使用終了サービスへの登録フローが残っていないか）
5. ハーネス新機能との突合: `02_skillup/情報収集/watch/` の直近ダイジェスト（あれば）から Claude Code の新機能を読み、スキルの手順が**新機能で簡素化・置換できる**場合は改善候補として挙げる
6. フロー導線の生存: 上位オーケストレータ・CLAUDE.md のルーティングから実際に到達できるか（到達経路が存在しないスキルは「導線欠如」として IMPROVE 候補へ）

検出した陳腐化・改善機会は Phase 5 の `IMPROVE` 入力にする（壊れた前提は severity 高として優先提示）。

## Phase 5: Recommendation（改善 or 削除提案）

各スキルに 1 つの推奨アクションを割り当てる:

- `KEEP`: 現状維持（利用あり・価値明確）
- `IMPROVE`: 名前/description/引数/導線を改善
- `MERGE`: 既存スキルへ統合
- `DELETE`: 削除候補

### 判定ルール

- `DELETE` は次を全て満たす場合のみ:
  - `never-used` または長期 `dormant`
  - 間接依存なし
  - ユニークな価値が説明できない
  - 代替スキルが存在
- `DELETE(相談)` は、上記4条件を満たさなくても次を全て満たす場合に出す:
  - 2回以上連続の audit（または window の2倍以上の期間）で direct=0 かつ indirect=0
  - hidden-dependency ではない
  - 削除しても他スキルのフローが壊れない
  - ユニークな価値は「ありうる」が、実際に使われる見込みの根拠が示せない
- `IMPROVE` は次のいずれか:
  - 価値はあるが discoverability/導線が弱い
  - 入力設計を変えれば利用が増える見込みが高い
  - Phase 4.6 で陳腐化（壊れたパス・死んだ外部前提・stale URL）や新機能による簡素化機会を検出した
- `MERGE` は責務重複が高い場合

## Phase 6: Interactive Apply（承認つき適用）

`--report-only` 指定時は本フェーズをスキップして終了。

Phase 5 の推奨のうち `IMPROVE` / `MERGE` / `DELETE` を **1 件ずつ** AskUserQuestion で提示し、承認されたものだけ即時適用する。

**提示形式（1 件ごと）:** 推奨内容 + 根拠(evidence) + 適用した場合の変更ファイル一覧を先に見せ、選択肢は「適用 / スキップ / 内容を修正して適用（自由入力） / 後で」。

**`DELETE(相談)` の提示形式:** 断定せず相談ベースで出す。そのスキルの**具体的な想定用途を 2〜3 個**挙げ、「もし『<用途1>』や『<用途2>』でも使わないなら消しましょう」と問う。選択肢は「削除 / 残す（理由を1行メモ） / 後で」。「残す」が選ばれたら理由をレポートに記録し、次回 audit では理由ごと再提示して見直しを促す。

**適用内容:**

- `DELETE`: `claude/skills-src/<category>/<name>/` と symlink `claude/skills/<name>` を `git rm -r` で削除
- `MERGE`: (1) 統合先 SKILL.md に吸収元の固有機能を**オプション/引数/モードとして**追記するドラフトを提示、(2) 承認後に統合先を編集、(3) 吸収元を DELETE と同様に削除、(4) description に「旧 <name> を吸収」と 1 行残す
- `IMPROVE`: name/description/argument-hint/導線/本文のアップデート（陳腐化修正・新機能への置換を含む）の最小差分ドラフトを提示し、承認後に適用。導線改善は SKILL.md 内に限らず、上位スキルや CLAUDE.md のルーティング節への追記も対象にしてよい（その場合も変更ファイルを明示して承認を取る）

**実行ルール:**

1. 1 適用 = 1 コミット。変更ファイルを明示して `git add`（`-A` 禁止）。メッセージ例: `chore(skills): merge <src> into <dst> as --<option>`
2. 他スキルから吸収元への invoke 記述が残る場合、その参照も同コミットで統合先に書き換える（Phase 1 の依存記録を使う）
3. 適用後に `find -L claude/skills -maxdepth 2 -name SKILL.md | wc -l` と dangling symlink チェック（`find claude/skills -type l ! -exec test -e {} \; -print`）を実行し、結果を報告する
4. 全件処理後、適用サマリ（適用 n / スキップ n / 後で n、コミット一覧）を出力する

## 出力フォーマット

以下の順で出力する。

### 1) Overview

```text
Skills Audit Report
window: <days>
total_skills: <N>
active: <N>
hidden_dependency: <N>
dormant: <N>
never_used: <N>
```

### 2) 未使用・低使用スキル一覧

1 スキルにつき最大 8 行:

```text
[skill-name]  class: never-used
- usage: direct=0 indirect=0 last_used=none
- reason: Discoverability不足（description が汎用的）
- evidence: "..."
- recommendation: IMPROVE
- action:
  1) description に trigger 語を追加
  2) feature-dev の Integration 節に導線追加
```

### 3) 削除候補

```text
Delete Candidates
- <skill-name>: 理由 / 代替 / 影響
```

### 4) 適用サマリ（Phase 6 実行時のみ）

適用 / スキップ / 後で の件数とコミット一覧、および適用後の検証結果（スキル数・dangling symlink）を出す。

## 実行ルール

1. 推測で「未使用」と断定しない。必ずログ根拠を示す
2. direct/indirect を分けて報告する
3. `DELETE` は保守的に判定し、影響を明記する
4. 提案は「今すぐ編集可能な粒度」で出す
5. 出力は簡潔なプレーンテキスト中心で作る

## Red Flags

- 利用実績ゼロの根拠なしで削除提案する
- `hidden-dependency` を未使用扱いして削除提案する
- 改善案が抽象的で実編集に落ちない
- 重複先スキル名を示さず `MERGE` 提案する
- ユーザー承認なしに削除・統合を適用する（1 件ずつの承認が必須）
- 統合時に吸収元の固有機能をオプション化せず黙って捨てる
