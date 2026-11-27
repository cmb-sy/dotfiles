#!/usr/bin/env bats
# herdr のタブをリポジトリごとの列で一覧する。herdr と gh のスタブと偽の会話ログで、--once の出力と、端末でのクリック・横スクロールを検査する。

load "helpers/common"
bats_require_minimum_version 1.5.0

# 2026-03-01 12:00:00 UTC. Ages are counted back from here.
NOW=1772366400
DAY=86400

setup() {
  make_tmpdir
  cat > "$TEST_TMPDIR/herdr" <<EOF
#!/bin/bash
case "\$1 \$2" in
  "workspace list") printf '%s' "\${FAKE_WS:-}"; exit "\${FAKE_HERDR_EXIT:-0}" ;;
  "tab list")
    # A file lets a test change the tabs while the board runs.
    if [ -n "\${FAKE_TABS_FILE:-}" ]; then cat "\$FAKE_TABS_FILE"; else printf '%s' "\${FAKE_TABS:-}"; fi
    exit "\${FAKE_HERDR_EXIT:-0}" ;;
  "agent list") printf '%s' "\${FAKE_AGENTS:-}"; exit "\${FAKE_HERDR_EXIT:-0}" ;;
  "workspace create") printf "%s\\n" "\$*" >> "$TEST_TMPDIR/calls"; printf '%s' "\${FAKE_CREATE:-}"; exit 0 ;;
  "pane list") printf '%s' "\${FAKE_PANES:-}"; exit 0 ;;
  "pane process-info") printf '%s' "\${FAKE_PROC:-}"; exit 0 ;;
  "pane get")
    if [ "\$3" = "\${FAKE_PANE_ID:-}" ]; then printf '%s' "\${FAKE_PANE:-}"; fi
    exit 0 ;;
esac
printf "%s\\n" "\$*" >> "$TEST_TMPDIR/calls"
EOF
  cat > "$TEST_TMPDIR/gh" <<EOF
#!/bin/bash
printf "%s\\n" "\$*" >> "$TEST_TMPDIR/gh-calls"
n="" repo=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    --repo) repo="\$2"; shift ;;
    [0-9]*) n="\$1" ;;
  esac
  shift
done
case " \${FAKE_GH_FAIL:-} " in *" \$n "*) echo "gh: no issue \$n" >&2; exit 1 ;; esac
state=OPEN
case " \${FAKE_GH_CLOSED:-} " in *" \$n "*) state=CLOSED ;; esac
printf '{"state":"%s","title":"%s の題 %s"}\\n' "\$state" "\$repo" "\$n"
EOF
  chmod +x "$TEST_TMPDIR/herdr" "$TEST_TMPDIR/gh"
  export HERDR_BIN="$TEST_TMPDIR/herdr"
  export GH_BIN="$TEST_TMPDIR/gh"
  export HERDR_ISSUES_ROOTS="$TEST_TMPDIR/acct"
  export HERDR_ISSUES_CACHE="$TEST_TMPDIR/cache"
  export HERDR_ISSUES_NOW="$NOW"
  export HERDR_ISSUES_REPOS="$TEST_TMPDIR/repos"
  export HERDR_ISSUES_SOCKET="$TEST_TMPDIR/no-socket"
  # Relative dates count calendar days in local time; pin the zone.
  export TZ=UTC
  # Run inside herdr, these would hide whichever tab ran the tests.
  unset HERDR_PANE_ID HERDR_ISSUES_SELF
  # --once falls back to 160 columns; a test sets COLUMNS when it wants another width.
  unset COLUMNS
  CMD="$BATS_TEST_DIRNAME/../bin/herdr-issues"
}

teardown() { rm -rf "$TEST_TMPDIR"; }

# ws <workspace_id> <label>
ws() { printf '{"workspace_id":"%s","label":"%s","pane_count":1,"focused":false}' "$1" "$2"; }

# tab <tab_id> <label>: the workspace is the part of the id before ":".
tab() {
  printf '{"tab_id":"%s","workspace_id":"%s","label":"%s","focused":false,"agent_status":"idle","pane_count":1}' \
    "$1" "${1%%:*}" "$2"
}

# ag <tab_id> <agent_status> <session_id> [cwd]
ag() {
  printf '{"agent_session":{"value":"%s"},"agent_status":"%s","cwd":"%s","tab_id":"%s","workspace_id":"%s","pane_id":"%s"}' \
    "$3" "$2" "${4:-$TEST_TMPDIR}" "$1" "${1%%:*}" "${1%%:*}:p$3"
}

# state <workspaces> <tabs> <agents>: comma-joined objects from ws / tab / ag.
state() {
  export FAKE_WS="{\"result\":{\"workspaces\":[$1]}}"
  export FAKE_TABS="{\"result\":{\"tabs\":[$2]}}"
  export FAKE_AGENTS="{\"result\":{\"agents\":[$3]}}"
}

# repo <dir> <owner/name>: a work tree under $TEST_TMPDIR whose origin is that repo.
repo() {
  git init -q "$TEST_TMPDIR/$1"
  git -C "$TEST_TMPDIR/$1" remote add origin "https://github.com/$2.git"
}

iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%S.000Z; }
stamp() { date -r "$1" +%Y%m%d%H%M.%S; }

# u <hex>: a JSON \u escape, built at run time so no raw control character sits in this file.
u() { printf '\\u%s' "$1"; }

# rule <n>: the line of n dashes under the column headings.
rule() { printf '─%.0s' $(seq 1 "$1"); }

# tx <session_id>: that session's transcript.
tx() { printf '%s' "$TEST_TMPDIR/acct/projects/p/$1.jsonl"; }

