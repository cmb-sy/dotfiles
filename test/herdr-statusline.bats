#!/usr/bin/env bats
# bin/herdr-statusline and the file claude/statusline.sh hands it.

load "helpers/common"

setup() {
  make_tmpdir
  CMD="$REPO_DIR/bin/herdr-statusline"
  export HERDR_BIN="$TEST_TMPDIR/herdr" HERDR_PANE_ID="w1:pk" HERDR_STATUSLINE_SELF="/x/herdr-statusline"
  export HERDR_STATUSLINE_DIR="$TEST_TMPDIR/sl"
  cat > "$HERDR_BIN" <<EOF
#!/bin/bash
printf '%s\\n' "\$*" >> "$TEST_TMPDIR/calls"
case "\$1 \$2" in
  "pane get") printf '{"result":{"pane":{"pane_id":"%s","tab_id":"w1:t1","workspace_id":"w1","agent_status":"%s"}}}' "\$3" "\${FAKE_STATE:-unknown}" ;;
  "pane list") printf '%s' "\${FAKE_PANES:-}" ;;
  "pane split") printf '%s' '{"result":{"pane":{"pane_id":"w1:p9"}}}'; exit "\${FAKE_SPLIT_EXIT:-0}" ;;
  "pane run") ;;
  *) printf '{"result":{"type":"ok"}}' ;;
esac
EOF
  chmod +x "$HERDR_BIN"
}

teardown() { rm -rf "$TEST_TMPDIR"; }

# pane <id> [label] [agent] [tab]
pane() { printf '{"pane_id":"%s","tab_id":"%s","workspace_id":"w1","label":"%s","agent":"%s"}' "$1" "${4:-w1:t1}" "${2:-}" "${3:-}"; }
panes() { local IFS=,; export FAKE_PANES="{\"result\":{\"panes\":[$*]}}"; }

@test "toggle: 無ければ agent のペインの右に開き、名前を付けて panel を動かす" {
  panes "$(pane w1:p1)" "$(pane w1:p2 '' claude)" "$(pane w1:pk)" "$(pane w1:px statusline '' w1:t2)"
  run "$CMD" toggle
  [ "$status" -eq 0 ]
  grep -qxF "pane split w1:p2 --direction right --ratio 0.8 --no-focus" "$TEST_TMPDIR/calls"
  grep -qxF "pane rename w1:p9 statusline" "$TEST_TMPDIR/calls"
  grep -qxF "pane run w1:p9 exec '/x/herdr-statusline' panel 'w1:p2'" "$TEST_TMPDIR/calls"
  # Another tab's pane is not this tab's.
  [ "$(grep -c '^pane close' "$TEST_TMPDIR/calls")" -eq 0 ]
}

@test "toggle: このタブにあれば閉じるだけ" {
  panes "$(pane w1:p2 '' claude)" "$(pane w1:p9 statusline)" "$(pane w1:pk)"
  run "$CMD" toggle
  [ "$status" -eq 0 ]
  grep -qxF "pane close w1:p9" "$TEST_TMPDIR/calls"
  [ "$(grep -c '^pane split' "$TEST_TMPDIR/calls")" -eq 0 ]
}

@test "toggle: 分割に失敗すれば 1 で終わり、名前付けへ進まない" {
  panes "$(pane w1:p2 '' claude)" "$(pane w1:pk)"
  FAKE_SPLIT_EXIT=1 run "$CMD" toggle
  [ "$status" -eq 1 ]
  [ "$(grep -c '^pane rename' "$TEST_TMPDIR/calls")" -eq 0 ]
}

@test "toggle: herdr の外では 1、引数違いは 2 で終わる" {
  HERDR_PANE_ID= run "$CMD" toggle
  [ "$status" -eq 1 ]
  [ ! -e "$TEST_TMPDIR/calls" ]
  run "$CMD" panel
  [ "$status" -eq 2 ]
}

