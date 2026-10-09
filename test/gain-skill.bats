#!/usr/bin/env bats
# 情報収集スキルの仕様。
#
# 2 か月間 1 件も出力しなかった対象なので、検査は「書いてあること」ではなく
# 「壊れる書き方が残っていないこと」に当てる。説明文にも語が出るため、
# 検査はコメントを除いた本文に当てる。

load "helpers/common"

setup() {
  SK="$REPO_DIR/claude/skills/distill-gain-latest-info/SKILL.md"
}

@test "dry-run が残っていない" {
  # 抑止すべき対話をサブエージェント側に置かない設計にしたので、
  # このフラグは存在自体が設計と矛盾する。
  n=$(grep -c -- '--dry-run' "$SK") || n=0
  [ "$n" -eq 0 ]
}

@test "廃止した出力先への言及が残っていない" {
  n=$(grep -c 'peer-watch' "$SK") || n=0
  [ "$n" -eq 0 ]
  m=$(grep -cE '情報収集/(watch|research)/' "$SK") || m=0
  [ "$m" -eq 0 ]
}

@test "出力先が正本の 情報収集 の 1 ファイルである" {
  # 正本は Obsidian vault から distill-vault へ移した。パスを固定して
  # おかないと、移管のたびに書き先が黙って古い場所へ戻る。
  grep -qF 'distill-vault/情報収集/' "$SK"
  n=$(grep -c 'index\.md' "$SK") || n=0
  [ "$n" -eq 0 ]
}

@test "週内クールダウンを gain-state に委ねている" {
  grep -qF 'gain-state due' "$SK"
  grep -qF 'gain-state record' "$SK"
}

@test "ダイジェストの件数と深さが指定されている" {
  grep -qE '1〜3 ?件' "$SK"
  grep -qF '業務のどこに効くか' "$SK"
  n=$(grep -cE '3〜5 ?件を深掘り' "$SK") || n=0
  [ "$n" -eq 0 ]
}

@test "改善提案は提示までで、適用しないと明記されている" {
  grep -qF '## 改善提案' "$SK"
  grep -qF 'このスキル自身は適用しない' "$SK"
}

@test "sources.yaml を読む記述が残っている" {
  grep -qF 'sources.yaml' "$SK"
}

# --- eod 側の配線 ---
#
# 「必ず実行する」と「承認を取る」は、サブエージェントに丸投げしたままでは
# 両立しない。収集はサブエージェント、承認は eod 本体、という分離を検査する。

@test "eod のスキップ選択肢から情報収集が消えている" {
  f="$REPO_DIR/claude/skills/eod/SKILL.md"
  # Step 0 の選択肢は「`名前` — 説明をスキップ」の形。宣言の形に当てる。
  n=$(grep -cE '^ +[0-9]+\. `distill-gain-latest-info' "$f") || n=0
  [ "$n" -eq 0 ]
}

@test "eod が dry-run を渡していない" {
  f="$REPO_DIR/claude/skills/eod/SKILL.md"
  n=$(grep -c -- '--dry-run' "$f") || n=0
  [ "$n" -eq 0 ]
}

@test "eod に改善提案の承認ステップがある" {
  f="$REPO_DIR/claude/skills/eod/SKILL.md"
  grep -qF '### Step 1.5' "$f"
  grep -qF '## 改善提案' "$f"
  grep -qF 'AskUserQuestion' "$f"
}

@test "eod が gain をサブエージェントに投げる記述は残っている" {
  f="$REPO_DIR/claude/skills/eod/SKILL.md"
  grep -qF 'distill-gain-latest-info' "$f"
}

# --- CWD 非依存 ---
#
# グローバルスキルはどのリポジトリからでも起動される。相対パスで書かれた
# コマンドは dotfiles を CWD にしたときしか解決せず、他リポジトリでは
# exit 127 で Step 1 が丸ごと落ちる。パスは CWD に依存させない。