# log_at <session_id> <age_seconds>: append a line that makes the session that old.
log_at() {
  mkdir -p "$TEST_TMPDIR/acct/projects/p"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]},"timestamp":"%s"}\n' \
    "$(iso $((NOW - $2)))" >> "$(tx "$1")"
}

# say <session_id> <content as JSON>: a user line.
say() {
  mkdir -p "$TEST_TMPDIR/acct/projects/p"
  printf '{"type":"user","message":{"role":"user","content":%s},"timestamp":"%s"}\n' \
    "$2" "$(iso $((NOW - DAY)))" >> "$(tx "$1")"
}

# reply <session_id> <text> [JSON object merged into the line]: an assistant line with that text.
reply() {
  mkdir -p "$TEST_TMPDIR/acct/projects/p"
  python3 -I -c '
import json, sys
line = {"type": "assistant", "timestamp": sys.argv[2],
        "message": {"role": "assistant", "content": [{"type": "text", "text": sys.argv[1]}]}}
if sys.argv[3]:
    line.update(json.loads(sys.argv[3]))
print(json.dumps(line, ensure_ascii=False))' "$2" "$(iso $((NOW - DAY)))" "${3:-}" >> "$(tx "$1")"
}

# order <ERE>: the matches in the output, in reading order, space-separated.
order() { printf '%s\n' "$output" | grep -oE "$1" | tr '\n' ' '; }

# board <rows> <cols> <action>...: run the live board in a pty of that size.
# Actions: wait:<text> / gone:<text> (until the screen shows / stops showing it),
# click:<text> (left click on that text), left, right, wheel:<SGR button>,
# key:<chars>, exec:<shell command>.
# Prints status=, restored= (mouse off and cursor back), frame_rows=, missed= for
# each wait that timed out or click that found nothing, then the last frame.
board() {
  python3 - "$CMD" "$@" <<'PY'
import fcntl, os, pty, re, select, shlex, struct, subprocess, sys, termios, time, unicodedata

cmd, rows, cols, actions = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4:]
pid, fd = pty.fork()
if pid == 0:
    fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    os.execv(cmd, [cmd])

out = bytearray()
missed = []


def pump(seconds):
    end = time.time() + seconds
    while time.time() < end:
        ready, _, _ = select.select([fd], [], [], max(0, end - time.time()))
        if not ready:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            return
        if not chunk:
            return
        out.extend(chunk)


def send(data):
    # The board may already be gone; that shows in status=, not as a crash here.
    try:
        os.write(fd, data)
    except OSError:
        pass


def frame():
    # The last drawn screen: everything after the last cursor-home, escapes removed.
    text = out.decode("utf-8", "replace")
    home = text.rfind("\x1b[H")
    text = text[home + 3:] if home >= 0 else text
    return re.sub(r"\x1b\[[0-9;?<]*[A-Za-z]", "", text).split("\r\n")


def width(s):
    return sum(0 if unicodedata.combining(c) else
               2 if unicodedata.east_asian_width(c) in ("W", "F") else 1 for c in s)


def until(test):
    end = time.time() + 10
    while time.time() < end:
        if test(frame()):
            pump(0.3)
            return True
        pump(0.1)
    return False


for action in actions:
    kind, _, arg = action.partition(":")
    if kind == "wait":
        if not until(lambda f: any(arg in line for line in f)):
            missed.append(action)
    elif kind == "gone":
        if not until(lambda f: not any(arg in line for line in f)):
            missed.append(action)
    elif kind == "click":
        hit = next(((i, line) for i, line in enumerate(frame()) if arg in line), None)
        if hit is None:
            missed.append(action)
            continue
        y, x = hit[0] + 1, width(hit[1][:hit[1].index(arg)]) + 1
        send(b"\x1b[<0;%d;%dM\x1b[<0;%d;%dm" % (x, y, x, y))
        pump(1.0)
    elif kind in ("left", "right"):
        send(b"\x1b[D" if kind == "left" else b"\x1b[C")
        pump(0.5)
    elif kind == "wheel":
        send(b"\x1b[<%d;10;5M" % int(arg))
        pump(0.5)
    elif kind == "key":
        send(arg.encode())
        pump(0.3)
    elif kind == "exec":
        subprocess.run(shlex.split(arg))

status = None
end = time.time() + 5
while time.time() < end:
    done, raw = os.waitpid(pid, os.WNOHANG)
    if done:
        status = os.waitstatus_to_exitcode(raw)
        break
    pump(0.1)
if status is None:
    os.kill(pid, 9)
    os.waitpid(pid, 0)
on, off = out.rfind(b"\x1b[?1000h"), out.rfind(b"\x1b[?1000l")
print("status=%s" % status)
print("restored=%d" % (0 <= on < off and b"\x1b[?25h" in out[off:]))
print("frame_rows=%d" % len(frame()))
for action in missed:
    print("missed=" + action)
print("\n".join(frame()))
PY
}

# no_missed: every wait and click of the last board run found its text.
no_missed() { [ "$(printf '%s\n' "$output" | grep -c '^missed=')" -eq 0 ]; }

@test "最後の見出しの札で状態を決める" {
  state "$(ws w1 🤖dots)" \
    "$(tab w1:t1 alpha),$(tab w1:t2 beta),$(tab w1:t3 gamma),$(tab w1:t4 delta),$(tab w1:t5 epsilon)" \
    "$(ag w1:t1 idle s1),$(ag w1:t2 idle s2),$(ag w1:t3 idle s3),$(ag w1:t4 idle s4),$(ag w1:t5 idle s5)"
  reply s1 '## 【要判断】 [a] 方針を選んでほしい'
  reply s2 '## 【失敗】 [b] テストが通らない'
  reply s3 '## 【完了】 [c] 直して push した'
  reply s4 '## 【回答】 [d] 原因は設定の読み順'
  for i in 1 2 3 4 5; do log_at "s$i" $((i * 60)); done
  run "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "▶ alpha あなたの番  1分前"
  printf '%s\n' "$output" | grep -qxF "▶ beta 要対応  2分前"
  printf '%s\n' "$output" | grep -qxF "✓ gamma 完了  3分前"
  printf '%s\n' "$output" | grep -qxF "  delta 回答済み  4分前"
  printf '%s\n' "$output" | grep -qxF "  epsilon 待機  5分前"
}

