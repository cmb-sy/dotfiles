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
  grep -qE '3〜5 ?件' "$SK"
  grep -qF '自分の環境で何が変わるか' "$SK"
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
  # 収集は 14 日固定。照合が 3 日だと、週次実行では前回分（約 7 日前）が
  # 照合の外に落ち、4〜14 日前のエントリを再掲できてしまう。
  grep -qF '直近 14 日分' "$SK"
  # 照合窓だけ見ても、収集窓を縮める変更が素通りする。両方を固定する。
  grep -qF 'lookback window は 14 日固定' "$SK"
  n=$(grep -c '直近 3 日分' "$SK") || n=0
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
