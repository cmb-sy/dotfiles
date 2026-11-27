#!/usr/bin/env bats
# herdr のタブを issue ごとに一覧する。herdr と gh のスタブと偽の会話ログで、--once の出力と、端末でのクリックを検査する。

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
  "tab list") printf '%s' "\${FAKE_TABS:-}"; exit "\${FAKE_HERDR_EXIT:-0}" ;;
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

# tx <session_id>: that session's transcript.
tx() { printf '%s' "$TEST_TMPDIR/acct/projects/p/$1.jsonl"; }

# log_at <session_id> <age_seconds>: append a line that makes the session that old.
log_at() {
  mkdir -p "$TEST_TMPDIR/acct/projects/p"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]},"timestamp":"%s"}\n' \
    "$(iso $((NOW - $2)))" >> "$(tx "$1")"
}

# say <session_id> <content as JSON> [extra fields, each ending in ","]: a user line.
say() {
  mkdir -p "$TEST_TMPDIR/acct/projects/p"
  printf '{"type":"user",%s"message":{"role":"user","content":%s},"timestamp":"%s"}\n' \
    "${3:-}" "$2" "$(iso $((NOW - DAY)))" >> "$(tx "$1")"
}

# col <n>: the n-th column of every output line. Columns are split by 2+ spaces.
col() { printf '%s\n' "$output" | awk -F '  +' -v n="$1" '{print $n}'; }

# board <rows> <cols> <action>...: run the live board in a pty of that size.
# Actions: wait:<text>, click:<text> (left click on the line showing it), key:<chars>.
# Prints status=, restored= (mouse off and cursor back), frame_rows=, then the last frame.
board() {
  python3 - "$CMD" "$@" <<'PY'
import fcntl, os, pty, re, select, struct, sys, termios, time

cmd, rows, cols, actions = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4:]
pid, fd = pty.fork()
if pid == 0:
    fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    os.execv(cmd, [cmd])

out = bytearray()


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


for action in actions:
    kind, _, arg = action.partition(":")
    if kind == "wait":
        end = time.time() + 10
        while time.time() < end and not any(arg in line for line in frame()):
            pump(0.1)
        pump(0.3)
    elif kind == "click":
        row = next((i + 1 for i, line in enumerate(frame()) if arg in line), 0)
        send(b"\x1b[<0;3;%dM\x1b[<0;3;%dm" % (row, row))
        pump(1.0)
    elif kind == "key":
        send(arg.encode())
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
print("\n".join(frame()))
PY
}

@test "返事待ちと完了・未確認が先頭、その後は新しい順" {
  state "$(ws w1 🤖dots)" \
    "$(tab w1:t1 alpha),$(tab w1:t2 beta),$(tab w1:t3 gamma),$(tab w1:t4 delta),$(tab w1:t5 epsilon),$(tab w1:t6 zeta)" \
    "$(ag w1:t1 idle s1),$(ag w1:t2 blocked s2),$(ag w1:t3 working s3),$(ag w1:t4 done s4),$(ag w1:t5 idle s5),$(ag w1:t6 blocked s6)"
  log_at s1 3600
  log_at s2 $((3 * DAY))
  log_at s3 600
  log_at s4 $((DAY + 3600))
  log_at s5 30
  log_at s6 7200
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(col 5)" = "$(printf 'zeta\nbeta\ndelta\nepsilon\ngamma\nalpha')" ]
  [ "$(col 2)" = "$(printf '返事待ち\n返事待ち\n完了・未確認\n待機中\n作業中\n待機中')" ]
  [ "$(col 1)" = "$(printf '2時間前\n3日前\n昨日\nたった今\n10分前\n1時間前')" ]
  [ "$(col 4)" = "$(printf 'dots\ndots\ndots\ndots\ndots\ndots')" ]
}

@test "列は表示幅でそろえる" {
  state "$(ws w1 🤖dots),$(ws w2 🤖library)" "$(tab w1:t1 alpha),$(tab w2:t1 beta)" \
    "$(ag w1:t1 done s1),$(ag w2:t1 idle s2)"
  log_at s1 600
  log_at s2 300
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '10分前  完了・未確認  −  dots     alpha\n5分前   待機中        −  library  beta')" ]
}