@test "herdr の作業中と返事待ちは札より優先する" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha),$(tab w1:t2 beta)" \
    "$(ag w1:t1 working s1),$(ag w1:t2 blocked s2)"
  reply s1 '## 【完了】 [a] 終えた'
  reply s2 '## 【回答】 [b] 答えた'
  log_at s1 60
  log_at s2 120
  run "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "● alpha 作業中  1分前"
  printf '%s\n' "$output" | grep -qxF "▶ beta あなたの番  2分前"
}

@test "herdr の done は札の状態に未読の印を足す" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha),$(tab w1:t2 beta)" "$(ag w1:t1 done s1),$(ag w1:t2 done s2)"
  reply s1 '## 【完了】 [a] 終えた'
  log_at s1 60
  log_at s2 120
  run "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "✓ alpha 完了 未読  1分前"
  printf '%s\n' "$output" | grep -qxF "  beta 待機 未読  2分前"
}

@test "見出しの結論を概要にし、無ければタブ名の残りと issue タイトルに戻る" {
  repo ra o/a
  state "$(ws w1 🤖app)" "$(tab w1:t1 '#12 ログイン修正'),$(tab w1:t2 '#13 画面調整')" \
    "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra"),$(ag w1:t2 idle s2 "$TEST_TMPDIR/ra")"
  reply s1 '## 【完了】 [ログイン] `bin/login` を直して push した'
  log_at s1 60
  log_at s2 120
  run "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "  bin/login を直して push した"
  printf '%s\n' "$output" | grep -qxF "  画面調整 — o/a の題 13"
}

@test "1 件は状態の行と概要の行で書き、件の間を空ける" {
  repo ra o/a
  state "$(ws w1 🤖app)" "$(tab w1:t1 '#12 ログイン修正'),$(tab w1:t2 '#13 画面調整')" \
    "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra"),$(ag w1:t2 working s2 "$TEST_TMPDIR/ra")"
  reply s1 $'作業の報告です\n\n## 【要判断】 [ログイン] ログイン画面の修正方針を決めてほしい\n\n本文'
  log_at s1 300
  log_at s2 600
  run env COLUMNS=50 "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'app (2)\n%s\n▶ #12 あなたの番  5分前\n  ログイン画面の修正方針を決めてほしい\n\n● #13 作業中  10分前\n  画面調整 — o/a の題 13' "$(rule 47)")" ]
}

@test "見出しは最後に見出しを持つ返答から取り、利用者の発言やサブエージェントは見ない" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha)" "$(ag w1:t1 idle s1)"
  reply s1 '## 【要判断】 [a] この結論が出る'
  reply s1 '途中経過だけの返答'
  say s1 '"## 【完了】 [x] 利用者が貼った見出し"'
  reply s1 '## 【完了】 [x] サブエージェントの見出し' '{"isSidechain": true}'
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "▶ alpha あなたの番  1分前"
  printf '%s\n' "$output" | grep -qxF "  この結論が出る"
  [ "$(printf '%s\n' "$output" | grep -cE '利用者が貼った|サブエージェント')" -eq 0 ]
}

@test "2 MB より前の見出しは使わない" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha)" "$(ag w1:t1 idle s1)"
  reply s1 '## 【要判断】 [a] 遠すぎて見えない結論'
  {
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"'
    head -c 2200000 /dev/zero | tr '\0' x
    printf '"}]},"timestamp":"%s"}\n' "$(iso $((NOW - 120)))"
  } >> "$(tx s1)"
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "  alpha 待機  1分前"
  [ "$(printf '%s\n' "$output" | grep -cF '遠すぎて')" -eq 0 ]
}

@test "利用者の依頼文は概要に出さない" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha)" "$(ag w1:t1 idle s1)"
  say s1 '"テストが落ちる原因を調べて直してほしい"'
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'dots (1)\n%s\n  alpha 待機  1分前' "$(rule 157)")" ]
}

@test "タブ名の絵文字や記号は出さない" {
  repo ra o/a
  state "$(ws w1 🤖app)" "$(tab w1:t1 '2499 🥉 📤'),$(tab w1:t2 'final-judge 新設 🔥'),$(tab w1:t3 '★整理 ✅')" \
    "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra"),$(ag w1:t2 idle s2),$(ag w1:t3 idle s3)"
  log_at s1 60
  log_at s2 120
  log_at s3 180
  run "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "  #2499 待機  1分前"
  printf '%s\n' "$output" | grep -qxF "  o/a の題 2499"
  printf '%s\n' "$output" | grep -qxF "  final-judge 新設 待機  2分前"
  printf '%s\n' "$output" | grep -qxF "  整理 待機  3分前"
  for mark in 🥉 📤 🔥 ★ ✅; do
    [ "$(printf '%s\n' "$output" | grep -cF "$mark")" -eq 0 ]
  done
}

@test "closed の issue は完了・回答済み・待機なら片付け候補になる" {
  repo ra o/a
  export FAKE_GH_CLOSED="13 14 15"
  state "$(ws w1 🤖app)" "$(tab w1:t1 '#13 a'),$(tab w1:t2 '#14 b'),$(tab w1:t3 '#15 c')" \
    "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra"),$(ag w1:t2 idle s2 "$TEST_TMPDIR/ra"),$(ag w1:t3 idle s3 "$TEST_TMPDIR/ra")"
  reply s1 '## 【完了】 [a] 終えた'
  reply s2 '## 【回答】 [b] 答えた'
  log_at s1 60
  log_at s2 120
  log_at s3 180
  run "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "  #13 片付け候補  1分前"
  printf '%s\n' "$output" | grep -qxF "  #14 片付け候補  2分前"
  printf '%s\n' "$output" | grep -qxF "  #15 片付け候補  3分前"
}

