#!/usr/bin/env bats
# 監視先ごとの週内クールダウン。
#
# 「今週見たか」を ISO 週（月曜起点）で判定する。sqlite の `weekday` 修飾子は
# 「次の N 曜へ進める。今日が N なら動かない」挙動で、素直に書くと月曜に 1 週
# ずれる。bin/voice-quota-watch がその回避策を記録している。ここは python3 の
# isocalendar() を使い、同じ罠に近寄らない。

load "helpers/common"

setup() {
  GS="$REPO_DIR/bin/gain-state"
  export GAIN_STATE="$BATS_TEST_TMPDIR/sources.tsv"
  SRC="$BATS_TEST_TMPDIR/sources.yaml"
  cat > "$SRC" << 'YAML'
github:
  - repo: owner/alpha
  - repo: owner/beta
news:
  - query: "検索語 A"
YAML
}

due() { GAIN_NOW="$1" run bash "$GS" due "$SRC"; }

@test "状態ファイルが無ければ全件が対象になる" {
  due 2026-09-07
  [ "$status" -eq 0 ]
  n=$(printf '%s' "$output" | grep -c .) || n=0
  [ "$n" -eq 3 ]
}

@test "今週すでに見た監視先は対象から外れる" {
  # 2026-09-07 は月曜。同じ週の 2026-09-09 に見た記録を置く
  printf 'github\towner/alpha\t2026-09-09\t1\t0\n' > "$GAIN_STATE"
  due 2026-09-11
  n=$(printf '%s' "$output" | grep -cF 'owner/alpha') || n=0
  [ "$n" -eq 0 ]
  m=$(printf '%s' "$output" | grep -cF 'owner/beta') || m=0
  [ "$m" -eq 1 ]
}

@test "週をまたぐと対象に戻る" {
  printf 'github\towner/alpha\t2026-09-09\t1\t0\n' > "$GAIN_STATE"
  due 2026-09-14          # 翌週の月曜
  n=$(printf '%s' "$output" | grep -cF 'owner/alpha') || n=0
  [ "$n" -eq 1 ]
}

@test "日曜と翌月曜が別の週に落ちる（境界）" {
  printf 'news\t検索語 A\t2026-09-13\t1\t0\n' > "$GAIN_STATE"   # 日曜
  due 2026-09-13
  a=$(printf '%s' "$output" | grep -cF '検索語 A') || a=0
  [ "$a" -eq 0 ]
  due 2026-09-14                                                # 翌日の月曜
  b=$(printf '%s' "$output" | grep -cF '検索語 A') || b=0
  [ "$b" -eq 1 ]
}

@test "全件が今週分なら何も出さず正常終了する" {
  {
    printf 'github\towner/alpha\t2026-09-07\t1\t0\n'
    printf 'github\towner/beta\t2026-09-07\t1\t0\n'
    printf 'news\t検索語 A\t2026-09-07\t1\t0\n'
  } > "$GAIN_STATE"
  due 2026-09-08
  [ "$status" -eq 0 ]
  n=$(printf '%s' "$output" | grep -c .) || n=0
  [ "$n" -eq 0 ]
}

@test "due は sources.yaml が無ければ失敗する" {
  # パーサを list_sources へ切り出した際、抜け方を exit から return へ変えた。
  # due はそれをパイプで受けるので、pipefail 越しに失敗が伝わることを固定する。
  run bash "$GS" due "$BATS_TEST_TMPDIR/does-not-exist.yaml"
  [ "$status" -ne 0 ]
}

@test "due の失敗伝播が pipefail に依存していない" {
  # 取得失敗と「今週は対象ゼロ」は、どちらも標準出力が空になる。区別が
  # シェル設定 1 行（set -o pipefail）に乗っていると、それが外れた瞬間に
  # 取得失敗が「確認済み」として黙って 1 週間飛ぶ。複製で固定する。
  sed 's/^set -uo pipefail$/set -u/' "$GS" > "$BATS_TEST_TMPDIR/nopipefail"
  run bash "$BATS_TEST_TMPDIR/nopipefail" due "$BATS_TEST_TMPDIR/does-not-exist.yaml"
  [ "$status" -ne 0 ]
}

@test "壊れた行があっても他の監視先は処理される" {
  printf 'これは壊れた行\n' > "$GAIN_STATE"
  printf 'github\towner/alpha\t2026-09-09\t1\t0\n' >> "$GAIN_STATE"
  due 2026-09-11
  [ "$status" -eq 0 ]
  n=$(printf '%s' "$output" | grep -cF 'owner/alpha') || n=0
  [ "$n" -eq 0 ]
}

