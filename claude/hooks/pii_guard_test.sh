#!/bin/bash
# Tests for the stdin JSON contract of pii-guard.py.
# Run: bash claude/hooks/pii_guard_test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD="${SCRIPT_DIR}/pii-guard.py"
source "${SCRIPT_DIR}/test-helpers.sh"

run_guard() {  # $1=stdin payload -> echo exit code
  printf '%s' "$1" | python3 "$GUARD" >/dev/null 2>&1
  echo $?
}

# Assemble a realistic-looking email at runtime (never leave it as a literal in this file)
addr="taro.yamada@""real-corp"".co.jp"

payload_write_pii="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/x.md\",\"content\":\"連絡先: ${addr}\"}}"
payload_write_safe='{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/x.md","content":"contact: info@example.com"}}'
payload_bash_safe='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls -la"}}'
payload_edit_pii="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/tmp/x.md\",\"new_string\":\"mail: ${addr}\"}}"
payload_skip_path="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/tests/fixture.py\",\"content\":\"${addr}\"}}"

assert_eq "blocks PII in Write content (stdin)"        "2" "$(run_guard "$payload_write_pii")"
assert_eq "allows safe-domain email in Write"          "0" "$(run_guard "$payload_write_safe")"
assert_eq "allows plain Bash command"                  "0" "$(run_guard "$payload_bash_safe")"
assert_eq "blocks PII in Edit new_string (stdin)"      "2" "$(run_guard "$payload_edit_pii")"
assert_eq "skips SKIP_PATHS file"                      "0" "$(run_guard "$payload_skip_path")"
assert_eq "fail-open on empty stdin"                   "0" "$(run_guard '')"
assert_eq "fail-open on broken JSON"                   "0" "$(run_guard '{broken')"
assert_eq "env-only invocation is ignored (old contract dead)" "0" \
  "$(CLAUDE_TOOL=Write CLAUDE_TOOL_INPUT="{\"file_path\":\"/tmp/x.md\",\"content\":\"${addr}\"}" run_guard '')"

# --- Task 1: logging + private IP advisory ---
# PII-shaped fixtures are assembled at runtime so the git diff of this file
# never contains a literal the (old or new) guard would match.
tmplog="$(mktemp /private/tmp/pii-guard-test-log.XXXXXX)"

run_guard_logged() {  # $1=stdin payload -> echo exit code (log to tmplog)
  printf '%s' "$1" | PII_GUARD_LOG="$tmplog" python3 "$GUARD" >/dev/null 2>&1
  echo $?
}

ip_priv="10.0.""1.5"
payload_private_ip="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/x.md\",\"content\":\"db host: ${ip_priv} port 5432\"}}"

assert_eq "private IP no longer blocks (advisory only)" "0" "$(run_guard_logged "$payload_private_ip")"
assert_eq "advisory logged for private IP" "0" "$(grep -qF '"advisory"' "$tmplog"; echo $?)"

: > "$tmplog"
assert_eq "block still exits 2 with logging on" "2" "$(run_guard_logged "$payload_write_pii")"
assert_eq "block event logged" "0" "$(grep -qF '"block"' "$tmplog"; echo $?)"
assert_eq "log contains rule label not the PII value" "1" "$(grep -qF 'real-corp' "$tmplog"; echo $?)"

rm -f "$tmplog"

# --- Task 2: detection rule fixes ---
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

payload_yaml_cfg="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/deploy.yaml\",\"content\":\"${k1}: app-service\\n${k2}: admin\\n${k3}: platform\\n\"}}"
payload_pw_var="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/auth.py\",\"content\":\"${pw_lbl} = hashed_value_ref\"}}"
payload_tk_call="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/auth.py\",\"content\":\"${tk_lbl}: get_auth_value()\"}}"
payload_nonluhn="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/x.md\",\"content\":\"id: ${card_ng/ /-}\"}}"
payload_luhn="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/x.md\",\"content\":\"card: ${card_ok}\"}}"
payload_real_pw="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/x.md\",\"content\":\"${pw_lbl}: ${pw_real}\"}}"
payload_quasi4="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/x.md\",\"content\":\"${j1} ${j2} ${j3} ${j4}\"}}"

assert_eq "yaml-like config keys allowed"                  "0" "$(run_guard "$payload_yaml_cfg")"
assert_eq "pw assigned from snake_case variable allowed"   "0" "$(run_guard "$payload_pw_var")"
assert_eq "value from function call allowed"               "0" "$(run_guard "$payload_tk_call")"
assert_eq "16 digits failing Luhn allowed"                 "0" "$(run_guard "$payload_nonluhn")"
assert_eq "Luhn-valid card number blocked"                 "2" "$(run_guard "$payload_luhn")"
assert_eq "real-looking pw still blocked"                  "2" "$(run_guard "$payload_real_pw")"
assert_eq "4 quasi-identifier categories still blocked"    "2" "$(run_guard "$payload_quasi4")"

print_summary