@test "gain-state の呼び出しが絶対パスで書かれている" {
  n=$(grep -oE '[^`[:space:]]*bin/gain-state' "$SK" | grep -cvF '$HOME/dotfiles/bin/gain-state') || n=0
  [ "$n" -eq 0 ]
  grep -qF '$HOME/dotfiles/bin/gain-state due' "$SK"
}

@test "SKILL.md の sources.yaml 参照が絶対パスである" {
  n=$(grep -oE "[^\`[:space:]]*claude/skills/distill-gain-latest-info/sources\.yaml" "$SK" \
      | grep -cvF '$HOME/dotfiles/claude/skills/') || n=0
  [ "$n" -eq 0 ]
}

@test "eod の sources.yaml 反映先が絶対パスである" {
  f="$REPO_DIR/claude/skills/eod/SKILL.md"
  n=$(grep -oE "[^\`[:space:]]*claude/skills/distill-gain-latest-info/sources\.yaml" "$f" \
      | grep -cvF '$HOME/dotfiles/claude/skills/') || n=0
  [ "$n" -eq 0 ]
}

# --- 窓の整合 ---

@test "既出照合の窓が収集窓と一致している" {
  # purge がダイジェストを 7 日で消す。照合に 14 日分を求めても残っていない。
  grep -qF '直近 7 日分' "$SK"
  grep -qF 'lookback window は 7 日固定' "$SK"
  n=$(grep -c '直近 14 日分' "$SK") || n=0
  [ "$n" -eq 0 ]
}

@test "外した監視先の掃除が watch の先頭に入っている" {
  # `gain-state prune` は手順書に 4 箇所出る。素の grep は他の 3 箇所に
  # ヒットするので、watch Step 1 のこの 1 行が消えても気付けない。
  grep -qF 'まず `$HOME/dotfiles/bin/gain-state prune' "$SK"
}

@test "due の終了ステータスを見る手順になっている" {
  # 同じ文言が sources モードにもある（`list` の終了ステータスを…）。素の
  # grep はそちらに当たるので、watch Step 1 の側が消えても気付けない。
  # 行頭一致で、修飾の付かないこちらだけを見る。
  grep -qE '^\*\*終了ステータスを先に見る' "$SK"
  grep -qF '「確認済み」とは報告しない' "$SK"
}

@test "sources.yaml 不在のエラー行がある" {
  # 不在と parse 不能を 1 行にまとめると、ファイルが消えているのに YAML 構文を
  # 疑わせる報告になり、復旧が遅れる。
  grep -qF 'sources.yaml が見つかりません' "$SK"
}

@test "取得失敗の再訪が「来週」ではなく次回実行時になっている" {
  # record を呼ばなければ、同じ週の再実行でも due に残り続ける。「来週」と書くと
  # sources.yaml を直しても今週分は諦める、という読みを誘発する。
  grep -qF '同じ週のうちに全件そのまま対象に残る' "$SK"
  n=$(grep -cE '来週も due のまま|来週そのまま再訪' "$SK") || n=0
  [ "$n" -eq 0 ]
}

@test "record の終了ステータスを見る手順になっている" {
  # ロック導入で exit 75（古い lock で 30 秒タイムアウト）が現実的になった。
  # 見逃すと、ダイジェストは書けたのに実績だけ落ち、次回に同じ内容を再掲する。
  grep -qF '`record` の終了ステータスも見る' "$SK"
  grep -qF 'ロックを取れなかった' "$SK"
}

# --- sources モード（監視先の編集） ---
#
# 監視先を手で yaml を開かずに見直す経路。表 → 決める → 検証 → 差分、の順を
# 飛ばすと、材料無しの判断・壊れた URL・巻き込み commit のどれかが起きる。

@test "sources モードが起動に載っている" {
  grep -qF 'distill-gain-latest-info sources' "$SK"
  grep -qF '| sources]' "$SK"
}

@test "sources は表を gain-state list から作る" {
  # 結合を LLM に毎回やらせると列や件数が揺れる。決定的な出力を表にする。
  grep -qF 'gain-state list' "$SK"
  grep -qF '巡回 1 以上で収穫 0' "$SK"
}

