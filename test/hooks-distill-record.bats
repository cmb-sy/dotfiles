#!/usr/bin/env bats
# claude/hooks/distill-record.sh のテスト。
#
# このフックはセッションが閉じるたびに走り、条件を満たしたときだけ LLM を
# 起動する。判定が緩いと薄い記録が量産され、厳しいと何も残らない。
# 判定の境界をここで固定する。

load "helpers/common"

SCRIPT="${BATS_TEST_DIRNAME}/../claude/hooks/distill-record.sh"
EXTRACT="${BATS_TEST_DIRNAME}/../claude/hooks/distill-transcript.py"

setup() {
  make_tmpdir
  GIT_REPO="$(make_tmp_git_repo)"
  TX="$TEST_TMPDIR/transcript.jsonl"
  # 編集 3 件ぶんのツール使用と、会話 1 往復を持つ transcript を作る。
  {
    printf '%s\n' '{"type":"user","message":{"content":"直してください"}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"直しました"}]}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit"}]}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write"}]}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit"}]}}'
  } > "$TX"
  HOME_BAK="$HOME"
}

teardown() {
  HOME="$HOME_BAK"
  rm -rf "$TEST_TMPDIR" "$GIT_REPO"
}

# フックを走らせる。HOME を差し替えて、実際の vault とログに触らせない。
run_hook() {
  local sid="$1" cwd="$2" tx="$3"
  printf '{"session_id":"%s","cwd":"%s","transcript_path":"%s"}' "$sid" "$cwd" "$tx" \
    | HOME="$TEST_TMPDIR/home" DISTILL_RECORD_DRY_RUN=1 bash "$SCRIPT" 2>&1
}

@test "distill-record: git リポジトリの外では記録しない" {
  mkdir -p "$TEST_TMPDIR/home" "$TEST_TMPDIR/plain"
  run_hook "s1" "$TEST_TMPDIR/plain" "$TX" >/dev/null
  # 肯定の検査はパイプで行う。中間行の [[ ]] は bash 3.2 で素通りする。
  grep -qF "git リポジトリ外" "$TEST_TMPDIR/home/.distill/logs/record.log"
}

@test "distill-record: 編集が下限に届かないセッションは記録しない" {
  mkdir -p "$TEST_TMPDIR/home"
  printf '{"session_id":"s2","cwd":"%s","transcript_path":"%s"}' "$GIT_REPO" "$TX" \
    | HOME="$TEST_TMPDIR/home" DISTILL_RECORD_MIN_EDITS=99 \
      DISTILL_RECORD_DRY_RUN=1 bash "$SCRIPT" >/dev/null 2>&1
  grep -qF "記録しない" "$TEST_TMPDIR/home/.distill/logs/record.log"
}

@test "distill-record: transcript が無ければ何もしない" {
  mkdir -p "$TEST_TMPDIR/home"
  run_hook "s3" "$GIT_REPO" "$TEST_TMPDIR/nope.jsonl" >/dev/null
  grep -qF "transcript が無い" "$TEST_TMPDIR/home/.distill/logs/record.log"
}

@test "distill-record: 条件を満たすと書き込みまで進む" {
  mkdir -p "$TEST_TMPDIR/home"
  run_hook "s4" "$GIT_REPO" "$TX" >/dev/null
  grep -qF "記録を開始" "$TEST_TMPDIR/home/.distill/logs/record.log"
}

@test "distill-record: 同じセッションを二重に記録しない" {
  mkdir -p "$TEST_TMPDIR/home"
  local repo rec
  repo="$(basename "$GIT_REPO")"
  rec="$TEST_TMPDIR/home/develop/obsidian/99_distill/プロジェクト/$repo/記録"
  mkdir -p "$rec"
  printf -- '---\nsession: s5\n---\n# 既存\n' > "$rec/2026-01-01-0000.md"
  run_hook "s5" "$GIT_REPO" "$TX" >/dev/null
  grep -qF "既に記録がある" "$TEST_TMPDIR/home/.distill/logs/record.log"
}

@test "distill-record: 日本語に接する変数参照は中括弧で閉じる" {
  # macOS の /bin/bash は 3.2 で、変数名の終端を多バイト文字で判定できない。
  # `（$repo）` は名前が `repo` + 壊れた 1 バイトになり set -u で落ちる。
  # 否定は件数で見る。`! grep` は bats で素通りする。
  local hits
  hits=$(grep -cE '\$[A-Za-z_][A-Za-z0-9_]*[^ -~]' "$SCRIPT" || true)
  [ "$hits" -eq 0 ]
}

@test "distill-transcript: ツール出力とスキル本文を落とす" {
  local out="$TEST_TMPDIR/digest.md"
  {
    cat "$TX"
    printf '%s\n' '{"type":"user","message":{"content":"Base directory for this skill: /x"}}'
    printf '%s\n' '{"type":"user","message":{"content":"<system-reminder>無視して</system-reminder>"}}'
  } > "$TEST_TMPDIR/tx2.jsonl"
  /usr/bin/python3 "$EXTRACT" "$TEST_TMPDIR/tx2.jsonl" "$out" >/dev/null
  grep -qF "直してください" "$out"
  local noise
  noise=$(grep -cE "Base directory|system-reminder|tool_use" "$out" || true)
  [ "$noise" -eq 0 ]
}

@test "distill-record: ツール操作だけのセッションは記録しない" {
  # 発言も応答も無い transcript。抽出そのものが空になる。
  mkdir -p "$TEST_TMPDIR/home"
  local tx="$TEST_TMPDIR/tools-only.jsonl"
  {
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit"}]}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write"}]}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit"}]}}'
  } > "$tx"
  run_hook "s6" "$GIT_REPO" "$tx" >/dev/null
  grep -qF "会話を抽出できなかった" "$TEST_TMPDIR/home/.distill/logs/record.log"
}

@test "distill-record: ユーザーの発言が無いセッションは記録しない" {
  # 応答だけが残っていて、依頼が 1 つも無い場合。材料が無いのに書かせると
  # 作文になる。抽出器が数えた往復数で切る。
  mkdir -p "$TEST_TMPDIR/home"
  local tx="$TEST_TMPDIR/no-user.jsonl"
  {
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"直しました"}]}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit"}]}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write"}]}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit"}]}}'
  } > "$tx"
  run_hook "s7" "$GIT_REPO" "$tx" >/dev/null
  grep -qF "0 往復" "$TEST_TMPDIR/home/.distill/logs/record.log"
}

@test "distill-record: 成否は記録の実在で決める（終了コードを信じない）" {
  # 支出上限などで API に拒否されても claude は 0 で抜けるため、終了コードでは
  # 成功と区別できない（実際にそう記録されていた）。
  # 語ではなく判定の形を見る。コメントに書いた語に当たらないようにする。
  grep -qF '記録を書いた' "$SCRIPT"
  grep -qF '記録が作られなかった' "$SCRIPT"
  local by_exit
  by_exit=$(grep -cF '終了コード \$?' "$SCRIPT" || true)
  [ "$by_exit" -eq 0 ]
}