@test "番号ありはタブ名の残りと issue タイトルを並べて概要にする" {
  repo ra o/a
  state "$(ws w1 🤖app)" "$(tab w1:t1 '#12 ログイン修正')" "$(ag w1:t1 working s1 "$TEST_TMPDIR/ra")"
  log_at s1 120
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$output" = "2分前  作業中  #12  app  ログイン修正 — o/a の題 12" ]
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
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(col 5)" = "$(printf '🔥 — o/mapped の題 2413\nx')" ]
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
  [ "$(col 3)" = "$(printf '#304\n#182\n#2386\n#2499\n−\n−\n−\n−')" ]
  # No repository behind these tabs, so gh is never asked.
  [ ! -e "$TEST_TMPDIR/gh-calls" ]
}

@test "closed の issue は片付け候補になる" {
  repo ra o/a
  export FAKE_GH_CLOSED=13
  state "$(ws w1 🤖app)" "$(tab w1:t1 '#13 古い修正')" "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra")"
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$output" = "1分前  片付け候補  #13  app  古い修正 — o/a の題 13" ]
}

@test "closed でも返事待ち・完了・作業中のタブは状態を変えない" {
  repo ra o/a
  export FAKE_GH_CLOSED="13 14 15"
  state "$(ws w1 🤖app)" "$(tab w1:t1 '#13 a'),$(tab w1:t2 '#14 b'),$(tab w1:t3 '#15 c')" \
    "$(ag w1:t1 blocked s1 "$TEST_TMPDIR/ra"),$(ag w1:t2 done s2 "$TEST_TMPDIR/ra"),$(ag w1:t3 working s3 "$TEST_TMPDIR/ra")"
  log_at s1 60
  log_at s2 120
  log_at s3 180
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(col 2)" = "$(printf '返事待ち\n完了・未確認\n作業中')" ]
}

@test "同じ issue のタブは 1 行にまとめる" {
  repo ra o/a
  state "$(ws w1 🤖app)" "$(tab w1:t1 '#12 前半'),$(tab w1:t2 '#12 後半')" \
    "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra"),$(ag w1:t2 idle s2 "$TEST_TMPDIR/ra")"
  log_at s1 3600
  log_at s2 300
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$output" = "5分前  待機中  #12 (2タブ)  app  後半 — o/a の題 12" ]
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
  [ "$(col 3)" = "$(printf '#12\n#12')" ]
  [ "$(col 4)" = "$(printf 'app\nlib')" ]
  [ "$(col 5)" = "$(printf 'a — o/a の題 12\nb — o/b の題 12')" ]
}

@test "14 日より前は放置 N 件にまとめる" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 a),$(tab w1:t2 b),$(tab w1:t3 c),$(tab w1:t4 d)" \
    "$(ag w1:t1 idle s1),$(ag w1:t2 blocked s2),$(ag w1:t3 idle s3),$(ag w1:t4 idle s4)"
  log_at s1 "$DAY"
  log_at s2 $((14 * DAY + 1))
  log_at s3 $((14 * DAY))
  log_at s4 $((30 * DAY))
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ "$(printf '%s\n' "$output" | head -n 2 | awk -F '  +' '{print $1 "|" $5}')" = "$(printf '昨日|a\n14日前|c')" ]
  [ "${lines[2]}" = "放置 2 件" ]
}

@test "番号なしはタブ名と最後の依頼文を概要にする（短い返事・< や [ 始まり・システム文は除く）" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 調査)" "$(ag w1:t1 idle s1)"
  say s1 '"古い依頼なのでこれは出てこないはずの文章"'
  say s1 '"テストが落ちる原因を調べて直してほしい"'
  say s1 '"<command-name>/clear</command-name> を実行した記録の行"'
  say s1 '"[Request interrupted by user for tool use]"'
  say s1 '"はい、それで進めて"'
  say s1 '[{"type":"tool_result","tool_use_id":"t1","content":"ツールの結果がここに長く書かれている"}]'
  say s1 '[{"type":"text","text":"スキルの本文がここに入っていて十分に長いテキスト"}]' '"isMeta":true,'
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$output" = "1分前  待機中  −  dots  調査  テストが落ちる原因を調べて直してほしい" ]
}