# panel_run <pane> <text to wait for>: run the panel in a 10x20 pty, then q.
panel_run() {
  run python3 -c '
import fcntl, os, pty, select, struct, sys, termios, time
pid, fd = pty.fork()
if pid == 0:
    fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 20, 0, 0))
    os.execv(sys.argv[1], [sys.argv[1], "panel", sys.argv[2]])
out, end = b"", time.time() + 5
while time.time() < end and sys.argv[3].encode() not in out:
    if select.select([fd], [], [], 0.2)[0]:
        out += os.read(fd, 65536)
os.write(fd, b"q")
# Keep draining: a pty nobody reads can hold the panel on its last write.
end = time.time() + 5
while True:
    done, raw = os.waitpid(pid, os.WNOHANG)
    if done or time.time() > end:
        break
    try:
        if select.select([fd], [], [], 0.1)[0]:
            os.read(fd, 65536)
    except OSError:
        pass
if not done:
    os.kill(pid, 9)
    _, raw = os.waitpid(pid, 0)
print("status=%d" % os.waitstatus_to_exitcode(raw))
sys.stdout.write(out.decode())' "$CMD" "$1" "$2"
}

@test "panel: statusline のファイルを 1 行ずつ出し、幅を超える行は折り返し、q で閉じる" {
  mkdir -p "$HERDR_STATUSLINE_DIR"
  printf 'Opus\nCtx 80%%\n%s\n' "$(printf 'x%.0s' $(seq 1 40))" > "$HERDR_STATUSLINE_DIR/w1:p2"
  panel_run w1:p2 "Ctx 80%"
  printf '%s\n' "$output" | grep -qxF "status=0"
  printf '%s' "$output" | grep -qF "Opus"
  # 20 columns less one on each side: 18, then the rest after a 3-column indent.
  plain="$(printf '%s' "$output" | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' | tr -d '\r')"
  printf '%s\n' "$plain" | grep -qxF " $(printf 'x%.0s' $(seq 1 18))"
  printf '%s\n' "$plain" | grep -qxF "    $(printf 'x%.0s' $(seq 1 15))"
  printf '%s\n' "$plain" | grep -qxF "    $(printf 'x%.0s' $(seq 1 7))"
}

@test "panel: 見出しごとにまとめて間を 1 行空け、残りの割合には小さなバーを付ける" {
  mkdir -p "$HERDR_STATUSLINE_DIR"
  printf 'Model\tOpus\nUsage left\t5h 25%%\nUsage left\t7d --%%\n' > "$HERDR_STATUSLINE_DIR/w1:p2"
  panel_run w1:p2 "7d --%"
  printf '%s\n' "$output" | grep -qxF "status=0"
  plain="$(printf '%s' "$output" | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' | tr -d '\r')"
  [ "$(printf '%s\n' "$plain" | grep -c -e '^ *Model$' -e '^ *Usage left$')" -eq 2 ]
  printf '%s\n' "$plain" | grep -qxF "  Opus"
  printf '%s\n' "$plain" | grep -qxF "  ▰▰▱▱▱▱▱▱ 5h 25%"
  # One blank row between the groups.
  printf '%s\n' "$plain" | grep -A1 -xF "  Opus" | tail -1 | grep -qx " *"
}

@test "panel: agent の状態を一番上に herdr と同じ色で出す" {
  mkdir -p "$HERDR_STATUSLINE_DIR"
  printf 'Model\tOpus\n' > "$HERDR_STATUSLINE_DIR/w1:p2"
  FAKE_STATE=working panel_run w1:p2 "Opus"
  printf '%s\n' "$output" | grep -qxF "status=0"
  printf '%s' "$output" | grep -qF $'\e[33m● working\e[0m'
  plain="$(printf '%s' "$output" | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' | tr -d '\r' | grep -v '^ *$')"
  [ "$(printf '%s\n' "$plain" | sed -n 2p)" = " State" ]
}