@test "closed でもあなたの番・要対応・作業中・未読はそのまま出す" {
  repo ra o/a
  export FAKE_GH_CLOSED="13 14 15 16"
  state "$(ws w1 🤖app)" "$(tab w1:t1 '#13 a'),$(tab w1:t2 '#14 b'),$(tab w1:t3 '#15 c'),$(tab w1:t4 '#16 d')" \
    "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra"),$(ag w1:t2 idle s2 "$TEST_TMPDIR/ra"),$(ag w1:t3 working s3 "$TEST_TMPDIR/ra"),$(ag w1:t4 done s4 "$TEST_TMPDIR/ra")"
  reply s1 '## 【要判断】 [a] 決めてほしい'
  reply s2 '## 【失敗】 [b] 落ちた'
  reply s4 '## 【完了】 [d] 終えた'
  for i in 1 2 3 4; do log_at "s$i" $((i * 60)); done
  run "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "▶ #13 あなたの番  1分前"
  printf '%s\n' "$output" | grep -qxF "▶ #14 要対応  2分前"
  printf '%s\n' "$output" | grep -qxF "● #15 作業中  3分前"
  printf '%s\n' "$output" | grep -qxF "✓ #16 完了 未読  4分前"
}

@test "リポジトリごとの列に分け、列の見出しに件数を出す" {
  state "$(ws w1 🤖app),$(ws w2 🤖lib)" "$(tab w1:t1 alpha),$(tab w1:t2 beta),$(tab w2:t1 gamma)" \
    "$(ag w1:t1 idle s1),$(ag w1:t2 idle s2),$(ag w2:t1 idle s3)"
  log_at s1 60
  log_at s2 120
  log_at s3 180
  run "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | head -n 1 | grep -qF "app (2)"
  printf '%s\n' "$output" | head -n 1 | grep -qF "lib (1)"
  printf '%s\n' "$output" | grep -F "alpha 待機" | grep -F "│" | grep -qF "gamma 待機"
  [ "$(order 'alpha|beta|gamma')" = "alpha gamma beta " ]
}

@test "列はあなたの番と要対応の多い順、同じなら最近動いた順に並べる" {
  state "$(ws w1 aaa),$(ws w2 bbb),$(ws w3 ccc),$(ws w4 ddd)" \
    "$(tab w1:t1 a1),$(tab w2:t1 b1),$(tab w2:t2 b2),$(tab w3:t1 c1),$(tab w4:t1 d1)" \
    "$(ag w1:t1 idle s1),$(ag w2:t1 idle s2),$(ag w2:t2 blocked s3),$(ag w3:t1 idle s4),$(ag w4:t1 idle s5)"
  reply s1 '## 【要判断】 [a] 決めてほしい'
  reply s2 '## 【失敗】 [b] 落ちた'
  log_at s1 3600
  log_at s2 7200
  log_at s3 7300
  log_at s4 60
  log_at s5 600
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | head -n 1 | grep -oE 'aaa|bbb|ccc|ddd' | tr '\n' ' ')" = "bbb aaa ccc ddd " ]
}

@test "列の中はあなたの番・要対応、作業中、完了、片付け候補、回答済み・待機の順で、同じなら新しい順" {
  repo ra o/a
  export FAKE_GH_CLOSED=13
  state "$(ws w1 🤖app)" \
    "$(tab w1:t1 alpha),$(tab w1:t2 beta),$(tab w1:t3 gamma),$(tab w1:t4 delta),$(tab w1:t5 epsilon),$(tab w1:t6 zeta),$(tab w1:t7 '#13 x')" \
    "$(ag w1:t1 idle s1),$(ag w1:t2 idle s2),$(ag w1:t3 working s3),$(ag w1:t4 idle s4),$(ag w1:t5 idle s5),$(ag w1:t6 idle s6),$(ag w1:t7 idle s7 "$TEST_TMPDIR/ra")"
  reply s1 '## 【回答】 [a] 答えた'
  reply s2 '## 【完了】 [b] 終えた'
  reply s4 '## 【要判断】 [d] 決めてほしい'
  reply s5 '## 【失敗】 [e] 落ちた'
  reply s7 '## 【完了】 [g] 閉じた'
  log_at s1 60
  log_at s2 120
  log_at s3 180
  log_at s4 3600
  log_at s5 600
  log_at s6 30
  log_at s7 90
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(order 'alpha|beta|gamma|delta|epsilon|zeta|#13')" = "epsilon delta gamma beta #13 zeta alpha " ]
}

@test "長い概要は 2 行で折り返し、残りは … にする" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha)" "$(ag w1:t1 idle s1)"
  reply s1 "## 【完了】 [a] $(printf 'あ%.0s' $(seq 1 40))"
  log_at s1 60
  run env COLUMNS=40 "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "  $(printf 'あ%.0s' $(seq 1 17))"
  printf '%s\n' "$output" | grep -qxF "  $(printf 'あ%.0s' $(seq 1 17))…"
  [ "$(printf '%s\n' "$output" | grep -cF 'あ')" -eq 2 ]
}