@test "sources は改善提案を表と同じ画面で見せる" {
  grep -qF '未反映の改善提案' "$SK"
}

@test "sources は URL の着地先を書く規則を持つ" {
  grep -qF 'url_effective' "$SK"
  grep -qF '着地先' "$SK"
}

@test "sources は repo の存在確認をする" {
  grep -qF 'gh api /repos/' "$SK"
}

@test "sources は sources.yaml だけを commit する" {
  grep -qF '`sources.yaml` だけを stage' "$SK"
}

@test "sources は外した監視先の実績を prune で消す" {
  n=$(grep -c 'gain-state prune' "$SK") || n=0
  [ "$n" -ge 2 ]
}

@test "対話メニューに監視先の編集がある" {
  grep -qF '4. 監視先を編集する' "$SK"
}

# --- 形の合わない監視先 ---
#
# services の取得は「日付つきエントリの抽出」を前提にしている。docs のような
# 文書には抽出するエントリが無く、収穫 0 で記録される。形の不一致が実績の
# 低さとして積み上がり、除外候補の判定を狂わせる。

@test "services に置けるページの形が決まっている" {
  grep -qF '日付つきエントリを持つページだけ' "$SK"
  grep -qF '日付つきエントリを持たないページを `services` に足す' "$SK"
}

# --- sources モードの穴 ---

@test "sources は list の終了ステータスを見る" {
  grep -qF 'list` の終了ステータス' "$SK"
}

@test "sources の書き込み検証が list を指している" {
  # due は「今週まだ見ていない監視先」しか出さないので、外した監視先は
  # もともと 0 行側にいる。削除のみの編集では行数が動かず、検証にならない。
  grep -qF 'gain-state list <path>` の出力に、意図した増減' "$SK"
  grep -qF '`due` では確かめられない' "$SK"
}

@test "sources は改善提案の反映済みを機械的に判定する" {
  # 手で推論すると、ダイジェストが増えるほど重く、間違いやすくなる。
  grep -qF '反映済みかどうかは `gain-state list` の出力と突き合わせて判定する' "$SK"
}

@test "peers の説明が表に出ない旨の記述が残っていない" {
  # note をフィールドにしたので、この回避策の説明は嘘になった。
  n=$(grep -c '行末コメントにあり' "$SK") || n=0
  [ "$n" -eq 0 ]
}

@test "採点は gain-score を絶対パスで呼ぶ" {
  grep -qF '$HOME/dotfiles/bin/gain-score rate' "$SK"
  grep -qF '$HOME/dotfiles/bin/gain-score log' "$SK"
  n=$(grep -oE '[^`[:space:]]*bin/gain-score' "$SK" | grep -cvF '$HOME/dotfiles/bin/gain-score') || n=0
  [ "$n" -eq 0 ]
}

@test "採点の終了ステータスごとの扱いがある" {
  grep -qF 'Jev 未設定（採点なし）' "$SK"
  grep -qF 'Jev のキーが無効' "$SK"
}

@test "深掘りは Jev の点数を見る前に選ぶ" {
  # 点数を見てから選ぶと、Claude の選び方と Jev の点数の比較が成り立たない。
  grep -qF '点数を見る前' "$SK"
  pick=$(grep -nF '**1〜3 件**を深掘りに選ぶ' "$SK" | head -1 | cut -d: -f1)
  rate=$(grep -nF '$HOME/dotfiles/bin/gain-score rate' "$SK" | head -1 | cut -d: -f1)
  logl=$(grep -nF '$HOME/dotfiles/bin/gain-score log' "$SK" | head -1 | cut -d: -f1)
  [ -n "$pick" ]
  [ "$pick" -lt "$rate" ]
  [ "$rate" -lt "$logl" ]
}