# --- record: 実績の記録 ---
#
# 「今週見たか」だけでなく「見て何か拾えたか」を残す。改善提案は
# この件数から「実績の無い監視先」を挙げるため、記録が無いと提案が作れない。

rec() { GAIN_NOW="$1" run bash "$GS" record "$2" "$3" "$4"; }
row() { awk -F'\t' -v s="$1" -v k="$2" '$1 == s && $2 == k { print $3"|"$4"|"$5; exit }' "$GAIN_STATE"; }

@test "record は行が無ければ作る" {
  rec 2026-09-07 github owner/alpha 2
  [ "$status" -eq 0 ]
  [ "$(row github owner/alpha)" = "2026-09-07|1|2" ]
}

@test "record は既存行の日付を更新し件数を足す" {
  printf 'github\towner/alpha\t2026-09-01\t3\t5\n' > "$GAIN_STATE"
  rec 2026-09-07 github owner/alpha 2
  [ "$(row github owner/alpha)" = "2026-09-07|4|7" ]
}

@test "record は他の行を壊さない" {
  {
    printf 'github\towner/alpha\t2026-09-01\t3\t5\n'
    printf 'news\t検索語 A\t2026-09-02\t9\t1\n'
  } > "$GAIN_STATE"
  rec 2026-09-07 github owner/alpha 0
  [ "$(row news '検索語 A')" = "2026-09-02|9|1" ]
  n=$(grep -c . "$GAIN_STATE") || n=0
  [ "$n" -eq 2 ]
}

@test "record した監視先はその週 due に出なくなる" {
  rec 2026-09-07 github owner/alpha 1
  due 2026-09-09
  n=$(printf '%s' "$output" | grep -cF 'owner/alpha') || n=0
  [ "$n" -eq 0 ]
}

@test "findings が数値でなければ拒否する" {
  rec 2026-09-07 github owner/alpha あ
  [ "$status" -ne 0 ]
}

@test "last_checked が不正な日付なら安全側（対象に含める）へ倒れる" {
  # 「今週見た」と誤認して飛ばすより、余分に見に行くほうが害が小さい。
  printf 'github\towner/alpha\tNOT-A-DATE\t1\t0\n' > "$GAIN_STATE"
  due 2026-09-11
  [ "$status" -eq 0 ]
  n=$(printf '%s' "$output" | grep -cF 'owner/alpha') || n=0
  [ "$n" -eq 1 ]
}

# --- prune: 監視先から外した対象の掃除 ---
#
# sources.yaml から監視先を消しても状態ファイルには行が残る。残った行は
# 二度と更新されないまま runs/findings を持ち続け、「実績の無い監視先」を
# 挙げる改善提案の根拠を汚す。外した対象は状態からも消す。

prune() { run bash "$GS" prune "$SRC"; }

@test "prune は sources.yaml に無い行を消す" {
  {
    printf 'github\towner/alpha\t2026-09-07\t1\t2\n'
    printf 'peers\tgone-handle\t2026-09-07\t3\t0\n'
  } > "$GAIN_STATE"
  prune
  [ "$status" -eq 0 ]
  n=$(grep -cF 'gone-handle' "$GAIN_STATE") || n=0
  [ "$n" -eq 0 ]
}

@test "prune は sources.yaml にある行を実績ごと残す" {
  printf 'github\towner/alpha\t2026-09-07\t3\t5\n' > "$GAIN_STATE"
  prune
  # status を見ないと、prune を丸ごと消しても usage の exit 64 で素通りする。
  [ "$status" -eq 0 ]
  [ "$(row github owner/alpha)" = "2026-09-07|3|5" ]
}

@test "prune は消した対象を報告する" {
  printf 'peers\tgone-handle\t2026-09-07\t3\t0\n' > "$GAIN_STATE"
  prune
  n=$(printf '%s' "$output" | grep -cF 'gone-handle') || n=0
  [ "$n" -eq 1 ]
}

@test "prune は scope 違いの同名キーを消さずに見分ける" {
  # engineers の mizchi を残したまま peers の mizchi だけ外す、が実際に起きた。
  cat > "$SRC" << 'YAML'
github:
  - repo: owner/alpha
news:
  - query: "owner/alpha"
YAML
  {
    printf 'github\towner/alpha\t2026-09-07\t1\t1\n'
    printf 'peers\towner/alpha\t2026-09-07\t1\t1\n'
  } > "$GAIN_STATE"
  prune
  [ -n "$(row github owner/alpha)" ]
  [ -z "$(row peers owner/alpha)" ]
}

