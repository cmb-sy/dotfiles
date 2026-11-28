#!/usr/bin/env bats
# herdr のタブをリポジトリごとの見出しの下に 1 件 1 行で一覧する。herdr と gh のスタブと偽の会話ログで、--once の出力と、端末でのクリックを検査する。

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
printf '{"title":"%s の題 %s"}\\n' "\$repo" "\$n"
EOF
  chmod +x "$TEST_TMPDIR/herdr" "$TEST_TMPDIR/gh"
  export HERDR_BIN="$TEST_TMPDIR/herdr"
  export GH_BIN="$TEST_TMPDIR/gh"
  export HERDR_ISSUES_ROOTS="$TEST_TMPDIR/acct"
  export HERDR_ISSUES_CACHE="$TEST_TMPDIR/cache"
  export HERDR_ISSUES_NOW="$NOW"
  export HERDR_ISSUES_REPOS="$TEST_TMPDIR/repos"
  export HERDR_ISSUES_SOCKET="$TEST_TMPDIR/no-socket"
  # The user's markers (herdr-mark), never the real set. 🌲 has no meaning.
  export HERDR_MARKS_FILE="$TEST_TMPDIR/marks.tsv"
  printf '%s\t%s\n' '📤' '返事待ち' '✅' '自分の分は完了・クローズ待ち' '🔥' '進行中' '🌲' '' > "$HERDR_MARKS_FILE"
  # Relative dates count calendar days in local time; pin the zone.
  export TZ=UTC
  # Run inside herdr, these would hide whichever tab ran the tests.
  unset HERDR_PANE_ID HERDR_ISSUES_SELF
  # --once cuts lines at 160 columns; a test sets COLUMNS when it wants another width.
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

# cells: the output with each run of 2+ spaces as "|". A row reads
# "|<issue>|<marker and meaning>|<time>|<summary>"; a row without a marker
# reads "|<issue>|<time>|<summary>".
cells() { printf '%s\n' "$output" | sed -E 's/  +/|/g'; }

# rows / heads: the row lines (indented under their heading) and the
# repository headings, in order.
rows() { printf '%s\n' "$output" | grep -E '^  [^ ]'; }
heads() { printf '%s\n' "$output" | grep -vE '^$|^ |^放置'; }

# order <ERE>: the matches in the output, in reading order, space-separated.
order() { printf '%s\n' "$output" | grep -oE "$1" | tr '\n' ' '; }

# board <rows> <cols> <action>...: run the live board in a pty of that size.
# Actions: wait:<text> / gone:<text> (until the screen shows / stops showing it),
# cursor:<text> (until the reverse-video row shows it, within 3 s), has:<bytes>
# (until the raw output holds them), click:<text> (left click on that text),
# key:<chars>, exec:<command, no shell>. In has: and key:, \e is ESC and \r is Enter.
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


ESCAPES = r"\x1b\[[0-9;?<]*[A-Za-z]"
# An SGR sequence that turns on reverse video (parameter 7).
REVERSE = re.compile(r"\x1b\[(?:[0-9]*;)*7(?:;[0-9]*)*m")


def raw_frame():
    # The last drawn screen, line by line, escapes kept.
    text = out.decode("utf-8", "replace")
    home = text.rfind("\x1b[H")
    return (text[home + 3:] if home >= 0 else text).split("\r\n")


def frame():
    return [re.sub(ESCAPES, "", line) for line in raw_frame()]


def cursor_row():
    return next((re.sub(ESCAPES, "", line) for line in raw_frame() if REVERSE.search(line)), "")


def keys(arg):
    return arg.replace("\\e", "\x1b").replace("\\r", "\r").encode()


def width(s):
    return sum(0 if unicodedata.combining(c) else
               2 if unicodedata.east_asian_width(c) in ("W", "F") else 1 for c in s)


def until(test, seconds):
    end = time.time() + seconds
    while time.time() < end and not test():
        pump(0.1)
    return test()