@test "採点のその他の失敗と候補 0 件の扱いがある" {
  n=$(grep -cF 'Jev 採点失敗（exit <code>）' "$SK") || n=0
  [ "$n" -ge 2 ]
  grep -qF '| `gain-score rate` が exit 0 以外 |' "$SK"
  n=$(grep -cF 'exit 3・4' "$SK") || n=0
  [ "$n" -eq 0 ]
  grep -qF '候補が 0 件なら `rate` を呼ばず' "$SK"
}

@test "Jev との一致の上位 N 件が定義されている" {
  grep -qF '`error` の行を除き `score` の高い順' "$SK"
  grep -qF '<N> は深掘りに選んだ件数' "$SK"
}

@test "採点は選び方を変えず、失敗で watch を止めない" {
  grep -qF '採点は選び方を変えない' "$SK"
  grep -qF '`gain-score` の失敗で watch を止める' "$SK"
}

@test "流れの層の節があり、採点しない" {
  for h in '## 今日の流れ' '## 話題の技術' '## キャリア' '## 定点'; do
    grep -qF "$h" "$SK"
  done
  grep -qF '流れの層の候補を `gain-score` に渡す' "$SK"
  n=$(grep -c '## 動向' "$SK") || n=0
  [ "$n" -eq 0 ]
}

@test "流れの層は gain-stream を絶対パスで呼び、budget を先に見る" {
  grep -qF '$HOME/dotfiles/bin/gain-stream topics' "$SK"
  grep -qF '$HOME/dotfiles/bin/gain-stream discover' "$SK"
  b=$(grep -nF '$HOME/dotfiles/bin/gain-stream budget' "$SK" | head -1 | cut -d: -f1)
  t=$(grep -nF '$HOME/dotfiles/bin/gain-stream topics' "$SK" | head -1 | cut -d: -f1)
  [ -n "$b" ]
  [ "$b" -lt "$t" ]
}

@test "budget は超過（exit 3）と sources.yaml の誤り（exit 1）を分けて扱う" {
  grep -F 'gain-stream budget' "$SK" | grep -qF 'exit 3'
  grep -F 'gain-stream budget' "$SK" | grep -qF 'exit 1'
  n=$(grep -cF '`gain-stream budget` が非 0' "$SK") || n=0
  [ "$n" -eq 0 ]
}

@test "取得できなかったものは出どころと query で書く" {
  grep -qF '`<source> <query>（<error>）`' "$SK"
  grep -qF '取得できなかった: <source> <query>（<error>）' "$SK"
  n=$(grep -cF '<source>（<error>）' "$SK") || n=0
  [ "$n" -eq 0 ]
}

@test "流れは出どころ 2 つ以上の話題だけ" {
  grep -qF '2 つ以上の出どころ' "$SK"
}

@test "news と engineers の scope が残っていない" {
  n=$(grep -cE '`(news|engineers)`' "$SK") || n=0
  [ "$n" -eq 0 ]
}

@test "毎日の部分は話題を絞り、前提から考察まで書く" {
  for h in '## 今日の要点' '#### 前提' '#### 何が起きたか' '#### なぜ今か' '#### 業務のどこに効くか' '#### 考察'; do
    grep -qF "$h" "$SK"
  done
  grep -qF '> [!abstract] 3 分で読む' "$SK"
  grep -qF '| 仕事・環境 | 何に効くか | 根拠 |' "$SK"
  grep -qF '【一次】' "$SK"
  grep -qF '【推論】' "$SK"
  run grep -cF '40 行' "$SK"
  [ "$output" = "0" ]
}

@test "行数は空行を除いて数え、合計は話題の数で決まる目安になっている" {
  # 数え方が決まっていないと、空行の多寡で同じ本文が 30 行にも 50 行にもなり、
  # 分量の決まりが検査にならない。
  grep -qF '行数は空行を除いて数える' "$SK"
  grep -qF '合計 120〜200 行は目安で、話題の数で決まる' "$SK"
}