@test "列は 32 桁以上の幅で画面に入るだけ並べ、残りは次の段に出す" {
  state "$(ws w1 aaa),$(ws w2 bbb),$(ws w3 ccc),$(ws w4 ddd)" \
    "$(tab w1:t1 a1),$(tab w2:t1 b1),$(tab w3:t1 c1),$(tab w4:t1 d1)" \
    "$(ag w1:t1 idle s1),$(ag w2:t1 idle s2),$(ag w3:t1 idle s3),$(ag w4:t1 idle s4)"
  for i in 1 2 3 4; do log_at "s$i" $((i * 60)); done
  run env COLUMNS=100 "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | head -n 1)" = "$(printf '%-30s │ %-30s │ %s' 'aaa (1)' 'bbb (1)' 'ccc (1)')" ]
  [ "$(printf '%s\n' "$output" | grep -F 'ddd (1)')" = "ddd (1)" ]
  # 95 holds two 32-wide columns, not three: two bands of two, 47 wide each.
  run env COLUMNS=95 "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | head -n 1)" = "$(printf '%-44s │ %s' 'aaa (1)' 'bbb (1)')" ]
  printf '%s\n' "$output" | grep -qxF "$(printf '%-44s │ %s' 'ccc (1)' 'ddd (1)')"
  # Narrower than 32, a column still gets 32.
  run env COLUMNS=20 "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -cxF "$(rule 29)")" -eq 4 ]
}

@test "--once は COLUMNS が無ければ 160 桁として並べる" {
  state "$(ws w1 aaa),$(ws w2 bbb),$(ws w3 ccc),$(ws w4 ddd),$(ws w5 eee),$(ws w6 fff)" \
    "$(tab w1:t1 a1),$(tab w2:t1 b1),$(tab w3:t1 c1),$(tab w4:t1 d1),$(tab w5:t1 e1),$(tab w6:t1 f1)" \
    "$(ag w1:t1 idle s1),$(ag w2:t1 idle s2),$(ag w3:t1 idle s3),$(ag w4:t1 idle s4),$(ag w5:t1 idle s5),$(ag w6:t1 idle s6)"
  for i in 1 2 3 4 5 6; do log_at "s$i" $((i * 60)); done
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | head -n 1 | grep -o '│' | grep -c .)" -eq 4 ]
  [ "$(printf '%s\n' "$output" | head -n 1 | awk '{print index($0, "│")}')" -eq 31 ]
  [ "$(printf '%s\n' "$output" | grep -F 'fff (1)')" = "fff (1)" ]
}

@test "14 日より前は最後の行で 放置 N 件 にまとめる" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha),$(tab w1:t2 beta),$(tab w1:t3 gamma),$(tab w1:t4 delta)" \
    "$(ag w1:t1 idle s1),$(ag w1:t2 blocked s2),$(ag w1:t3 idle s3),$(ag w1:t4 idle s4)"
  log_at s1 "$DAY"
  log_at s2 $((14 * DAY + 1))
  log_at s3 $((14 * DAY))
  log_at s4 $((30 * DAY))
  run "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | head -n 1 | grep -qxF "dots (2)"
  printf '%s\n' "$output" | grep -qxF "  alpha 待機  昨日"
  printf '%s\n' "$output" | grep -qxF "  gamma 待機  14日前"
  [ "$(printf '%s\n' "$output" | grep -cE 'beta|delta')" -eq 0 ]
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "放置 2 件" ]
}

@test "番号ありはタブ名の残りと issue タイトルを並べて概要にする" {
  repo ra o/a
  state "$(ws w1 🤖app)" "$(tab w1:t1 '#12 ログイン修正')" "$(ag w1:t1 working s1 "$TEST_TMPDIR/ra")"
  log_at s1 120
  run "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "● #12 作業中  2分前"
  printf '%s\n' "$output" | grep -qxF "  ログイン修正 — o/a の題 12"
  [ "$(cat "$TEST_TMPDIR/gh-calls")" = "issue view 12 --repo o/a --json title,state" ]
}

@test "remote が無ければワークスペース名の対応表からリポジトリを決める" {
  mkdir -p "$TEST_TMPDIR/plain"
  printf '%s\n' '# workspace  owner/repo' 'app  o/mapped' 'bad' > "$HERDR_ISSUES_REPOS"
  state "$(ws w1 🤖app),$(ws w2 other)" \
    "$(tab w1:t1 '2413 🔥'),$(tab w2:t1 '#7 x')" \
    "$(ag w1:t1 idle s1 "$TEST_TMPDIR/plain"),$(ag w2:t1 idle s2 "$TEST_TMPDIR/plain")"
  log_at s1 60
  log_at s2 120
  run env COLUMNS=40 "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "  o/mapped の題 2413"
  printf '%s\n' "$output" | grep -qxF "  x"
  [ "$(cat "$TEST_TMPDIR/gh-calls")" = "issue view 2413 --repo o/mapped --json title,state" ]
}

@test "remote があれば対応表より remote を使う" {
  repo ra o/a
  printf '%s\n' 'app  o/mapped' > "$HERDR_ISSUES_REPOS"
  state "$(ws w1 🤖app)" "$(tab w1:t1 '#12 x')" "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra")"
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/gh-calls")" = "issue view 12 --repo o/a --json title,state" ]
}

