#!/usr/bin/env bats
# claude/hooks/pii-guard.py の stdin JSON 契約のテスト。
# PII 形状のフィクスチャは実行時に連結して組み立てる。このファイルの diff に
# リテラルが残ると guard 自身がコミットをブロックするため。

load "helpers/common"

GUARD="${BATS_TEST_DIRNAME}/../claude/hooks/pii-guard.py"

setup() {
  make_tmpdir
  LOG="$TEST_TMPDIR/pii-guard.log"

  addr="taro.yamada@""real-corp"".co.jp"
  ip_priv="10.0.""1.5"

  pw_lbl="pass""word"
  tk_lbl="tok""en"
  card_ok="4111 1111 ""1111 1111"        # Luhn-valid test number
  card_ng="1234-5678 ""9012-3456"        # fails Luhn
  pw_real="Tr0ub4dor""&3xyz"
  k1="user""name"
  k2="ro""le"
  k3="te""am"
  # JP quasi-identifier labels (4 categories), assembled apart
  j1="所""属: 営業部"
  j2="役""職: 本部長代理"
  j3="年""齢: 45"
  j4="性""別: 男"

  # Prose occurrences of quasi-identifier words must not count as matches;
  # only key-like positions should.
  pr1="関""係"
  pr2="tit""le"
  pr3="アカ""ウント"
  pr4="従業""員番号"
  prose="Genie と UC の ${pr1} を説明する。space.json の ${pr2} は陳腐化。個人${pr3} は 4 件。${pr4}リストを渡す。unisex という語も出る。"

  # JSON keys are quoted, so the separator must tolerate a closing quote.
  jk1="employ""ee_id"
  jk2="depart""ment"
  jk3="job_ti""tle"
  jk4="gen""der"
  json_body="{\\\"${jk1}\\\":\\\"000000001\\\",\\\"${jk2}\\\":\\\"Sales\\\",\\\"${jk3}\\\":\\\"Manager\\\",\\\"${jk4}\\\":\\\"male\\\"}"

  # CSV headers use a comma as the separator.
  c1="従業""員番号"
  c2="部""署"
  c3="役""職"
  c4="性""別"
  c5="年""齢"
  csv_body="${c1},${c2},${c3},${c4},${c5}\\n000000001,営業部,課長,男,45"

  payload_write_pii="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/x.md\",\"content\":\"連絡先: ${addr}\"}}"
  payload_write_safe='{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/x.md","content":"contact: info@example.com"}}'
  payload_bash_safe='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls -la"}}'
  payload_edit_pii="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/tmp/x.md\",\"new_string\":\"mail: ${addr}\"}}"
  payload_skip_path="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/tests/fixture.py\",\"content\":\"${addr}\"}}"
  payload_private_ip="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/x.md\",\"content\":\"db host: ${ip_priv} port 5432\"}}"
  payload_yaml_cfg="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/deploy.yaml\",\"content\":\"${k1}: app-service\\n${k2}: admin\\n${k3}: platform\\n\"}}"
  payload_pw_var="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/auth.py\",\"content\":\"${pw_lbl} = hashed_value_ref\"}}"
  payload_tk_call="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/auth.py\",\"content\":\"${tk_lbl}: get_auth_value()\"}}"
  payload_nonluhn="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/x.md\",\"content\":\"id: ${card_ng/ /-}\"}}"
  payload_luhn="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/x.md\",\"content\":\"card: ${card_ok}\"}}"
  payload_real_pw="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/x.md\",\"content\":\"${pw_lbl}: ${pw_real}\"}}"
  payload_quasi4="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/x.md\",\"content\":\"${j1} ${j2} ${j3} ${j4}\"}}"
  payload_prose="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/x.md\",\"content\":\"${prose}\"}}"
  payload_json_keys="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/x.md\",\"content\":\"${json_body}\"}}"
  payload_csv_header="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/x.md\",\"content\":\"${csv_body}\"}}"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

run_guard() {  # $1=stdin payload -> echo exit code
  printf '%s' "$1" | python3 "$GUARD" >/dev/null 2>&1
  echo $?
}

run_guard_logged() {  # $1=stdin payload -> echo exit code, log to $LOG
  printf '%s' "$1" | PII_GUARD_LOG="$LOG" python3 "$GUARD" >/dev/null 2>&1
  echo $?
}

@test "blocks PII in Write content (stdin)" {
  run run_guard "$payload_write_pii"
  [ "$output" = "2" ]
}

@test "allows safe-domain email in Write" {
  run run_guard "$payload_write_safe"
  [ "$output" = "0" ]
}

@test "allows plain Bash command" {
  run run_guard "$payload_bash_safe"
  [ "$output" = "0" ]
}

@test "blocks PII in Edit new_string (stdin)" {
  run run_guard "$payload_edit_pii"
  [ "$output" = "2" ]
}

@test "skips SKIP_PATHS file" {
  run run_guard "$payload_skip_path"
  [ "$output" = "0" ]
}

@test "fail-open on empty stdin" {
  run run_guard ''
  [ "$output" = "0" ]
}

@test "fail-open on broken JSON" {
  run run_guard '{broken'
  [ "$output" = "0" ]
}

@test "env-only invocation is ignored (old contract dead)" {
  export CLAUDE_TOOL=Write
  export CLAUDE_TOOL_INPUT="{\"file_path\":\"/tmp/x.md\",\"content\":\"${addr}\"}"
  run run_guard ''
  [ "$output" = "0" ]
}

@test "private IP no longer blocks (advisory only)" {
  run run_guard_logged "$payload_private_ip"
  [ "$output" = "0" ]
}

@test "advisory logged for private IP" {
  run run_guard_logged "$payload_private_ip"
  grep -qF '"advisory"' "$LOG"
}

@test "block still exits 2 with logging on" {
  run run_guard_logged "$payload_write_pii"
  [ "$output" = "2" ]
}

@test "block event logged" {
  run run_guard_logged "$payload_write_pii"
  grep -qF '"block"' "$LOG"
}

@test "log contains rule label not the PII value" {
  run run_guard_logged "$payload_write_pii"
  hits="$(grep -cF 'real-corp' "$LOG" || true)"
  [ "$hits" = "0" ]
}

@test "yaml-like config keys allowed" {
  run run_guard "$payload_yaml_cfg"
  [ "$output" = "0" ]
}

@test "pw assigned from snake_case variable allowed" {
  run run_guard "$payload_pw_var"
  [ "$output" = "0" ]
}

@test "value from function call allowed" {
  run run_guard "$payload_tk_call"
  [ "$output" = "0" ]
}

@test "16 digits failing Luhn allowed" {
  run run_guard "$payload_nonluhn"
  [ "$output" = "0" ]
}

@test "Luhn-valid card number blocked" {
  run run_guard "$payload_luhn"
  [ "$output" = "2" ]
}

@test "real-looking pw still blocked" {
  run run_guard "$payload_real_pw"
  [ "$output" = "2" ]
}

@test "4 quasi-identifier categories still blocked" {
  run run_guard "$payload_quasi4"
  [ "$output" = "2" ]
}

@test "prose mentions of quasi-identifier words allowed" {
  run run_guard "$payload_prose"
  [ "$output" = "0" ]
}

@test "quoted JSON keys still blocked" {
  run run_guard "$payload_json_keys"
  [ "$output" = "2" ]
}

@test "CSV header of quasi-identifiers still blocked" {
  run run_guard "$payload_csv_header"
  [ "$output" = "2" ]
}
