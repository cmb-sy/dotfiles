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
  rec="$TEST_TMPDIR/home/develop/distill-vault/プロジェクト/$repo/記録"
  mkdir -p "$rec"
  printf -- '---\nsession: s5\n---\n# 既存\n' > "$rec/2026-01-01-0000.md"
  run_hook "s5" "$GIT_REPO" "$TX" >/dev/null
  grep -qF "既に記録がある" "$TEST_TMPDIR/home/.distill/logs/record.log"
  local started
  started=$(grep -cF "記録を開始" "$TEST_TMPDIR/home/.distill/logs/record.log" || true)
  [ "$started" -eq 0 ]
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

@test "distill-record: 正本と digest を許可ディレクトリとして渡す" {
  # claude は作業ディレクトリの外を既定では読み書きできない。フックは
  # 対象リポジトリを cwd にして走らせるので、正本も digest も外側になる。
  # 無人実行では許可を尋ねる相手が居ないため、渡さないと何も書かずに終わる。
  grep -qF -- '--add-dir' "$SCRIPT"
  grep -qF -- '.distill/tmp' "$SCRIPT"
}

@test "distill-record: --add-dir はプロンプトより後ろに置く" {
  # --add-dir は可変長引数で、後ろの語をすべて飲む。プロンプトより前に置くと
  # プロンプトごと許可ディレクトリとして解釈され、claude は入力が無いと言って
  # 即終了する。行番号で順序を固定する。
  local prompt_line add_dir_line
  prompt_line=$(grep -n 'claude -p' "$SCRIPT" | head -1 | cut -d: -f1)
  add_dir_line=$(grep -n -- '--add-dir' "$SCRIPT" | head -1 | cut -d: -f1)
  [ "$add_dir_line" -gt "$prompt_line" ]
}

# --- 開いたままのセッションを何度かに分けて記録する -----------------------
#
# 巡回（bin/distill-record-sweep）は同じセッションを何度も渡してくる。
# どこまで書いたかを覚えていないと、同じ会話を書き直すか、続きを落とす。