@test "毎日の話題と深掘りの分量が決まっている" {
  grep -qF '2〜3 本、1 本 30〜50 行' "$SK"
  grep -qF '1 件あたり 30〜50 行' "$SK"
  run grep -cF '10〜20 行' "$SK"
  [ "$output" = "0" ]
}

@test "前の日に出た話題は今日の流れの 1 本として書き、学習メモの材料は行頭の ### で集める" {
  grep -qF '新しい事実が無ければ書かない' "$SK"
  grep -qF '行頭の `### `（`^### `）' "$SK"
  run grep -cF '「続報」として 1 行' "$SK"
  [ "$output" = "0" ]
}

@test "業務の照らし合わせは対象.md の 5 プロジェクトと手元の環境を根拠にする" {
  grep -qF '$HOME/develop/distill-vault/対象.md' "$SK"
  grep -qF 'プロジェクト/<名前>/概要.md' "$SK"
}

@test "選ばなかった候補は書かず、見出しには主題だけを書く" {
  run grep -cE '選ばれなかった候補|選ばなかった候補' "$SK"
  [ "$output" = "0" ]
  grep -qF '見出しには主題だけを書く' "$SK"
  grep -qF '## 深掘り' "$SK"
  run grep -cF '## 深掘り 1' "$SK"
  [ "$output" = "0" ]
}

@test "同じ週の深掘りの照合は新旧両方の見出しを読む" {
  grep -qF '`## 深掘り` の下の `###`' "$SK"
  grep -qF '`## 深掘り N: <主題>`' "$SK"
}

@test "深さ原則が自分に効く区分に限られている" {
  n=$(grep -c '全 scope 共通の深さ原則' "$SK") || n=0
  [ "$n" -eq 0 ]
  grep -qF '自分に効く区分（`services`・`github`・`peers`）の深さ原則' "$SK"
}

# --- 層ごとの失敗と期間 ---

@test "全ソース失敗の行が監視先の層を名指ししている" {
  # 層を書かないと、流れの層が取れていてもファイルを作らない読みになる。
  grep -qF '監視先の層の全ソースが失敗' "$SK"
  n=$(grep -c '| 全ソース取得失敗 |' "$SK") || n=0
  [ "$n" -eq 0 ]
}

@test "期間を 3 日に切り詰めたら window に書く" {
  n=$(grep -F 'window' "$SK" | grep -cF '3 日') || n=0
  [ "$n" -ge 1 ]
}

@test "description がエンジニア発信を謳っていない" {
  n=$(awk 'NR==1{next} /^---$/{exit} {print}' "$SK" | grep -c 'エンジニア発信') || n=0
  [ "$n" -eq 0 ]
}

# --- 学習メモ（週 1 回）と、学べる書き方 ---
#
# ダイジェストは 7 日で消える。繰り返し出た流れだけを、消えない学習メモに
# 残す。書き方の規則は distill-project に 1 か所だけ置き、ここでは場所を指す。

@test "週 1 回、繰り返し出た流れを学習メモにする手順がある" {
  grep -qF '### Step 3.5: 学習メモ（週 1 回）' "$SK"
  grep -qF '2 日以上に出た話題' "$SK"
  grep -qF '1〜2 本' "$SK"
  grep -qF '候補が無い週は 0 本' "$SK"
}

@test "学習メモの書き方は distill-project の節を指す（書き写さない）" {
  grep -qF '$HOME/dotfiles/claude/skills/distill-project/SKILL.md' "$SK"
  grep -qF '「読者像と文体」' "$SK"
  grep -qF '「読者を押し上げる仕組み」' "$SK"
  grep -qF '「精度の下限」' "$SK"
}

@test "学習メモは既存の学習メモと重ならない主題を選ぶ" {
  grep -qF '既存の学習メモ' "$SK"
}

@test "学習メモからダイジェストへリンクしない（purge が消せなくなる）" {
  grep -qF '学習メモからダイジェストへはリンクしない' "$SK"
}

@test "ダイジェストの週 1 回の部分に今週の学習メモの節がある" {
  grep -qF '## 今週の学習メモ' "$SK"
}