for action in actions:
    kind, _, arg = action.partition(":")
    if kind == "wait":
        if not until(lambda: any(arg in line for line in frame()), 10):
            missed.append(action)
        pump(0.3)
    elif kind == "gone":
        if not until(lambda: not any(arg in line for line in frame()), 10):
            missed.append(action)
    elif kind == "cursor":
        # Shorter than the 5 s redraw: a key must show at once.
        if not until(lambda: arg in cursor_row(), 3):
            missed.append(action)
    elif kind == "has":
        if not until(lambda: keys(arg) in out, 10):
            missed.append(action)
    elif kind == "exec":
        subprocess.run(shlex.split(arg))
    elif kind == "click":
        hit = next(((i, line) for i, line in enumerate(frame()) if arg in line), None)
        if hit is None:
            missed.append(action)
            continue
        y, x = hit[0] + 1, width(hit[1][:hit[1].index(arg)]) + 1
        send(b"\x1b[<0;%d;%dM\x1b[<0;%d;%dm" % (x, y, x, y))
        pump(1.0)
    elif kind == "key":
        send(keys(arg))
        pump(0.3)

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

@test "状態の列はタブ名の先頭の印とその意味だけを出す" {
  repo ra o/a
  state "$(ws w1 🤖app)" \
    "$(tab w1:t1 '📤#12 ログイン修正'),$(tab w1:t2 '✅alpha'),$(tab w1:t3 beta),$(tab w1:t4 '🔵gamma'),$(tab w1:t5 'delta 🔥')" \
    "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra"),$(ag w1:t2 idle s2),$(ag w1:t3 idle s3),$(ag w1:t4 idle s4),$(ag w1:t5 idle s5)"
  for i in 1 2 3 4 5; do log_at "s$i" $((i * 60)); done
  run "$CMD" --once
  [ "$status" -eq 0 ]
  cells | grep -qxF "|#12|📤 返事待ち|1分前|ログイン修正 — o/a の題 12"
  cells | grep -qxF "|alpha|✅ 自分の分は完了・クローズ待ち|2分前"
  # No marker from the set leads these labels, so the state stays blank.
  cells | grep -qxF "|beta|3分前"
  cells | grep -qxF "|gamma|4分前"
  cells | grep -qxF "|delta|5分前"
}

@test "どのタブにも印が無ければ状態の列を詰める" {
  state "$(ws w1 🟢app)" "$(tab w1:t1 alpha)" "$(ag w1:t1 idle s1)"
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "  alpha  1分前"
}

@test "印の意味が空なら印だけを出す" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 '🌲alpha')" "$(ag w1:t1 idle s1)"
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  cells | grep -qxF "|alpha|🌲|1分前"
}

@test "印の一覧が無くても一覧を出し、状態は空にする" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 '📤alpha')" "$(ag w1:t1 idle s1)"
  log_at s1 60
  run env HERDR_MARKS_FILE="$TEST_TMPDIR/missing.tsv" "$CMD" --once
  [ "$status" -eq 0 ]
  cells | grep -qxF "|alpha|1分前"
}

@test "herdr の状態や返答の札からは状態を出さない" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha),$(tab w1:t2 beta),$(tab w1:t3 gamma)" \
    "$(ag w1:t1 working s1),$(ag w1:t2 blocked s2),$(ag w1:t3 done s3)"
  reply s1 '## 【要判断】 [a] 決めてほしい'
  reply s2 '## 【失敗】 [b] 落ちた'
  log_at s1 60
  log_at s2 120
  log_at s3 180
  run "$CMD" --once
  [ "$status" -eq 0 ]
  cells | grep -qxF "|alpha|1分前|決めてほしい"
  cells | grep -qxF "|beta|2分前|落ちた"
  cells | grep -qxF "|gamma|3分前"
  [ "$(printf '%s\n' "$output" | grep -cE 'あなたの番|要対応|作業中|完了|回答済み|待機|片付け候補|未読|▶|●|✓')" -eq 0 ]
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
  cells | grep -qxF "|#12|1分前|bin/login を直して push した"
  cells | grep -qxF "|#13|2分前|画面調整 — o/a の題 13"
}

@test "作業名の無い見出しでも結論を概要にする" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha)" "$(ag w1:t1 idle s1)"
  reply s1 '## 【回答】 結論だけの見出し'
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  cells | grep -qxF "|alpha|1分前|結論だけの見出し"
}