@test "prune は状態ファイルが無ければ何もせず正常終了する" {
  rm -f "$GAIN_STATE"
  prune
  [ "$status" -eq 0 ]
}

@test "prune は壊れた行を落とす" {
  printf 'これは壊れた行\n' > "$GAIN_STATE"
  printf 'github\towner/alpha\t2026-09-07\t1\t0\n' >> "$GAIN_STATE"
  prune
  [ "$status" -eq 0 ]
  n=$(grep -c . "$GAIN_STATE") || n=0
  [ "$n" -eq 1 ]
}

@test "prune は監視先が 1 件も取れないとき状態を消さずに拒否する" {
  # yaml を取り違えて空ファイルを渡したとき、全実績が消えるのは割に合わない。
  printf 'github:\n  []\n' > "$SRC"
  printf 'github\towner/alpha\t2026-09-07\t9\t9\n' > "$GAIN_STATE"
  prune
  [ "$status" -ne 0 ]
  # 拒否の理由まで見る。見ないと usage の exit 64 と区別が付かない。
  [[ "$output" == *"refusing to prune"* ]]
  [ "$(row github owner/alpha)" = "2026-09-07|9|9" ]
}

@test "prune は sources.yaml が無ければ状態を消さずに失敗する" {
  printf 'github\towner/alpha\t2026-09-07\t9\t9\n' > "$GAIN_STATE"
  run bash "$GS" prune "$BATS_TEST_TMPDIR/does-not-exist.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no sources file at"* ]]
  [ "$(row github owner/alpha)" = "2026-09-07|9|9" ]
}

# --- 並列書き込み ---
#
# record と prune はファイル全体を書き直すので、同時に走ると互いの結果を
# 踏む。両方が古い状態を読み、後から mv したほうが勝つ。SKILL.md は scope 内を
# 並列 dispatch する設計で監視先ごとに record を呼ぶため、これは稀な事故では
# なく既定の経路。record は exit 0 を返しながら書き込みが消えるので、
# 呼び出し側は失敗に気付けない。

@test "並列 record が全件反映される" {
  : > "$GAIN_STATE"
  for i in 1 2 3 4 5 6 7 8 9 10; do
    GAIN_NOW=2026-09-07 bash "$GS" record news "key$i" 1 &
  done
  wait
  n=$(grep -c . "$GAIN_STATE") || n=0
  [ "$n" -eq 10 ]
}

@test "並列 record が exit 0 を返したなら実際に書けている" {
  : > "$GAIN_STATE"
  d="$BATS_TEST_TMPDIR/rc"; mkdir -p "$d"
  for i in 1 2 3 4 5 6 7 8; do
    ( GAIN_NOW=2026-09-07 bash "$GS" record news "k$i" 1; printf '%s' "$?" > "$d/$i" ) &
  done
  wait
  ok=0
  for f in "$d"/*; do [ "$(cat "$f")" = "0" ] && ok=$((ok + 1)); done
  rows=$(grep -c . "$GAIN_STATE") || rows=0
  [ "$ok" -eq 8 ]
  [ "$rows" -eq "$ok" ]
}

@test "record と prune が同時に走っても record の書き込みが消えない" {
  # 1 回勝負だと、ロックが無くても順番次第で通る。5 回繰り返して運を潰す。
  for _ in 1 2 3 4 5; do
    {
      printf 'github\towner/alpha\t2026-09-01\t1\t1\n'
      printf 'peers\tgone-handle\t2026-09-01\t1\t0\n'
    } > "$GAIN_STATE"
    bash "$GS" prune "$SRC" > /dev/null &
    GAIN_NOW=2026-09-07 bash "$GS" record news '検索語 A' 7 &
    wait
    [ "$(row news '検索語 A')" = "2026-09-07|1|7" ]
    [ -z "$(row peers gone-handle)" ]
  done
}

@test "書き込みはロックも tmp も残さない" {
  GAIN_NOW=2026-09-07 run bash "$GS" record github owner/alpha 1
  [ "$status" -eq 0 ]
  [ ! -e "$GAIN_STATE.tmp" ]
  [ ! -e "$GAIN_STATE.lock" ]
}

@test "prune は失敗しても tmp を残さない" {
  printf 'github\towner/alpha\t2026-09-07\t1\t0\n' > "$GAIN_STATE"
  chmod 000 "$GAIN_STATE"
  prune
  chmod 644 "$GAIN_STATE"
  [ ! -e "$GAIN_STATE.tmp" ]
  [ ! -e "$GAIN_STATE.lock" ]
}