@test "貼り付けは（貼り付け）と書き、貼り付けだけの依頼は飛ばす" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 調査),$(tab w1:t2 確認)" "$(ag w1:t1 idle s1),$(ag w1:t2 idle s2)"
  say s1 '"<pasted_content id=\"1\">Traceback (most recent call last): boom</pasted_content id=\"1\">\nこのエラーの原因を調べて直してください"'
  say s2 '"ログの読み方を教えてほしいので説明をお願いします"'
  say s2 '"<pasted_content id=\"2\">とても長い貼り付けの中身がここに入る</pasted_content id=\"2\">"'
  log_at s1 60
  log_at s2 120
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(col 6)" = "$(printf '（貼り付け） このエラーの原因を調べて直してください\nログの読み方を教えてほしいので説明をお願いします')" ]
}

@test "長い依頼文は 60 文字で切って … を付ける" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 調査)" "$(ag w1:t1 idle s1)"
  say s1 "\"$(printf 'あ%.0s' $(seq 1 70))\""
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(col 6)" = "$(printf 'あ%.0s' $(seq 1 59))…" ]
}

@test "状態の分からないエージェントは待機中として出す" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha)" "$(ag w1:t1 unknown s1)"
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(col 2)" = 待機中 ]
}

@test "数字だけのタブ名は概要に出さない" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 2)" "$(ag w1:t1 idle s1)"
  say s1 '"設定ファイルの書き方を見直してほしい"'
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$output" = "1分前  待機中  −  dots  設定ファイルの書き方を見直してほしい" ]
}

@test "一覧自身のタブは出さない" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha),$(tab w1:t2 board)" "$(ag w1:t1 idle s1),$(ag w1:t2 idle s2)"
  log_at s1 60
  log_at s2 120
  run env HERDR_ISSUES_SELF=w1:t2 "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(col 5)" = alpha ]
  # Without the override it is the tab holding $HERDR_PANE_ID.
  export FAKE_PANE_ID=w1:p9
  export FAKE_PANE='{"result":{"pane":{"pane_id":"w1:p9","tab_id":"w1:t2"}}}'
  run env HERDR_PANE_ID=w1:p9 "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(col 5)" = alpha ]
  # A pane herdr does not know hides nothing.
  run env HERDR_PANE_ID=w1:p8 "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(col 5)" = "$(printf 'alpha\nboard')" ]
}

@test "エージェントのいないタブは出さない" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha),$(tab w1:t2 terminal)" "$(ag w1:t1 idle s1)"
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(col 5)" = alpha ]
}

@test "会話ログの最後の行が途中で切れていれば最終対応は − にして行は出す" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha),$(tab w1:t2 beta)" "$(ag w1:t1 idle s1),$(ag w1:t2 idle s2)"
  log_at s1 600
  printf '{"type":"assistant","timestamp":"%s","message":{"te' "$(iso $((NOW - 60)))" >> "$(tx s1)"
  log_at s2 300
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(col 1)" = "$(printf '5分前\n−')" ]
  [ "$(col 5)" = "$(printf 'beta\nalpha')" ]
}

@test "gh が失敗しても一覧を出し、概要はタブ名の残りにする" {
  repo ra o/a
  state "$(ws w1 🤖app)" "$(tab w1:t1 '#12 ログイン修正'),$(tab w1:t2 '#13 画面調整')" \
    "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra"),$(ag w1:t2 idle s2 "$TEST_TMPDIR/ra")"
  log_at s1 60
  log_at s2 120
  run env FAKE_GH_FAIL=12 "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(col 5)" = "$(printf 'ログイン修正\n画面調整 — o/a の題 13')" ]
  run env GH_BIN="$TEST_TMPDIR/missing" HERDR_ISSUES_CACHE="$TEST_TMPDIR/cache2" "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(col 5)" = "$(printf 'ログイン修正\n画面調整')" ]
}