@test "1 件を 1 行で書き、issue・印・最終対応・概要の列をそろえる" {
  repo ra o/a
  state "$(ws w1 🤖app)" "$(tab w1:t1 '📤#12 ログイン修正'),$(tab w1:t2 '#130 画面調整')" \
    "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra"),$(ag w1:t2 working s2 "$TEST_TMPDIR/ra")"
  reply s1 $'作業の報告です\n\n## 【要判断】 [ログイン] ログイン画面の修正方針を決めてほしい\n\n本文'
  log_at s1 300
  log_at s2 600
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' 'app' \
    '  #12   📤 返事待ち  5分前   ログイン画面の修正方針を決めてほしい' \
    "$(printf '  #130%15s10分前  画面調整 — o/a の題 130' '')")" ]
}

@test "リポジトリ名だけの見出しの下に並べ、リポジトリの間を空ける" {
  state "$(ws w1 🤖app),$(ws w2 🤖lib)" "$(tab w1:t1 alpha),$(tab w1:t2 beta),$(tab w2:t1 gamma)" \
    "$(ag w1:t1 idle s1),$(ag w1:t2 idle s2),$(ag w2:t1 idle s3)"
  log_at s1 60
  log_at s2 120
  log_at s3 180
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' 'app' '  alpha  1分前' '  beta   2分前' '' 'lib' '  gamma  3分前')" ]
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
  cells | grep -qxF "|alpha|1分前|この結論が出る"
  [ "$(printf '%s\n' "$output" | grep -cE '利用者が貼った|サブエージェント')" -eq 0 ]
}

@test "最新の見出しの結論が空なら、古い見出しの結論は使わない" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha)" "$(ag w1:t1 idle s1)"
  reply s1 '## 【完了】 [a] 古い結論'
  reply s1 '## 【完了】'
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  cells | grep -qxF "|alpha|1分前"
  [ "$(printf '%s\n' "$output" | grep -cF '古い結論')" -eq 0 ]
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
  cells | grep -qxF "|alpha|1分前"
  [ "$(printf '%s\n' "$output" | grep -cF '遠すぎて')" -eq 0 ]
}

@test "利用者の依頼文は概要に出さない" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha)" "$(ag w1:t1 idle s1)"
  say s1 '"テストが落ちる原因を調べて直してほしい"'
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' 'dots' '  alpha  1分前')" ]
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
  cells | grep -qxF "|#2499|1分前|o/a の題 2499"
  cells | grep -qxF "|final-judge 新設|2分前"
  cells | grep -qxF "|整理|3分前"
  for mark in 🥉 📤 🔥 ★ ✅; do
    [ "$(printf '%s\n' "$output" | grep -cF "$mark")" -eq 0 ]
  done
}

@test "長いタブ名は issue の列で 24 桁に切る" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 'とても長いタブの名前がここに入っていて切られる')" "$(ag w1:t1 idle s1)"
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  cells | grep -qxF "|とても長いタブの名前が…|1分前"
}

@test "リポジトリは最近動いた順に並べる" {
  state "$(ws w1 aaa),$(ws w2 bbb),$(ws w3 ccc),$(ws w4 ddd)" \
    "$(tab w1:t1 a1),$(tab w2:t1 b1),$(tab w2:t2 b2),$(tab w3:t1 c1),$(tab w4:t1 d1)" \
    "$(ag w1:t1 idle s1),$(ag w2:t1 idle s2),$(ag w2:t2 idle s3),$(ag w3:t1 idle s4),$(ag w4:t1 idle s5)"
  reply s1 '## 【要判断】 [a] 決めてほしい'
  log_at s1 3600
  log_at s2 7200
  log_at s3 60
  log_at s4 600
  log_at s5 120
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(heads | tr '\n' ' ')" = "bbb ddd ccc aaa " ]
}

@test "リポジトリの中は新しい順に並べ、印や herdr の状態では並べ替えない" {
  state "$(ws w1 🤖app)" \
    "$(tab w1:t1 '📤alpha'),$(tab w1:t2 beta),$(tab w1:t3 gamma),$(tab w1:t4 delta),$(tab w1:t5 epsilon)" \
    "$(ag w1:t1 idle s1),$(ag w1:t2 working s2),$(ag w1:t3 idle s3),$(ag w1:t4 blocked s4),$(ag w1:t5 idle s5)"
  log_at s1 600
  log_at s2 60
  log_at s4 300
  log_at s5 120
  run "$CMD" --once
  [ "$status" -eq 0 ]
  # gamma has no transcript, so its time is unknown and it goes last.
  [ "$(order 'alpha|beta|gamma|delta|epsilon')" = "beta epsilon delta alpha gamma " ]
}

