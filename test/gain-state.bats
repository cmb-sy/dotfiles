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