# 書き込みまで走らせる。claude は偽物に差し替え、渡されたプロンプトと digest を
# 手元に残して、記録を 1 つ書く（FAKE_CLAUDE_NOWRITE なら書かない）。
make_fake_claude() {
  mkdir -p "$TEST_TMPDIR/bin"
  cat >"$TEST_TMPDIR/bin/claude" <<'SH'
#!/bin/bash
prompt="$2"
calls="$FAKE_CLAUDE_CALLS"
digest=$(printf '%s' "$prompt" | sed -n "s/.*会話の代わりに '\([^']*\)'.*/\1/p")
sid=$(printf '%s' "$prompt" | sed -n 's/.*session には \([A-Za-z0-9_-]*\) を.*/\1/p')
printf '%s\n' "$sid" >>"$calls"
n=$(wc -l <"$calls" | tr -d ' ')
printf '%s\n' "$prompt" >"$calls.prompt.$n"
cp "$digest" "$calls.digest.$n"
[ -n "${FAKE_CLAUDE_NOWRITE:-}" ] && exit 0
dest="$HOME/develop/distill-vault/プロジェクト/${FAKE_CLAUDE_PROJECT:-$(basename "$PWD")}/記録"
mkdir -p "$dest"
f=$(grep -l "^session: ${sid}\$" "$dest"/*.md 2>/dev/null | head -1)
[ -n "$f" ] || f="$dest/2026-01-01-0000.md"
{ printf -- '---\nsession: %s\n---\n' "$sid"; cat "$digest"; } >"$f"
SH
  chmod +x "$TEST_TMPDIR/bin/claude"
}

# 前景で走らせ、終了コードを返す。10 は「書き込みを渡した」。
run_hook_fg() {
  local sid="$1" cwd="$2" tx="$3"
  printf '{"session_id":"%s","cwd":"%s","transcript_path":"%s"}' "$sid" "$cwd" "$tx" \
    | HOME="$TEST_TMPDIR/home" PATH="$TEST_TMPDIR/bin:$PATH" DISTILL_RECORD_FOREGROUND=1 \
      FAKE_CLAUDE_CALLS="$TEST_TMPDIR/calls" bash "$SCRIPT" >/dev/null 2>&1
}

calls() { [ -f "$TEST_TMPDIR/calls" ] && wc -l <"$TEST_TMPDIR/calls" | tr -d ' ' || echo 0; }

# 会話 1 往復と編集 3 件を足す。
append_turn() {
  local tx="$1" text="$2"
  {
    printf '{"type":"user","message":{"content":"%s"}}\n' "$text"
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"対応しました"}]}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit"}]}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit"}]}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write"}]}}'
  } >>"$tx"
}

@test "distill-record: 2 回目は前回の記録より後の会話だけを渡す" {
  mkdir -p "$TEST_TMPDIR/home"
  make_fake_claude
  local rc=0
  run_hook_fg "c1" "$GIT_REPO" "$TX" || rc=$?
  [ "$rc" -eq 10 ]
  grep -qF "直してください" "$TEST_TMPDIR/calls.digest.1"
  grep -qF "記録を書いた" "$TEST_TMPDIR/home/.distill/logs/record.log"

  append_turn "$TX" "続きをお願いします"
  rc=0
  run_hook_fg "c1" "$GIT_REPO" "$TX" || rc=$?
  [ "$rc" -eq 10 ]
  grep -qF "続きをお願いします" "$TEST_TMPDIR/calls.digest.2"
  local old
  old=$(grep -cF "直してください" "$TEST_TMPDIR/calls.digest.2" || true)
  [ "$old" -eq 0 ]
  # 既存の記録へ書き足させる。新しい記録として書かせると 1 セッションが割れる。
  grep -qF "続きを書き足して" "$TEST_TMPDIR/calls.prompt.2"
  local first
  first=$(grep -cF "続きを書き足して" "$TEST_TMPDIR/calls.prompt.1" || true)
  [ "$first" -eq 0 ]
}

@test "distill-record: 伸びていない transcript は黙って飛ばす" {
  # 巡回は 30 分ごとに同じ候補を渡す。毎回ログを足すと読めなくなる。
  mkdir -p "$TEST_TMPDIR/home"
  make_fake_claude
  run_hook_fg "c2" "$GIT_REPO" "$TX" || true
  local before after
  before=$(wc -l <"$TEST_TMPDIR/home/.distill/logs/record.log")
  run_hook_fg "c2" "$GIT_REPO" "$TX" || true
  after=$(wc -l <"$TEST_TMPDIR/home/.distill/logs/record.log")
  [ "$before" -eq "$after" ]
  [ "$(calls)" -eq 1 ]
}

@test "distill-record: 管理用の行が増えただけなら判定し直さない" {
  # 開いたままのセッションは会話が無くても mode などを足し続ける。大きさで
  # 見ると、足されるたびに判定をやり直してログを埋める。
  mkdir -p "$TEST_TMPDIR/home"
  make_fake_claude
  run_hook_fg "c2b" "$GIT_REPO" "$TX" || true
  local before after
  before=$(wc -l <"$TEST_TMPDIR/home/.distill/logs/record.log")
  printf '%s\n' '{"type":"mode","mode":"normal"}' '{"type":"last-prompt","lastPrompt":"x"}' >>"$TX"
  run_hook_fg "c2b" "$GIT_REPO" "$TX" || true
  after=$(wc -l <"$TEST_TMPDIR/home/.distill/logs/record.log")
  [ "$before" -eq "$after" ]
  [ "$(calls)" -eq 1 ]
}

@test "distill-record: 書かせた区間は失敗しても書かせ直さない" {
  # 支出上限で断られ続けると、巡回のたびに LLM を起こすことになる。
  mkdir -p "$TEST_TMPDIR/home"
  make_fake_claude
  FAKE_CLAUDE_NOWRITE=1 run_hook_fg "c3" "$GIT_REPO" "$TX" || true
  grep -qF "記録が作られなかった" "$TEST_TMPDIR/home/.distill/logs/record.log"
  # 状態を消さない限り、同じ transcript をもう一度渡しても起動しない。
  FAKE_CLAUDE_NOWRITE=1 run_hook_fg "c3" "$GIT_REPO" "$TX" || true
  [ "$(calls)" -eq 1 ]
}

@test "distill-record: 届かなかった区間は持ち越して次と合わせて数える" {
  mkdir -p "$TEST_TMPDIR/home"
  make_fake_claude
  local tx="$TEST_TMPDIR/small.jsonl"
  {
    printf '%s\n' '{"type":"user","message":{"content":"最初の小さな依頼"}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit"}]}}'
  } >"$tx"
  run_hook_fg "c4" "$GIT_REPO" "$tx" || true
  [ "$(calls)" -eq 0 ]
  append_turn "$tx" "次の依頼"
  run_hook_fg "c4" "$GIT_REPO" "$tx" || true
  [ "$(calls)" -eq 1 ]
  grep -qF "最初の小さな依頼" "$TEST_TMPDIR/calls.digest.1"
  grep -qF "次の依頼" "$TEST_TMPDIR/calls.digest.1"
}

@test "distill-record: 手で書いた記録より後の会話だけを見る" {
  # 位置の記録が無いのに記録がある = セッション内で distill-project を
  # 手で走らせた。記録の更新時刻で区切る。
  mkdir -p "$TEST_TMPDIR/home"
  make_fake_claude
  local repo rec tx="$TEST_TMPDIR/stamped.jsonl"
  repo="$(basename "$GIT_REPO")"
  rec="$TEST_TMPDIR/home/develop/distill-vault/プロジェクト/$repo/記録"
  mkdir -p "$rec"
  printf -- '---\nsession: c5\n---\n# 既存\n' >"$rec/2026-01-01-0000.md"
  {
    printf '%s\n' '{"type":"user","timestamp":"2000-01-01T00:00:00.000Z","message":{"content":"書く前の依頼"}}'
    printf '%s\n' '{"type":"assistant","timestamp":"2000-01-01T00:00:01.000Z","message":{"content":[{"type":"tool_use","name":"Edit"}]}}'
    printf '%s\n' '{"type":"user","timestamp":"2099-01-01T00:00:00.000Z","message":{"content":"書いた後の依頼"}}'
    printf '%s\n' '{"type":"assistant","timestamp":"2099-01-01T00:00:01.000Z","message":{"content":[{"type":"tool_use","name":"Edit"}]}}'
    printf '%s\n' '{"type":"assistant","timestamp":"2099-01-01T00:00:02.000Z","message":{"content":[{"type":"tool_use","name":"Edit"}]}}'
    printf '%s\n' '{"type":"assistant","timestamp":"2099-01-01T00:00:03.000Z","message":{"content":[{"type":"tool_use","name":"Write"}]}}'
  } >"$tx"
  run_hook_fg "c5" "$GIT_REPO" "$tx" || true
  [ "$(calls)" -eq 1 ]
  grep -qF "書いた後の依頼" "$TEST_TMPDIR/calls.digest.1"
  local old
  old=$(grep -cF "書く前の依頼" "$TEST_TMPDIR/calls.digest.1" || true)
  [ "$old" -eq 0 ]
  grep -qF "続きを書き足して" "$TEST_TMPDIR/calls.prompt.1"
}

@test "distill-record: SDK からの無人実行は記録しない" {
  # 記録を書く実行も SessionEnd を起こす（sdk-cli）。通すと記録の記録を書きに
  # 行く。SDK から自動で起こされるレビューなど（sdk-py）も会話の記録ではない。
  mkdir -p "$TEST_TMPDIR/home"
  make_fake_claude
  local entry tx
  for entry in sdk-cli sdk-py sdk-ts some-new-runner; do
    tx="$TEST_TMPDIR/$entry.jsonl"
    printf '{"type":"user","entrypoint":"%s","message":{"content":"自動の依頼"}}\n' "$entry" >"$tx"
    append_turn "$tx" "書いてください"
    run_hook_fg "e-$entry" "$GIT_REPO" "$tx" || true
    grep -qF "e-${entry}: 対話ではないセッション（${entry}）" "$TEST_TMPDIR/home/.distill/logs/record.log"
  done
  [ "$(calls)" -eq 0 ]
}

@test "distill-record: アプリからの対話は記録する" {
  mkdir -p "$TEST_TMPDIR/home"
  make_fake_claude
  local tx="$TEST_TMPDIR/desktop.jsonl"
  printf '%s\n' '{"type":"user","entrypoint":"claude-desktop","message":{"content":"直してください"}}' >"$tx"
  append_turn "$tx" "続き"
  run_hook_fg "e-desktop" "$GIT_REPO" "$tx" || true
  [ "$(calls)" -eq 1 ]
}

@test "distill-record: 除外.md に載ったリポジトリは LLM を起こさない" {
  # 判定は distill 本体に任せる。ここでは「除外」と答える偽物で、答えに
  # 従うことだけを見る。
  mkdir -p "$TEST_TMPDIR/home"
  make_fake_claude
  printf '#!/bin/sh\ncat >/dev/null\nexit 0\n' >"$TEST_TMPDIR/bin/distill-py"
  chmod +x "$TEST_TMPDIR/bin/distill-py"
  DISTILL_RECORD_PY="$TEST_TMPDIR/bin/distill-py" run_hook_fg "c7" "$GIT_REPO" "$TX" || true
  grep -qF "除外.md に載っている" "$TEST_TMPDIR/home/.distill/logs/record.log"
  [ "$(calls)" -eq 0 ]
}

@test "distill-record: 除外を判定できなければ記録を続ける" {
  mkdir -p "$TEST_TMPDIR/home"
  make_fake_claude
  printf '#!/bin/sh\ncat >/dev/null\nexit 1\n' >"$TEST_TMPDIR/bin/distill-py"
  chmod +x "$TEST_TMPDIR/bin/distill-py"
  DISTILL_RECORD_PY="$TEST_TMPDIR/bin/distill-py" run_hook_fg "c8" "$GIT_REPO" "$TX" || true
  grep -qF "判定できなかった" "$TEST_TMPDIR/home/.distill/logs/record.log"
  [ "$(calls)" -eq 1 ]
}

@test "distill-record: cwd の無い入力は transcript の最後の cwd を使う" {
  # 巡回は transcript しか知らない。
  mkdir -p "$TEST_TMPDIR/home"
  local tx="$TEST_TMPDIR/cwd.jsonl"
  printf '{"type":"user","cwd":"%s","message":{"content":"最初"}}\n' "$TEST_TMPDIR" >"$tx"
  printf '{"type":"user","cwd":"%s","message":{"content":"移った先で依頼"}}\n' "$GIT_REPO" >>"$tx"
  append_turn "$tx" "続き"
  printf '{"session_id":"c9","transcript_path":"%s"}' "$tx" \
    | HOME="$TEST_TMPDIR/home" DISTILL_RECORD_DRY_RUN=1 bash "$SCRIPT" >/dev/null 2>&1
  grep -qF "記録を開始（$(basename "$GIT_REPO")" "$TEST_TMPDIR/home/.distill/logs/record.log"
}

@test "distill-record: 同じセッションを判定中なら手を出さない" {
  # SessionEnd と巡回が重なったとき、両方が書かせると記録が二重になる。
  mkdir -p "$TEST_TMPDIR/home/.distill/state/record/c10.lock"
  make_fake_claude
  local rc=0
  run_hook_fg "c10" "$GIT_REPO" "$TX" || rc=$?
  [ "$rc" -eq 0 ]
  [ "$(calls)" -eq 0 ]
}

@test "distill-record: 取り残されたロックは 30 分で見限る" {
  local lock="$TEST_TMPDIR/home/.distill/state/record/c11.lock"
  mkdir -p "$lock"
  touch -t "$(date -v-31M +%Y%m%d%H%M)" "$lock"
  make_fake_claude
  run_hook_fg "c11" "$GIT_REPO" "$TX" || true
  [ "$(calls)" -eq 1 ]
}

@test "distill-record: dry-run は状態を残さない" {
  # 対象を確かめるだけの実行で「判定済み」にすると、本番で黙って飛ばされる。
  # 判定で落ちる経路も見る。判定を通る経路は状態を書く前に抜ける。
  mkdir -p "$TEST_TMPDIR/home"
  run_hook "c12" "$GIT_REPO" "$TX" >/dev/null
  printf '{"session_id":"c12b","cwd":"%s","transcript_path":"%s"}' "$GIT_REPO" "$TX" \
    | HOME="$TEST_TMPDIR/home" DISTILL_RECORD_MIN_EDITS=99 \
      DISTILL_RECORD_DRY_RUN=1 bash "$SCRIPT" >/dev/null 2>&1
  grep -qF "c12b: 編集" "$TEST_TMPDIR/home/.distill/logs/record.log"
  [ ! -e "$TEST_TMPDIR/home/.distill/state/record/c12" ]
  [ ! -e "$TEST_TMPDIR/home/.distill/state/record/c12b" ]
}

@test "distill-record: パスになる session_id は受け付けない" {
  mkdir -p "$TEST_TMPDIR/home"
  run_hook "../x" "$GIT_REPO" "$TX" >/dev/null
  grep -qF "session_id の形が想定外" "$TEST_TMPDIR/home/.distill/logs/record.log"
  [ ! -e "$TEST_TMPDIR/home/.distill/state/x" ]
}

@test "distill-transcript: --from-byte は行の途中から読み始めない" {
  local out="$TEST_TMPDIR/digest.md" off
  # 1 行目の途中を指す。半端な行は捨て、次の行から読む。
  off=$(( $(head -1 "$TX" | wc -c) - 5 ))
  /usr/bin/python3 "$EXTRACT" "$TX" "$out" --from-byte "$off" >/dev/null
  local first
  first=$(grep -cF "直してください" "$out" || true)
  [ "$first" -eq 0 ]
  grep -qF "直しました" "$out"
}

@test "distill-transcript: --offset-after は指定時刻より後の最初の行を指す" {
  local tx="$TEST_TMPDIR/ts.jsonl" off size
  printf '%s\n' '{"type":"user","timestamp":"2000-01-01T00:00:00.000Z","message":{"content":"a"}}' >"$tx"
  printf '%s\n' '{"type":"mode"}' >>"$tx"
  printf '%s\n' '{"type":"user","timestamp":"2099-01-01T00:00:00.000Z","message":{"content":"b"}}' >>"$tx"
  off=$(/usr/bin/python3 "$EXTRACT" --offset-after 1000000000 "$tx")
  [ "$off" -eq "$(head -2 "$tx" | wc -c)" ]
  # 後の行が無ければ全部済んだ扱い（ファイルの大きさ）。
  off=$(/usr/bin/python3 "$EXTRACT" --offset-after 5000000000 "$tx")
  size=$(wc -c <"$tx")
  [ "$off" -eq "$size" ]
}

@test "distill-transcript: 負の --from-byte は受け付けない" {
  run /usr/bin/python3 "$EXTRACT" "$TX" "$TEST_TMPDIR/d.md" --from-byte -1
  [ "$status" -eq 2 ]
}

@test "distill-transcript: --last-activity は最後の会話の時刻と終わりを返す" {
  # 後ろに続く管理用の行は会話ではない。終わりはその手前。
  local tx="$TEST_TMPDIR/la.jsonl" empty="$TEST_TMPDIR/empty.jsonl" out
  printf '%s\n' '{"type":"user","timestamp":"2026-01-01T00:00:00.000Z","message":{"content":"a"}}' >"$tx"
  printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:01:00.000Z","message":{"content":"b"}}' >>"$tx"
  local conv_end
  conv_end=$(wc -c <"$tx" | tr -d ' ')
  printf '%s\n' '{"type":"mode","mode":"normal"}' '{"type":"ai-title","aiTitle":"t"}' >>"$tx"
  printf '%s\n' '{"type":"mode","mode":"normal"}' >"$empty"
  out=$(/usr/bin/python3 "$EXTRACT" --last-activity "$tx" "$empty")
  printf '%s\n' "$out" | grep -qF "$(printf '1767225660\t%s\t%s' "$conv_end" "$tx")"
  printf '%s\n' "$out" | grep -qF "$(printf '0\t0\t%s' "$empty")"
}

# --- 記録に使わないアカウント（ブロックリスト）-------------------------------
#
# ブロックしたアカウントのセッションは、記録しないだけでなく transcript を
# 開きもしない。判定の前に中身を読むと「取得しない」が守れない。

# ブロックリストを置き、そこに載せるアカウントを作る。transcript は読めない
# 権限にして、開こうとしたら判定がそれとわかる形で崩れるようにする。
setup_blocked() {
  BLOCKED="$TEST_TMPDIR/acct-private"
  mkdir -p "$BLOCKED/projects/p" "$TEST_TMPDIR/home"
  printf '# 注釈\n\n  %s   # 末尾の注釈\n' "$BLOCKED" >"$TEST_TMPDIR/blocklist"
  make_fake_claude
}

run_blocked_hook() {
  local sid="$1" tx="$2"
  shift 2
  printf '{"session_id":"%s","cwd":"%s","transcript_path":"%s"}' "$sid" "$GIT_REPO" "$tx" \
    | env HOME="$TEST_TMPDIR/home" PATH="$TEST_TMPDIR/bin:$PATH" DISTILL_RECORD_FOREGROUND=1 \
      FAKE_CLAUDE_CALLS="$TEST_TMPDIR/calls" DISTILL_RECORD_BLOCKLIST="$TEST_TMPDIR/blocklist" \
      "$@" bash "$SCRIPT" >/dev/null 2>&1
}

assert_untouched() {
  local sid="$1" why="${2:-記録に使わないアカウントのセッション}"
  local log="$TEST_TMPDIR/home/.distill/logs/record.log"
  grep -qF "$why" "$log"
  # session もログに残さない。状態もロックも作らない。
  local named
  named=$(grep -cF "$sid" "$log" || true)
  [ "$named" -eq 0 ]
  [ ! -e "$TEST_TMPDIR/home/.distill/state/record/$sid" ]
  [ ! -e "$TEST_TMPDIR/home/.distill/state/record/$sid.lock" ]
  [ "$(calls)" -eq 0 ]
}

@test "distill-record: ブロックしたアカウントの transcript は開かずに止める" {
  setup_blocked
  local tx="$BLOCKED/projects/p/blocked-a.jsonl"
  cp "$TX" "$tx"
  chmod 000 "$tx"
  run_blocked_hook "blocked-a" "$tx" || true
  chmod 600 "$tx"
  assert_untouched "blocked-a"
}

@test "distill-record: symlink 経由の置き場所でも実パスで止める" {
  # ~/.claude はアカウントを指す symlink。transcript_path はその経由で来る。
  setup_blocked
  ln -s "$BLOCKED" "$TEST_TMPDIR/claude-link"
  cp "$TX" "$BLOCKED/projects/p/blocked-b.jsonl"
  run_blocked_hook "blocked-b" "$TEST_TMPDIR/claude-link/projects/p/blocked-b.jsonl" || true
  assert_untouched "blocked-b"
}

@test "distill-record: CLAUDE_CONFIG_DIR がブロック先なら止める" {
  setup_blocked
  run_blocked_hook "blocked-c" "$TX" CLAUDE_CONFIG_DIR="$BLOCKED" || true
  assert_untouched "blocked-c"
}

@test "distill-record: symlink で指した CLAUDE_CONFIG_DIR も実パスで止める" {
  # ブロック先に transcript が無く、手掛かりが設定ディレクトリだけの場合。
  # 文字列で比べると ~/.claude のような symlink 経由の指定を素通しする。
  setup_blocked
  ln -s "$BLOCKED" "$TEST_TMPDIR/config-link"
  run_blocked_hook "blocked-c2" "$TX" CLAUDE_CONFIG_DIR="$TEST_TMPDIR/config-link" || true
  assert_untouched "blocked-c2"
}

@test "distill-record: 同じ session の transcript がブロック先にあれば止める" {
  # 途中で ~/.claude の指す先が変わると、置き場所だけでは見分けられない。
  setup_blocked
  : >"$BLOCKED/projects/p/blocked-d.jsonl"
  run_blocked_hook "blocked-d" "$TX" || true
  assert_untouched "blocked-d"
}

@test "distill-record: ~/ で書いたブロック先を HOME で解く" {
  setup_blocked
  mkdir -p "$TEST_TMPDIR/home/.claude-x/projects/p"
  printf '~/.claude-x\n' >"$TEST_TMPDIR/blocklist"
  cp "$TX" "$TEST_TMPDIR/home/.claude-x/projects/p/blocked-e.jsonl"
  run_blocked_hook "blocked-e" "$TEST_TMPDIR/home/.claude-x/projects/p/blocked-e.jsonl" || true
  assert_untouched "blocked-e"
}

@test "distill-record: ブロックリストを読めなければ何も記録しない" {
  setup_blocked
  rm -f "$TEST_TMPDIR/blocklist"
  run_blocked_hook "open-f" "$TX" || true
  assert_untouched "open-f" "ブロックリストを読めない"
}

# 書き損じたブロックリストで黙って素通しにしない。ブロック先の transcript は
# 読めない権限にして、開こうとしたら判定がそれとわかる形で崩れるようにする。
blocklist_must_block() {
  local sid="$1" why="$2" tx="$BLOCKED/projects/p/$1.jsonl"
  cp "$TX" "$tx"
  chmod 000 "$tx"
  run_blocked_hook "$sid" "$tx" || true
  chmod 600 "$tx"
  assert_untouched "$sid" "$why"
}

@test "distill-record: ブロックリストがディレクトリなら何も記録しない" {
  setup_blocked
  rm -f "$TEST_TMPDIR/blocklist"
  mkdir "$TEST_TMPDIR/blocklist"
  blocklist_must_block "bl-dir" "ブロックリストを読めない"
}

@test "distill-record: 先頭に BOM があってもブロック先として読む" {
  # エディタが保存時に付けることがある。付くと 1 行目が別の文字列になる。
  setup_blocked
  printf '\357\273\277%s\n' "$BLOCKED" >"$TEST_TMPDIR/blocklist"
  blocklist_must_block "bl-bom" "記録に使わないアカウントのセッション"
}

@test "distill-record: 空のブロックリストでは何も記録しない" {
  # 誤って空にしただけで、ブロックしていたアカウントが素通しになる。
  setup_blocked
  local body
  for body in "" "# 注釈だけ\n\n"; do
    printf "$body" >"$TEST_TMPDIR/blocklist"
    blocklist_must_block "bl-empty-${#body}" "ブロックリストを読めない、空"
  done
}

@test "distill-record: 絶対パスにならない行があれば何も記録しない" {
  # 相対パスは作業ディレクトリで意味が変わる。$HOME の文字は展開しない。
  setup_blocked
  local bad
  for bad in "acct-private" '$HOME/.claude-private'; do
    printf '%s\n%s\n' "$BLOCKED" "$bad" >"$TEST_TMPDIR/blocklist"
    blocklist_must_block "bl-rel-${#bad}" "絶対パスにならない行がある"
  done
}

@test "distill-record: 通してよいときだけ 3 を返す（--is-blocked-dir）" {
  # 1 は bash が異常終了したときにも返る。巡回はこれを「通す」と読まない。
  setup_blocked
  local rc
  rc=0
  env HOME="$TEST_TMPDIR/home" DISTILL_RECORD_BLOCKLIST="$TEST_TMPDIR/blocklist" \
    bash "$SCRIPT" --is-blocked-dir "$BLOCKED" || rc=$?
  [ "$rc" -eq 0 ]
  rc=0
  env HOME="$TEST_TMPDIR/home" DISTILL_RECORD_BLOCKLIST="$TEST_TMPDIR/blocklist" \
    bash "$SCRIPT" --is-blocked-dir "$TEST_TMPDIR/home" || rc=$?
  [ "$rc" -eq 3 ]
}

@test "distill-record: ブロック先でないセッションは注釈つきのリストでも記録する" {
  setup_blocked
  run_blocked_hook "open-g" "$TX" || true
  [ "$(calls)" -eq 1 ]
}

@test "distill-record: private アカウントはブロックリストに載っている" {
  # 記録に一切使わないと決めたアカウント。行が消えると SessionEnd から記録が始まる。
  grep -qx '~/.claude-private' "${BATS_TEST_DIRNAME}/../claude/hooks/distill-record.blocklist"
}

@test "distill-record: 取り残されたロックは中身があっても外す" {
  # rmdir で消せないロックが残ると、そのセッションは黙って記録されなくなる。
  local lock="$TEST_TMPDIR/home/.distill/state/record/c13.lock"
  mkdir -p "$lock"
  : >"$lock/.DS_Store"
  touch -t "$(date -v-31M +%Y%m%d%H%M)" "$lock"
  make_fake_claude
  run_hook_fg "c13" "$GIT_REPO" "$TX" || true
  [ "$(calls)" -eq 1 ]
  grep -qF "c13: 取り残されたロックを外した" "$TEST_TMPDIR/home/.distill/logs/record.log"
}

@test "distill-record: 桁あふれした状態は壊れたものとして読み直す" {
  mkdir -p "$TEST_TMPDIR/home/.distill/state/record"
  printf '99999999999999999999 99999999999999999999\n' >"$TEST_TMPDIR/home/.distill/state/record/c14"
  make_fake_claude
  run_hook_fg "c14" "$GIT_REPO" "$TX" || true
  [ "$(calls)" -eq 1 ]
}

@test "distill-record: 作業ディレクトリが分からないセッションは記録しない" {
  # 今の場所で代用すると、巡回を起こした別のセッションのリポジトリに紐付く。
  mkdir -p "$TEST_TMPDIR/home"
  make_fake_claude
  printf '{"session_id":"c15","transcript_path":"%s"}' "$TX" \
    | (cd "$GIT_REPO" && HOME="$TEST_TMPDIR/home" PATH="$TEST_TMPDIR/bin:$PATH" \
        DISTILL_RECORD_FOREGROUND=1 FAKE_CLAUDE_CALLS="$TEST_TMPDIR/calls" bash "$SCRIPT") \
    >/dev/null 2>&1 || true
  grep -qF "c15: 作業ディレクトリが分からない" "$TEST_TMPDIR/home/.distill/logs/record.log"
  [ "$(calls)" -eq 0 ]
}

@test "distill-transcript: --to-byte より後の行は読まない" {
  # 会話の終わりを測ったあとに足された行は、次の区間に回す。
  local out="$TEST_TMPDIR/digest.md" stop
  stop=$(head -2 "$TX" | wc -c | tr -d ' ')
  printf '%s\n' '{"type":"user","message":{"content":"後から来た依頼"}}' >>"$TX"
  /usr/bin/python3 "$EXTRACT" "$TX" "$out" --to-byte "$stop" >/dev/null
  grep -qF "直しました" "$out"
  local late
  late=$(grep -cF "後から来た依頼" "$out" || true)
  [ "$late" -eq 0 ]
}

@test "distill-record: スキルが別のプロジェクトに置いた記録も書けたと判定する" {
  # worktree（例: probe-repo-123）の記録を、スキルは元のプロジェクト（probe-repo）に寄せる。
  # フックがリポジトリ名の下だけを探すと、書けたのに失敗と記録する。
  mkdir -p "$TEST_TMPDIR/home"
  make_fake_claude
  FAKE_CLAUDE_PROJECT=base-proj run_hook_fg "c16" "$GIT_REPO" "$TX" || true
  grep -qF "c16: 記録を書いた" "$TEST_TMPDIR/home/.distill/logs/record.log"
  # 続きも、その記録を既存として書き足させる。
  append_turn "$TX" "続きの依頼"
  FAKE_CLAUDE_PROJECT=base-proj run_hook_fg "c16" "$GIT_REPO" "$TX" || true
  grep -qF "続きを書き足して" "$TEST_TMPDIR/calls.prompt.2"
  local failed
  failed=$(grep -cF "c16: 記録が作られなかった" "$TEST_TMPDIR/home/.distill/logs/record.log" || true)
  [ "$failed" -eq 0 ]
}

@test "distill-record: worktree のセッションは元のリポジトリの名前で記録する" {
  # 名前がスキルと食い違うと、除外の判定も記録の置き場所もずれる。
  mkdir -p "$TEST_TMPDIR/home"
  local wt="$TEST_TMPDIR/wt-123"
  git -C "$GIT_REPO" worktree add -q -b feature "$wt"
  run_hook "c17" "$wt" "$TX" >/dev/null
  grep -qF "c17: 記録を開始（$(basename "$GIT_REPO")" "$TEST_TMPDIR/home/.distill/logs/record.log"
}