@test "タブ名の #番号 と、先頭か単独の 2〜5 桁だけを issue 番号として読む" {
  state "$(ws w1 🤖dots)" \
    "$(tab w1:t1 '#304 引数上書き防止'),$(tab w1:t2 'jpu 管理テーブル化 #182'),$(tab w1:t3 '2386 ✅'),$(tab w1:t4 '2499 🥉 📤'),$(tab w1:t5 debug2),$(tab w1:t6 1),$(tab w1:t7 'v2 移行'),$(tab w1:t8 123456)" \
    "$(ag w1:t1 idle s1),$(ag w1:t2 idle s2),$(ag w1:t3 idle s3),$(ag w1:t4 idle s4),$(ag w1:t5 idle s5),$(ag w1:t6 idle s6),$(ag w1:t7 idle s7),$(ag w1:t8 idle s8)"
  for i in 1 2 3 4 5 6 7 8; do log_at "s$i" $((i * 60)); done
  run "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "  #304 待機  1分前"
  printf '%s\n' "$output" | grep -qxF "  #182 待機  2分前"
  printf '%s\n' "$output" | grep -qxF "  #2386 待機  3分前"
  printf '%s\n' "$output" | grep -qxF "  #2499 待機  4分前"
  printf '%s\n' "$output" | grep -qxF "  debug2 待機  5分前"
  printf '%s\n' "$output" | grep -qxF "  1 待機  6分前"
  printf '%s\n' "$output" | grep -qxF "  v2 移行 待機  7分前"
  printf '%s\n' "$output" | grep -qxF "  123456 待機  8分前"
  # No repository behind these tabs, so gh is never asked.
  [ ! -e "$TEST_TMPDIR/gh-calls" ]
}

@test "同じ issue のタブは 1 件にまとめる" {
  repo ra o/a
  state "$(ws w1 🤖app)" "$(tab w1:t1 '#12 前半'),$(tab w1:t2 '#12 後半')" \
    "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra"),$(ag w1:t2 idle s2 "$TEST_TMPDIR/ra")"
  log_at s1 3600
  log_at s2 300
  run "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | head -n 1 | grep -qxF "app (1)"
  printf '%s\n' "$output" | grep -qxF "  #12 (2タブ) 待機  5分前"
  printf '%s\n' "$output" | grep -qxF "  後半 — o/a の題 12"
  [ "$(cat "$TEST_TMPDIR/gh-calls")" = "issue view 12 --repo o/a --json title,state" ]
}

@test "別リポジトリの同じ番号はまとめない" {
  repo ra o/a
  repo rb o/b
  state "$(ws w1 🤖app),$(ws w2 🤖lib)" "$(tab w1:t1 '#12 a'),$(tab w2:t1 '#12 b')" \
    "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra"),$(ag w2:t1 idle s2 "$TEST_TMPDIR/rb")"
  log_at s1 300
  log_at s2 600
  run "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "a — o/a の題 12"
  printf '%s\n' "$output" | grep -qF "b — o/b の題 12"
  [ "$(printf '%s\n' "$output" | grep -cF '(2タブ)')" -eq 0 ]
}

@test "一覧自身のタブは出さない" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha),$(tab w1:t2 board)" "$(ag w1:t1 idle s1),$(ag w1:t2 idle s2)"
  log_at s1 60
  log_at s2 120
  run env HERDR_ISSUES_SELF=w1:t2 "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(order 'alpha|board')" = "alpha " ]
  # Without the override it is the tab holding $HERDR_PANE_ID.
  export FAKE_PANE_ID=w1:p9
  export FAKE_PANE='{"result":{"pane":{"pane_id":"w1:p9","tab_id":"w1:t2"}}}'
  run env HERDR_PANE_ID=w1:p9 "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(order 'alpha|board')" = "alpha " ]
  # A pane herdr does not know hides nothing.
  run env HERDR_PANE_ID=w1:p8 "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(order 'alpha|board')" = "alpha board " ]
}

@test "エージェントのいないタブは出さない" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha),$(tab w1:t2 terminal)" "$(ag w1:t1 idle s1)"
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(order 'alpha|terminal')" = "alpha " ]
}

@test "会話ログの最後の行が途中で切れていれば最終対応は − にして件は出す" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha),$(tab w1:t2 beta)" "$(ag w1:t1 idle s1),$(ag w1:t2 idle s2)"
  log_at s1 600
  printf '{"type":"assistant","timestamp":"%s","message":{"te' "$(iso $((NOW - 60)))" >> "$(tx s1)"
  log_at s2 300
  run "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "  beta 待機  5分前"
  printf '%s\n' "$output" | grep -qxF "  alpha 待機  −"
  [ "$(order 'alpha|beta')" = "beta alpha " ]
}

@test "状態の分からないエージェントは待機として出す" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha)" "$(ag w1:t1 unknown s1)"
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "  alpha 待機  1分前"
}

@test "gh が失敗しても一覧を出し、概要はタブ名の残りにする" {
  repo ra o/a
  state "$(ws w1 🤖app)" "$(tab w1:t1 '#12 ログイン修正'),$(tab w1:t2 '#13 画面調整')" \
    "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra"),$(ag w1:t2 idle s2 "$TEST_TMPDIR/ra")"
  log_at s1 60
  log_at s2 120
  run env FAKE_GH_FAIL=12 "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "  ログイン修正"
  printf '%s\n' "$output" | grep -qxF "  画面調整 — o/a の題 13"
  run env GH_BIN="$TEST_TMPDIR/missing" HERDR_ISSUES_CACHE="$TEST_TMPDIR/cache2" "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "  ログイン修正"
  printf '%s\n' "$output" | grep -qxF "  画面調整"
}

@test "gh の失敗はキャッシュせず次の実行で引き直す" {
  repo ra o/a
  state "$(ws w1 🤖app)" "$(tab w1:t1 '#12 ログイン修正')" "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra")"
  log_at s1 60
  run env FAKE_GH_FAIL=12 "$CMD" --once
  [ "$status" -eq 0 ]
  run "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "  ログイン修正 — o/a の題 12"
}

@test "gh の結果をキャッシュし 2 回目は呼ばない" {
  repo ra o/a
  state "$(ws w1 🤖app)" "$(tab w1:t1 '#12 ログイン修正')" "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra")"
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  first="$output"
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
  [ "$(cat "$TEST_TMPDIR/gh-calls")" = "issue view 12 --repo o/a --json title,state" ]
  [ -f "$TEST_TMPDIR/cache/o_a_12.json" ]
}