@test "--once は COLUMNS の幅で、無ければ 160 桁で行を切って … を付ける" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha)" "$(ag w1:t1 idle s1)"
  reply s1 "## 【完了】 [a] $(printf 'x%.0s' $(seq 1 200))"
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  cells | grep -qxF "|alpha|1分前|$(printf 'x%.0s' $(seq 1 143))…"
  run env COLUMNS=40 "$CMD" --once
  [ "$status" -eq 0 ]
  cells | grep -qxF "|alpha|1分前|$(printf 'x%.0s' $(seq 1 23))…"
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
  [ "$(printf '%s\n' "$output" | head -n 1)" = "dots" ]
  cells | grep -qxF "|alpha|昨日"
  cells | grep -qxF "|gamma|14日前"
  [ "$(printf '%s\n' "$output" | grep -cE 'beta|delta')" -eq 0 ]
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "放置 2 件" ]
}

@test "番号ありはタブ名の残りと issue タイトルを並べて概要にする" {
  repo ra o/a
  state "$(ws w1 🤖app)" "$(tab w1:t1 '#12 ログイン修正')" "$(ag w1:t1 working s1 "$TEST_TMPDIR/ra")"
  log_at s1 120
  run "$CMD" --once
  [ "$status" -eq 0 ]
  cells | grep -qxF "|#12|2分前|ログイン修正 — o/a の題 12"
  [ "$(cat "$TEST_TMPDIR/gh-calls")" = "issue view 12 --repo o/a --json title" ]
}

@test "remote が無ければワークスペース名の対応表からリポジトリを決める" {
  mkdir -p "$TEST_TMPDIR/plain"
  printf '%s\n' '# workspace  owner/repo' 'app  o/mapped' 'bad' > "$HERDR_ISSUES_REPOS"
  state "$(ws w1 🤖app),$(ws w2 other)" \
    "$(tab w1:t1 '2413 🔥'),$(tab w2:t1 '#7 x')" \
    "$(ag w1:t1 idle s1 "$TEST_TMPDIR/plain"),$(ag w2:t1 idle s2 "$TEST_TMPDIR/plain")"
  log_at s1 60
  log_at s2 120
  run "$CMD" --once
  [ "$status" -eq 0 ]
  cells | grep -qxF "|#2413|1分前|o/mapped の題 2413"
  cells | grep -qxF "|#7|2分前|x"
  [ "$(cat "$TEST_TMPDIR/gh-calls")" = "issue view 2413 --repo o/mapped --json title" ]
}

@test "remote があれば対応表より remote を使う" {
  repo ra o/a
  printf '%s\n' 'app  o/mapped' > "$HERDR_ISSUES_REPOS"
  state "$(ws w1 🤖app)" "$(tab w1:t1 '#12 x')" "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra")"
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/gh-calls")" = "issue view 12 --repo o/a --json title" ]
}

@test "タブ名の #番号 と、先頭か単独の 2〜5 桁だけを issue 番号として読む" {
  state "$(ws w1 🤖dots)" \
    "$(tab w1:t1 '#304 引数上書き防止'),$(tab w1:t2 'jpu 管理テーブル化 #182'),$(tab w1:t3 '2386 ✅'),$(tab w1:t4 '2499 🥉 📤'),$(tab w1:t5 debug2),$(tab w1:t6 1),$(tab w1:t7 'v2 移行'),$(tab w1:t8 123456)" \
    "$(ag w1:t1 idle s1),$(ag w1:t2 idle s2),$(ag w1:t3 idle s3),$(ag w1:t4 idle s4),$(ag w1:t5 idle s5),$(ag w1:t6 idle s6),$(ag w1:t7 idle s7),$(ag w1:t8 idle s8)"
  for i in 1 2 3 4 5 6 7 8; do log_at "s$i" $((i * 60)); done
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(rows | sed -E 's/  +/|/g' | cut -d'|' -f2 | tr '\n' ',')" = "#304,#182,#2386,#2499,debug2,1,v2 移行,123456," ]
  # No repository behind these tabs, so gh is never asked.
  [ ! -e "$TEST_TMPDIR/gh-calls" ]
}