@test "gh の失敗はキャッシュせず次の実行で引き直す" {
  repo ra o/a
  state "$(ws w1 🤖app)" "$(tab w1:t1 '#12 ログイン修正')" "$(ag w1:t1 idle s1 "$TEST_TMPDIR/ra")"
  log_at s1 60
  run env FAKE_GH_FAIL=12 "$CMD" --once
  [ "$status" -eq 0 ]
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "$(col 5)" = "ログイン修正 — o/a の題 12" ]
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

@test "ラベル・ワークスペース名・依頼文の制御文字は出さない" {
  state "$(ws w1 '🤖do\u001b[2Jts')" "$(tab w1:t1 'x\u001b]0;evil\u0007y‮z')" "$(ag w1:t1 idle s1)"
  say s1 '"\u001b[31m赤い文字で表示してほしいという依頼の文章"'
  log_at s1 60
  run "$CMD" --once
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "$(printf '%s' "$output" | tr -d '\033\007')" = "$output" ]
  # U+202E reverses the text after it on screen.
  [ "$(printf '%s\n' "$output" | grep -cF "$(printf '\342\200\256')")" -eq 0 ]
  printf '%s' "$output" | grep -qF "赤い文字で表示してほしいという依頼の文章"
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

@test "端末ではクリックした行のタブへ移り、q で端末を元に戻す" {
  state "$(ws w1 🤖dots)" "$(tab w1:t1 alpha),$(tab w1:t2 beta),$(tab w1:t3 gamma)" \
    "$(ag w1:t1 idle s1),$(ag w1:t2 idle s2),$(ag w1:t3 idle s3)"
  log_at s1 60
  log_at s2 120
  log_at s3 180
  run board 24 100 wait:gamma click:beta key:q
  [ "${lines[0]}" = "status=0" ]
  [ "${lines[1]}" = "restored=1" ]
  [ "$(cat "$TEST_TMPDIR/calls")" = "tab focus w1:t2" ]
}

@test "画面に収まらない行は…ほか N 件にまとめ、その行はクリックしても移らない" {
  state "$(ws w1 🤖dots)" \
    "$(tab w1:t1 alpha),$(tab w1:t2 beta),$(tab w1:t3 gamma),$(tab w1:t4 delta),$(tab w1:t5 epsilon),$(tab w1:t6 zeta)" \
    "$(ag w1:t1 idle s1),$(ag w1:t2 idle s2),$(ag w1:t3 idle s3),$(ag w1:t4 idle s4),$(ag w1:t5 idle s5),$(ag w1:t6 idle s6)"
  for i in 1 2 3 4 5 6; do log_at "s$i" $((i * 60)); done
  run board 8 100 wait:ほか click:ほか key:q
  [ "${lines[0]}" = "status=0" ]
  [ "${lines[1]}" = "restored=1" ]
  [ "${lines[2]}" = "frame_rows=8" ]
  printf '%s\n' "$output" | grep -qF "gamma"
  printf '%s\n' "$output" | grep -qF "…ほか 3 件"
  [ "$(printf '%s\n' "$output" | grep -cF delta)" -eq 0 ]
  [ ! -e "$TEST_TMPDIR/calls" ]
}

@test "まとめた行のクリックは、状態を決めたタブか最も新しいタブへ移る" {
  repo ra o/a
  state "$(ws w1 🤖app)" \
    "$(tab w1:t1 '#12 前半'),$(tab w1:t2 '#12 後半'),$(tab w1:t3 '#13 前半'),$(tab w1:t4 '#13 後半')" \
    "$(ag w1:t1 blocked s1 "$TEST_TMPDIR/ra"),$(ag w1:t2 idle s2 "$TEST_TMPDIR/ra"),$(ag w1:t3 idle s3 "$TEST_TMPDIR/ra"),$(ag w1:t4 idle s4 "$TEST_TMPDIR/ra")"
  log_at s1 $((2 * DAY))
  log_at s2 300
  log_at s3 3600
  log_at s4 600
  run board 24 100 "wait:o/a の題 13" "click:o/a の題 12" "click:o/a の題 13" key:q
  [ "${lines[0]}" = "status=0" ]
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