@test "今日の流れの各話題は「そもそも」の 1 行から始める" {
  grep -qF 'そもそも:' "$SK"
  grep -qF '学ぶ入口:' "$SK"
}

# --- AI セキュリティの監視と、月次の監視先 ---
#
# 月次でしか動かない監視先（OWASP・MITRE ATLAS・規制など）は週 1 回の巡回で
# 空振りが続く。週次の基準で外すと遅い動きを追う監視先から消えていくので、
# cadence: monthly の印と、それを尊重する sources モードの規則をセットで守る。

yaml_py() {  # yaml_py <python expression over d> — prints the result
  local py
  py="$(mise which python3 2>/dev/null || command -v python3)"
  "$py" -c "import sys, yaml; d = yaml.safe_load(open(sys.argv[1], encoding='utf-8')); print($1)" \
    "$REPO_DIR/claude/skills/distill-gain-latest-info/sources.yaml"
}

@test "sources.yaml に AI セキュリティの topic がある" {
  yaml_py "[t['name'] for t in d.get('topics') or []]" | grep -qF 'AI セキュリティ'
}

@test "AI セキュリティの topic は動向レベルで要約すると説明に書いてある" {
  yaml_py "[t.get('note','') for t in d.get('topics') or [] if t['name'] == 'AI セキュリティ']" \
    | grep -qF '動向レベル'
}

@test "cadence の値は monthly だけ" {
  n=$(yaml_py "sorted({it['cadence'] for s in ('github','services') for it in (d.get(s) or []) if isinstance(it, dict) and 'cadence' in it} - {'monthly'})" \
    | grep -c -v '^\[\]$') || n=0
  [ "$n" -eq 0 ]
}

@test "cadence は週次の監視先（github・services）にだけ付く" {
  n=$(yaml_py "[s for s, v in d.items() if s not in ('github','services') and isinstance(v, list) and any(isinstance(i, dict) and 'cadence' in i for i in v)]" \
    | grep -c -v '^\[\]$') || n=0
  [ "$n" -eq 0 ]
}

@test "月次の監視先が少なくとも 1 つある" {
  yaml_py "sum(1 for s in ('github','services') for it in (d.get(s) or []) if isinstance(it, dict) and it.get('cadence') == 'monthly')" \
    | grep -qE '^[1-9][0-9]*$'
}

@test "sources モードは月次の監視先を早く外さない" {
  grep -qF '`cadence: monthly` の行' "$SK"
  grep -qF '巡回 13 回（約 3 か月）未満で収穫 0 でも外す候補にしない' "$SK"
}

@test "gain-state list は cadence 付きの監視先も並べる" {
  y="$BATS_TEST_TMPDIR/s.yaml"
  printf 'services:\n  - name: Slow Feed\n    url: https://example.com/news\n    cadence: monthly\n' > "$y"
  run env GAIN_STATE="$BATS_TEST_TMPDIR/state.tsv" "$REPO_DIR/bin/gain-state" list "$y"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'Slow Feed'
}

@test "research モードに AI セキュリティの深掘り先がある" {
  grep -qF 'arXiv の cs.CR' "$SK"
  grep -qF 'Gray Swan Arena' "$SK"
}

@test "改善提案も月次の監視先を早く除外候補に挙げない" {
  grep -qF '`cadence: monthly` の監視先は巡回 13 回未満なら挙げない' "$SK"
}

@test "sources モードは cadence を sources.yaml から読む" {
  grep -qF '`cadence` は `list` の出力に無いので `sources.yaml` から読む' "$SK"
}

@test "OpenAI は取得できる RSS を見る（安全性の一覧ページはボット対策で 403）" {
  yaml_py "[s['url'] for s in d.get('services') or [] if s['name'].startswith('OpenAI')]" \
    | grep -qF 'openai.com/news/rss.xml'
  n=$(yaml_py "[s['url'] for s in d.get('services') or []]" | grep -cF 'safety-alignment') || n=0
  [ "$n" -eq 0 ]
}