@test "先頭に印の付いたタブ名からも issue 番号を読む" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 '📤2386 x')" "$(ag w1:t1 idle s1)"
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  cells | grep -qxF "|#2386|📤 返事待ち|1分前|x"
}

@test "同じ issue のタブは 1 件にまとめる" {
  repo ra o/a
  state "$(ws w1 🤖app)" "$(tab w1:t1 '#12 前半'),$(tab w1:t2 '#12 後半')" \
    "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra"),$(ag w1:t2 idle s2 "$TEST_TMPDIR/ra")"
  log_at s1 3600
  log_at s2 300
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | head -n 1)" = "app" ]
  cells | grep -qxF "|#12 (2タブ)|5分前|後半 — o/a の題 12"
  [ "$(cat "$TEST_TMPDIR/gh-calls")" = "issue view 12 --repo o/a --json title" ]
}

@test "同じ issue のまとめでは、印の付いたタブを見せる" {
  repo ra o/a
  state "$(ws w1 🤖app)" "$(tab w1:t1 '📤#12 前半'),$(tab w1:t2 '#12 後半')" \
    "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra"),$(ag w1:t2 idle s2 "$TEST_TMPDIR/ra")"
  log_at s1 3600
  log_at s2 300
  run "$CMD" --once
  [ "$status" -eq 0 ]
  cells | grep -qxF "|#12 (2タブ)|📤 返事待ち|5分前|前半 — o/a の題 12"
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
  cells | grep -qxF "|#12|5分前|a — o/a の題 12"
  cells | grep -qxF "|#12|10分前|b — o/b の題 12"
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
  cells | grep -qxF "|beta|5分前"
  cells | grep -qxF "|alpha|−"
  [ "$(order 'alpha|beta')" = "beta alpha " ]
}

@test "gh が失敗しても一覧を出し、概要はタブ名の残りにする" {
  repo ra o/a
  state "$(ws w1 🤖app)" "$(tab w1:t1 '#12 ログイン修正'),$(tab w1:t2 '#13 画面調整')" \
    "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra"),$(ag w1:t2 idle s2 "$TEST_TMPDIR/ra")"
  log_at s1 60
  log_at s2 120
  run env FAKE_GH_FAIL=12 "$CMD" --once
  [ "$status" -eq 0 ]
  cells | grep -qxF "|#12|1分前|ログイン修正"
  cells | grep -qxF "|#13|2分前|画面調整 — o/a の題 13"
  run env GH_BIN="$TEST_TMPDIR/missing" HERDR_ISSUES_CACHE="$TEST_TMPDIR/cache2" "$CMD" --once
  [ "$status" -eq 0 ]
  cells | grep -qxF "|#12|1分前|ログイン修正"
  cells | grep -qxF "|#13|2分前|画面調整"
}

@test "gh の失敗はキャッシュせず次の実行で引き直す" {
  repo ra o/a
  state "$(ws w1 🤖app)" "$(tab w1:t1 '#12 ログイン修正')" "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra")"
  log_at s1 60
  run env FAKE_GH_FAIL=12 "$CMD" --once
  [ "$status" -eq 0 ]
  run "$CMD" --once
  [ "$status" -eq 0 ]
  cells | grep -qxF "|#12|1分前|ログイン修正 — o/a の題 12"
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
  [ "$(cat "$TEST_TMPDIR/gh-calls")" = "issue view 12 --repo o/a --json title" ]
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

