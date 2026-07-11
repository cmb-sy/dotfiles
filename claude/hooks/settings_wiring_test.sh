#!/bin/bash
# settings.json の inline hook command が stdin JSON で実際に動くかの配線テスト
# (post-commit 起動判定 / 破壊的コマンドブロック)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="${SCRIPT_DIR}/../settings.json"
source "${SCRIPT_DIR}/test-helpers.sh"

# --- 抽出: matcher/内容で select (インデックス非依存) ---
POST_CMD="$(jq -r '.hooks.PostToolUse[] | select(.matcher=="Bash") | .hooks[].command | select(contains("post-commit"))' "$SETTINGS")"
BLOCK_CMD="$(jq -r '.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[].command | select(contains("BLOCK"))' "$SETTINGS")"
assert_eq "post-commit trigger exists in settings" "0" "$([ -n "$POST_CMD" ]; echo $?)"
assert_eq "destructive block exists in settings"   "0" "$([ -n "$BLOCK_CMD" ]; echo $?)"

# --- post-commit 起動判定: stub した post-commit.sh が呼ばれるか ---
FAKE_HOME="$(mktemp -d)"
mkdir -p "$FAKE_HOME/.claude/hooks"
printf '#!/bin/bash\necho CALLED\n' > "$FAKE_HOME/.claude/hooks/post-commit.sh"
chmod +x "$FAKE_HOME/.claude/hooks/post-commit.sh"

run_post() { printf '%s' "$1" | HOME="$FAKE_HOME" bash -c "$POST_CMD" 2>&1; }
assert_contains "git commit triggers post-commit hook" \
  "$(run_post '{"tool_input":{"command":"git commit -m test"}}')" "CALLED"
assert_eq "non-commit command does not trigger" "" \
  "$(run_post '{"tool_input":{"command":"ls -la"}}')"
assert_eq "broken JSON does not trigger" "" \
  "$(run_post 'not-json')"
rm -rf "$FAKE_HOME"

# --- 破壊的コマンドブロック: exit 2 / 0 ---
run_block() { printf '%s' "$1" | bash -c "$BLOCK_CMD" >/dev/null 2>&1; echo $?; }
assert_eq "blocks rm -rf /"           "2" "$(run_block '{"tool_input":{"command":"rm -rf /"}}')"
assert_eq "blocks rm -rf ~"           "2" "$(run_block '{"tool_input":{"command":"rm -rf ~"}}')"
assert_eq "blocks rm -rf /usr"        "2" "$(run_block '{"tool_input":{"command":"rm -rf /usr"}}')"
assert_eq "blocks rm -rf /etc subtree" "2" "$(run_block '{"tool_input":{"command":"rm -rf /etc/hosts"}}')"
assert_eq "blocks dd if="             "2" "$(run_block '{"tool_input":{"command":"dd if=/dev/zero of=/dev/sda"}}')"
assert_eq "allows normal command"     "0" "$(run_block '{"tool_input":{"command":"ls -la /usr"}}')"
assert_eq "allows rm -rf of tmp path" "0" "$(run_block '{"tool_input":{"command":"rm -rf /tmp/foo"}}')"
assert_eq "allows rm -rf of home subdir" "0" "$(run_block '{"tool_input":{"command":"rm -rf ~/scratch/foo"}}')"
assert_eq "fail-open on empty stdin"  "0" "$(run_block '')"

print_summary