@test "10 分より古いキャッシュは引き直す" {
  repo ra o/a
  state "$(ws w1 🤖app)" "$(tab w1:t1 '#12 ログイン修正')" "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra")"
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  touch -t "$(stamp $(($(date +%s) - 601)))" "$TEST_TMPDIR/cache/o_a_12.json"
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(grep -c . "$TEST_TMPDIR/gh-calls")" -eq 2 ]
}

@test "ラベル・ワークスペース名・見出しの制御文字は出さない" {
  state "$(ws w1 "🤖do$(u 001b)[2Jts")" "$(tab w1:t1 "x$(u 001b)]0;evil$(u 0007)y$(u 202e)z")" "$(ag w1:t1 idle s1)"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"## 【完了】 [a] %s[31m赤い文字で書いた結論"}]},"timestamp":"%s"}\n' \
    "$(u 001b)" "$(iso $((NOW - DAY)))" > "$(mkdir -p "$TEST_TMPDIR/acct/projects/p" && tx s1)"
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | tr -d '\033\007')" = "$output" ]
  # U+202E reverses the text after it on screen.
  [ "$(printf '%s\n' "$output" | grep -cF "$(printf '\342\200\256')")" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "赤い文字で書いた結論"
}

@test "不正な引数は使い方を出して 2 で終わる" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha)" "$(ag w1:t1 idle s1)"
  for args in "--bogus" "--once extra" "extra" "-h"; do
    # Unquoted on purpose: each entry is split into its words.
    run --separate-stderr "$CMD" $args
    echo "args=$args"
    [ "$status" -eq 2 ]
    [ -z "$output" ]
    printf '%s' "$stderr" | grep -qF "usage: herdr-issues [--once | --jump]"
  done
  [ ! -e "$TEST_TMPDIR/calls" ]
}

@test "herdr が無い・状態を読めなければ何もせず 0 で終わる" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha)" "$(ag w1:t1 idle s1)"
  log_at s1 60
  run --separate-stderr env HERDR_BIN="$TEST_TMPDIR/missing" "$CMD" --once
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  printf '%s' "$stderr" | grep -qF "herdr-issues: herdr not found"
  run --separate-stderr env FAKE_HERDR_EXIT=1 "$CMD" --once
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  printf '%s' "$stderr" | grep -qF "herdr-issues:"
  for broken in "not json" '[]' '{"result":{}}' '{"result":{"tabs":"x","agents":"x","workspaces":"x"}}'; do
    for var in FAKE_WS FAKE_TABS FAKE_AGENTS; do
      run --separate-stderr env "$var=$broken" "$CMD" --once
      echo "$var=$broken"
      [ "$status" -eq 0 ]
      [ -z "$output" ]
    done
  done
  [ ! -e "$TEST_TMPDIR/calls" ]
}

@test "端末でなければ --once を使うよう促して 2 で終わる" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha)" "$(ag w1:t1 idle s1)"
  run --separate-stderr "$CMD"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  printf '%s' "$stderr" | grep -qF -- "--once"
  [ ! -e "$TEST_TMPDIR/calls" ]
}

@test "端末ではクリックした件のタブへ移り、q で端末を元に戻す" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha),$(tab w1:t2 beta),$(tab w1:t3 gamma)" \
    "$(ag w1:t1 idle s1),$(ag w1:t2 idle s2),$(ag w1:t3 idle s3)"
  reply s2 '## 【完了】 [b] ベータの結論'
  log_at s1 60
  log_at s2 120
  log_at s3 180
  run board 24 100 wait:gamma click:ベータの結論 key:q
  [ "${lines[0]}" = "status=0" ]
  [ "${lines[1]}" = "restored=1" ]
  no_missed
  [ "$(cat "$TEST_TMPDIR/calls")" = "tab focus w1:t2" ]
}

# four <tabs-or-empty>: four one-tab repositories aaa..ddd, newest first.
four() {
  state "$(ws w1 aaa),$(ws w2 bbb),$(ws w3 ccc),$(ws w4 ddd)" \
    "$(tab w1:t1 alpha),$(tab w2:t1 beta),$(tab w3:t1 gamma),$(tab w4:t1 delta)" \
    "$(ag w1:t1 idle s1),$(ag w2:t1 idle s2),$(ag w3:t1 idle s3),$(ag w4:t1 idle s4)"
  for i in 1 2 3 4; do log_at "s$i" $((i * 60)); done
}

@test "← → とホイールで列を 1 つずつ動かし、隠れた列の数を出す" {
  four
  # 70 columns hold two 32-wide columns: aaa and bbb show, ccc and ddd hide.
  run board 24 70 "wait:2 列 ▶" right "wait:◀ 1 列" "wait:1 列 ▶" "wheel:67" "wait:◀ 2 列" \
    "wheel:68" "wait:◀ 1 列" "wheel:66" "gone:◀" "wheel:69" "wait:◀ 1 列" left "gone:◀" key:q
  [ "${lines[0]}" = "status=0" ]
  no_missed
  printf '%s\n' "$output" | grep -qF "aaa (1)"
  printf '%s\n' "$output" | grep -qF "2 列 ▶"
}

@test "列を動かした後のクリックは見えている列のタブへ移る" {
  four
  run board 24 70 "wait:2 列 ▶" right "wait:◀ 1 列" click:gamma key:q
  [ "${lines[0]}" = "status=0" ]
  no_missed
  [ "$(cat "$TEST_TMPDIR/calls")" = "tab focus w3:t1" ]
}