@test "ラベル・ワークスペース名・見出し・印の意味の制御文字は出さない" {
  printf '%s\t%s\n' '📤' "返事$(printf '\033')[31m待ち" > "$HERDR_MARKS_FILE"
  state "$(ws w1 "🤖do$(u 001b)[2Jts")" "$(tab w1:t1 "📤x$(u 001b)]0;evil$(u 0007)y$(u 202e)z")" "$(ag w1:t1 idle s1)"
  mkdir -p "$TEST_TMPDIR/acct/projects/p"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"## 【完了】 [a] %s[31m赤い文字で書いた結論"}]},"timestamp":"%s"}\n' \
    "$(u 001b)" "$(iso $((NOW - DAY)))" > "$(tx s1)"
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | tr -d '\033\007')" = "$output" ]
  # U+202E reverses the text after it on screen.
  [ "$(printf '%s\n' "$output" | grep -cF "$(printf '\342\200\256')")" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "赤い文字で書いた結論"
  printf '%s\n' "$output" | grep -qF "📤 返事 [31m待ち"
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

@test "端末ではクリックした行のタブへ移ってカーソルもその行へ動き、q で端末を元に戻す" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha),$(tab w1:t2 beta),$(tab w1:t3 gamma)" \
    "$(ag w1:t1 idle s1),$(ag w1:t2 idle s2),$(ag w1:t3 idle s3)"
  reply s2 '## 【完了】 [b] ベータの結論'
  reply s3 '## 【回答】 [c] ガンマの結論'
  log_at s1 60
  log_at s2 120
  log_at s3 180
  # Newest first: alpha leads and holds the cursor; gamma is last.
  run board 24 100 wait:gamma cursor:alpha click:ガンマの結論 cursor:gamma key:q
  [ "${lines[0]}" = "status=0" ]
  [ "${lines[1]}" = "restored=1" ]
  no_missed
  [ "$(cat "$TEST_TMPDIR/calls")" = "tab focus w1:t3" ]
}

# two_repos: app holds alpha and beta, lib holds gamma; newest first.
two_repos() {
  state "$(ws w1 🤖app),$(ws w2 🤖lib)" "$(tab w1:t1 alpha),$(tab w1:t2 beta),$(tab w2:t1 gamma)" \
    "$(ag w1:t1 idle s1),$(ag w1:t2 idle s2),$(ag w2:t1 idle s3)"
  log_at s1 60
  log_at s2 120
  log_at s3 180
}

@test "↑↓ と j/k でカーソルを動かし、見出しや空行は飛ばして端で止まる" {
  two_repos
  run board 24 100 "wait:↑↓ で選ぶ・Enter で移動・クリックでも移動・q で終了" cursor:alpha \
    key:j cursor:beta 'key:\e[B' cursor:gamma key:j cursor:gamma \
    key:k cursor:beta 'key:\e[A' cursor:alpha key:k cursor:alpha key:q
  [ "${lines[0]}" = "status=0" ]
  no_missed
  [ ! -e "$TEST_TMPDIR/calls" ]
}

@test "Enter でカーソルの行のタブへ移る" {
  two_repos
  run board 24 100 wait:gamma cursor:alpha key:j key:j cursor:gamma 'key:\r' key:q
  [ "${lines[0]}" = "status=0" ]
  no_missed
  [ "$(cat "$TEST_TMPDIR/calls")" = "tab focus w2:t1" ]
}

@test "修飾キーつきの矢印（ESC[1;9A や ESC O B）でもカーソルが動く" {
  two_repos
  run board 24 100 wait:gamma cursor:alpha 'key:\e[1;9B' cursor:beta 'key:\eOB' cursor:gamma \
    'key:\e[1;9A' cursor:beta 'key:\eOA' cursor:alpha key:q
  [ "${lines[0]}" = "status=0" ]
  no_missed
}

@test "並びが変わってもカーソルは同じタブに付いていく" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha),$(tab w1:t2 beta),$(tab w1:t3 gamma)" \
    "$(ag w1:t1 idle s1),$(ag w1:t2 idle s2),$(ag w1:t3 idle s3)"
  log_at s1 60
  log_at s2 120
  log_at s3 180
  # gamma becomes the newest, so the order turns into gamma, alpha, beta.
  cp "$(tx s3)" "$TEST_TMPDIR/s3-new.jsonl"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]},"timestamp":"%s"}\n' \
    "$(iso $((NOW - 10)))" >> "$TEST_TMPDIR/s3-new.jsonl"
  run board 24 100 wait:gamma cursor:alpha key:j cursor:beta "exec:cp $TEST_TMPDIR/s3-new.jsonl $(tx s3)" \
    wait:たった今 cursor:beta key:q
  [ "${lines[0]}" = "status=0" ]
  no_missed
  [ "$(order 'alpha|beta|gamma')" = "gamma alpha beta " ]
}

