#!/usr/bin/env bats
# 続きから再開する起動関数（clpc / clwc）。
#
# clpa / clwa は必ずプロンプトを渡すので、必ず新しいセッションになる。更新や
# 端末を閉じたあとに前の会話へ戻る手段が無かった。clpc / clwc はプロンプトを
# 渡さず --continue を付ける。
#
# 実際の claude は起動しない。PATH の先頭にスタブを置き、渡された引数を記録
# して検査する。

load "helpers/common"

setup() {
  make_tmpdir
  STUB="$TEST_TMPDIR/bin"
  mkdir -p "$STUB"
  ARGS="$TEST_TMPDIR/args"
  : >"$ARGS"
  export ARGS
  printf '#!/bin/bash\nprintf "%%s\\n" "$@" >>"$ARGS"\n' >"$STUB/claude"
  chmod +x "$STUB/claude"
  export HOME="$TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

teardown() { rm -rf "$TEST_TMPDIR"; }

# 関数を読み込んで 1 つ実行する。PATH のスタブ以外は触らせない。
run_fn() {  # $1 = 関数名, 以降 = 引数
  run bash -c "PATH='$STUB:\$PATH'; . '$REPO_DIR/.aliases.sh' >/dev/null 2>&1; $*"
}

args() { cat "$ARGS" 2>/dev/null || true; }
# -- は必須。検査する引数が "--continue" のように - で始まるため、付けないと
# grep がオプションとして解釈して常にエラーになり、検査が素通りする。
has_arg() { args | grep -qxF -- "$1"; }
arg_count() {
  local n
  n=$(args | grep -c .) || n=0
  printf '%s' "$n"
}

@test "clwc は --continue を渡す" {
  run_fn clwc
  has_arg '--continue'
}

@test "clwc は自律実行フラグを落とさない" {
  # ここが落ちると、続きから開いた瞬間に確認を求められて自律実行が止まる。
  run_fn clwc
  has_arg '--dangerously-skip-permissions'
}

@test "clwc はプロンプトを渡さない（渡すと新規セッションになる）" {
  run_fn clwc
  n=$(args | grep -c 'Implement the requested changes') || n=0
  [ "$n" -eq 0 ]
}

@test "clwc に渡した引数はそのまま転送される" {
  run_fn clwc "つづきをお願い"
  has_arg 'つづきをお願い'
  has_arg '--continue'
}

@test "clpc も --continue と自律実行フラグを渡す" {
  run_fn clpc
  has_arg '--continue'
  has_arg '--dangerously-skip-permissions'
}

@test "clwa は従来どおりプロンプトを渡す（--continue は付けない）" {
  # clwc を足したことで clwa の挙動が変わっていないことを確かめる。
  run_fn clwa
  args | grep -qF 'Implement the requested changes'
  n=$(args | grep -cxF -- '--continue') || n=0
  [ "$n" -eq 0 ]
}

@test "help_key に clpc / clwc が載っている" {
  grep -qF 'clwc' "$REPO_DIR/bin/help_key"
  grep -qF 'clpc' "$REPO_DIR/bin/help_key"
}