@test "列が減ったら動かした位置を詰める" {
  four
  printf '%s' "$FAKE_TABS" > "$TEST_TMPDIR/tabs.json"
  export FAKE_TABS_FILE="$TEST_TMPDIR/tabs.json"
  printf '{"result":{"tabs":[%s,%s]}}' "$(tab w1:t1 alpha)" "$(tab w2:t1 beta)" > "$TEST_TMPDIR/two.json"
  run board 24 70 "wait:2 列 ▶" right right "wait:◀ 2 列" \
    "exec:cp '$TEST_TMPDIR/two.json' '$TEST_TMPDIR/tabs.json'" "gone:◀" key:q
  [ "${lines[0]}" = "status=0" ]
  no_missed
  printf '%s\n' "$output" | grep -qF "aaa (1)"
  printf '%s\n' "$output" | grep -qF "bbb (1)"
}

@test "画面に収まらない件は列ごとに…ほか N 件にまとめ、その行はクリックしても移らない" {
  state "$(ws w1 🤖dots)" \
    "$(tab w1:t1 alpha),$(tab w1:t2 beta),$(tab w1:t3 gamma),$(tab w1:t4 delta),$(tab w1:t5 epsilon),$(tab w1:t6 zeta)" \
    "$(ag w1:t1 idle s1),$(ag w1:t2 idle s2),$(ag w1:t3 idle s3),$(ag w1:t4 idle s4),$(ag w1:t5 idle s5),$(ag w1:t6 idle s6)"
  for i in 1 2 3 4 5 6; do log_at "s$i" $((i * 60)); done
  run board 10 100 "wait:…ほか 4 件" "click:…ほか" key:q
  [ "${lines[0]}" = "status=0" ]
  [ "${lines[1]}" = "restored=1" ]
  no_missed
  [ "$(printf '%s\n' "${lines[2]}" | cut -d= -f2)" -le 10 ]
  printf '%s\n' "$output" | grep -qF "beta 待機"
  [ "$(printf '%s\n' "$output" | grep -cF gamma)" -eq 0 ]
  [ ! -e "$TEST_TMPDIR/calls" ]
}

@test "まとめた件のクリックは、状態を決めたタブか最も新しいタブへ移る" {
  repo ra o/a
  state "$(ws w1 🤖app)" \
    "$(tab w1:t1 '#12 前半'),$(tab w1:t2 '#12 後半'),$(tab w1:t3 '#13 前半'),$(tab w1:t4 '#13 後半')" \
    "$(ag w1:t1 blocked s1 "$TEST_TMPDIR/ra"),$(ag w1:t2 idle s2 "$TEST_TMPDIR/ra"),$(ag w1:t3 idle s3 "$TEST_TMPDIR/ra"),$(ag w1:t4 idle s4 "$TEST_TMPDIR/ra")"
  log_at s1 $((2 * DAY))
  log_at s2 300
  log_at s3 3600
  log_at s4 600
  run board 24 100 "wait:#13 (2タブ)" "click:#12 (2タブ)" "click:#13 (2タブ)" key:q
  [ "${lines[0]}" = "status=0" ]
  no_missed
  [ "$(cat "$TEST_TMPDIR/calls")" = "$(printf 'tab focus w1:t1\ntab focus w1:t4')" ]
}

board_ws() { printf '{"result":{"workspaces":[%s]}}' "$1"; }
board_proc() {
  printf '{"result":{"process_info":{"foreground_processes":[{"argv":["%s","-I"]}]}}}' "$1"
}

@test "--jump: 一覧のスペースが無ければ作って一覧を起動し、そこへ移る" {
  export FAKE_WS="$(board_ws "$(ws w1 🤖app)")"
  export FAKE_CREATE='{"result":{"root_pane":{"pane_id":"wB:p1"},"workspace":{"workspace_id":"wB"}}}'
  run "$CMD" --jump
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$TEST_TMPDIR/calls")" = "workspace create --label 📋 issue 一覧 --no-focus" ]
  [ "$(sed -n 2p "$TEST_TMPDIR/calls")" = "pane run wB:p1 $CMD" ]
  [ "$(sed -n 3p "$TEST_TMPDIR/calls")" = "workspace focus wB" ]
  [ "$(wc -l < "$TEST_TMPDIR/calls")" -eq 3 ]
}

@test "--jump: 一覧が動いていれば起動し直さず移るだけ" {
  export FAKE_WS="$(board_ws "$(ws w1 🤖app),$(ws wB '📋 issue 一覧')")"
  export FAKE_PANES='{"result":{"panes":[{"pane_id":"wB:p1"}]}}'
  export FAKE_PROC="$(board_proc herdr-issues)"
  run "$CMD" --jump
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/calls")" = "workspace focus wB" ]
}

@test "--jump: 一覧が止まっていれば起動し直す" {
  export FAKE_WS="$(board_ws "$(ws wB '📋 issue 一覧')")"
  export FAKE_PANES='{"result":{"panes":[{"pane_id":"wB:p1"}]}}'
  export FAKE_PROC="$(board_proc -zsh)"
  run "$CMD" --jump
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/calls")" = "$(printf 'pane run wB:p1 %s\nworkspace focus wB' "$CMD")" ]
}

@test "--jump: 一覧のスペースが 2 つあれば 1 つだけ残して閉じる" {
  export FAKE_WS="$(board_ws "$(ws wB '📋 issue 一覧'),$(ws w1 🤖app),$(ws wC '📋 issue 一覧')")"
  export FAKE_PANES='{"result":{"panes":[{"pane_id":"wB:p1"}]}}'
  export FAKE_PROC="$(board_proc herdr-issues)"
  run "$CMD" --jump
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/calls")" = "$(printf 'workspace close wC\nworkspace focus wB')" ]
}

@test "--jump: herdr が読めなければ何もせず 1 で終わる" {
  run env FAKE_HERDR_EXIT=1 "$CMD" --jump
  [ "$status" -eq 1 ]
  [ ! -e "$TEST_TMPDIR/calls" ]
}