@test "カーソルのタブが消えたら同じ位置に留まる" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha),$(tab w1:t2 beta),$(tab w1:t3 gamma)" \
    "$(ag w1:t1 idle s1),$(ag w1:t2 idle s2),$(ag w1:t3 idle s3)"
  log_at s1 60
  log_at s2 120
  log_at s3 180
  printf '%s' "$FAKE_TABS" > "$TEST_TMPDIR/tabs.json"
  export FAKE_TABS_FILE="$TEST_TMPDIR/tabs.json"
  printf '{"result":{"tabs":[%s,%s]}}' "$(tab w1:t1 alpha)" "$(tab w1:t3 gamma)" > "$TEST_TMPDIR/two.json"
  run board 24 100 wait:gamma cursor:alpha key:j cursor:beta "exec:cp $TEST_TMPDIR/two.json $TEST_TMPDIR/tabs.json" \
    gone:beta cursor:gamma key:q
  [ "${lines[0]}" = "status=0" ]
  no_missed
  [ "$(order 'alpha|beta|gamma')" = "alpha gamma " ]
}

@test "端末では見出しを画面幅いっぱいの 1 色の帯にし、上を 1 行空ける" {
  state "$(ws w1 🤖app),$(ws w2 🔥lib)" "$(tab w1:t1 alpha),$(tab w2:t1 beta)" \
    "$(ag w1:t1 idle s1),$(ag w2:t1 idle s2)"
  log_at s1 60
  log_at s2 120
  run board 24 100 wait:beta 'has:\e[1;97;48;5;24m app ' 'has:\e[1;97;48;5;24m lib ' key:q
  [ "${lines[0]}" = "status=0" ]
  no_missed
  # The bands span the screen but its spare last column.
  [ "$(printf '%s\n' "$output" | grep -E '^ (app|lib) +$' | awk '{print length($0)}' | tr '\n' ' ')" = "99 99 " ]
  printf '%s\n' "$output" | awk '/^ (app|lib) +$/ { n++; if (prev != "") bad = 1 } { prev = $0 } END { exit !(n == 2 && !bad) }'
}

@test "画面に収まらない行は…ほか N 件にまとめ、その行や見出しはクリックしても移らない" {
  state "$(ws w1 🤖dots)" \
    "$(tab w1:t1 alpha),$(tab w1:t2 beta),$(tab w1:t3 gamma),$(tab w1:t4 delta),$(tab w1:t5 epsilon),$(tab w1:t6 zeta)" \
    "$(ag w1:t1 idle s1),$(ag w1:t2 idle s2),$(ag w1:t3 idle s3),$(ag w1:t4 idle s4),$(ag w1:t5 idle s5),$(ag w1:t6 idle s6)"
  for i in 1 2 3 4 5 6; do log_at "s$i" $((i * 60)); done
  # 8 rows: the title and a gap leave 6 for the heading and the rows.
  run board 8 100 "wait:…ほか 2 件" "click:…ほか" "click:dots" key:q
  [ "${lines[0]}" = "status=0" ]
  [ "${lines[1]}" = "restored=1" ]
  [ "${lines[2]}" = "frame_rows=8" ]
  no_missed
  printf '%s\n' "$output" | grep -qF "delta"
  [ "$(printf '%s\n' "$output" | grep -cF epsilon)" -eq 0 ]
  [ ! -e "$TEST_TMPDIR/calls" ]
}

@test "まとめた件のクリックは、印の付いたタブか最も新しいタブへ移る" {
  repo ra o/a
  state "$(ws w1 🤖app)" \
    "$(tab w1:t1 '📤#12 前半'),$(tab w1:t2 '#12 後半'),$(tab w1:t3 '#13 前半'),$(tab w1:t4 '#13 後半')" \
    "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra"),$(ag w1:t2 idle s2 "$TEST_TMPDIR/ra"),$(ag w1:t3 idle s3 "$TEST_TMPDIR/ra"),$(ag w1:t4 idle s4 "$TEST_TMPDIR/ra")"
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
  [ "$(sed -n 2p "$TEST_TMPDIR/calls")" = "pane run wB:p1 $(cd "$(dirname "$CMD")" && pwd)/herdr-issues" ]
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
  [ "$(cat "$TEST_TMPDIR/calls")" = "$(printf 'pane run wB:p1 %s\nworkspace focus wB' "$(cd "$(dirname "$CMD")" && pwd)/herdr-issues")" ]
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