@test "panel: セッションの subagent を working から並べ、古いものは出さず、# の行は見せない" {
  mkdir -p "$HERDR_STATUSLINE_DIR" "$TEST_TMPDIR/s1/subagents"
  sub="$TEST_TMPDIR/s1/subagents"
  printf '{"name":"busy","description":"doing it"}' > "$sub/agent-a1.meta.json"; : > "$sub/agent-a1.jsonl"
  printf '{"name":"rest"}' > "$sub/agent-a2.meta.json"; : > "$sub/agent-a2.jsonl"
  touch -t "$(date -v-5M +%Y%m%d%H%M)" "$sub/agent-a2.jsonl"
  printf '{"name":"old"}' > "$sub/agent-a3.meta.json"; : > "$sub/agent-a3.jsonl"
  touch -t "$(date -v-3H +%Y%m%d%H%M)" "$sub/agent-a3.jsonl"
  printf 'Model\tOpus\n#transcript\t%s\n' "$TEST_TMPDIR/s1.jsonl" > "$HERDR_STATUSLINE_DIR/w1:p2"
  panel_run w1:p2 "○ rest"
  printf '%s\n' "$output" | grep -qxF "status=0"
  plain="$(printf '%s' "$output" | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' | tr -d '\r')"
  [ "$(printf '%s\n' "$plain" | grep -A2 -x ' *Agents' | tail -2 | tr '\n' '|')" = "  ● busy|    doing it|" ]
  printf '%s\n' "$plain" | grep -qxF "  ○ rest"
  [ "$(printf '%s\n' "$plain" | grep -c -e old -e transcript)" -eq 0 ]
}

@test "panel: ファイルや subagent の名前に入った制御文字は端末へ渡さない" {
  mkdir -p "$HERDR_STATUSLINE_DIR" "$TEST_TMPDIR/s1/subagents"
  printf '{"name":"ev\\u001b]0;pwn\\u0007il"}' > "$TEST_TMPDIR/s1/subagents/agent-a1.meta.json"
  : > "$TEST_TMPDIR/s1/subagents/agent-a1.jsonl"
  printf 'Mo\033[2Jdel\tO\033]0;x\007pus\n#transcript\t%s\n' "$TEST_TMPDIR/s1.jsonl" > "$HERDR_STATUSLINE_DIR/w1:p2"
  panel_run w1:p2 "il"
  printf '%s\n' "$output" | grep -qxF "status=0"
  [ "$(printf '%s' "$output" | grep -c -e $'\e]0' -e $'\e\[2J' -e $'\a')" -eq 0 ]
  printf '%s' "$output" | grep -qF "ev]0;pwnil"
}

@test "panel: ファイルがまだ無ければ待っていると出す" {
  panel_run w1:p2 "Waiting"
  printf '%s\n' "$output" | grep -qxF "status=0"
  printf '%s' "$output" | grep -qF "Waiting"
}

@test "statusline.sh: herdr の中ではファイルへ 1 項目 1 行で書き、画面には何も出さない" {
  run bash -c 'echo "{\"context_window\":{\"used_percentage\":20}}" | HERDR_PANE_ID=w1:p2 "$1"' _ "$REPO_DIR/claude/statusline.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -qxF "$(printf 'Context left\t80%% (160k)')" <(sed 's/\x1b\[[0-9;]*m//g' "$HERDR_STATUSLINE_DIR/w1:p2")
}

@test "statusline.sh: herdr の外や書けないときは今までどおり画面に出す" {
  run bash -c 'echo "{\"context_window\":{\"used_percentage\":20}}" | HERDR_PANE_ID= "$1"' _ "$REPO_DIR/claude/statusline.sh"
  printf '%s' "$output" | grep -qF "Ctx"
  : > "$TEST_TMPDIR/file"
  export HERDR_STATUSLINE_DIR="$TEST_TMPDIR/file/sub"
  run bash -c 'echo "{\"context_window\":{\"used_percentage\":20}}" | HERDR_PANE_ID=w1:p2 "$1"' _ "$REPO_DIR/claude/statusline.sh"
  printf '%s' "$output" | grep -qF "Ctx"
}
