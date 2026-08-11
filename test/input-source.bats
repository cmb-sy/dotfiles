#!/usr/bin/env bats
# Checks bin/input-source and the ruler indicator that reads it.
#
# The indicator's failure mode is silence: if the helper stops reporting, the
# label goes blank and the ruler still looks fine, so nothing tells you the
# state you are reading is stale.
#
# All but one test leave the live input source alone: the label logic can be
# checked without touching it. The end-to-end test has to switch it, so it
# records the previous value in IME_RESTORE and teardown puts it back -- a failed
# assertion aborts the test body, which would otherwise leave the machine in a
# Japanese state.

load "helpers/common"

IS="$REPO_DIR/bin/input-source"

teardown() {
    # return 0 so the empty guard does not fail the tests that never switch.
    if [ -n "${IME_RESTORE:-}" ]; then
        "$IS" --set "$IME_RESTORE" || echo "restore failed: $IME_RESTORE" >&2
    fi
    return 0
}

@test "実行可能である" {
    [ -x "$IS" ]
}

@test "bash 構文が通る" {
    run bash -n "$IS"
    [ "$status" -eq 0 ]
}

@test "現在の入力ソース ID を返す" {
    run "$IS"
    [ "$status" -eq 0 ]
    # Every macOS source id is a reverse-dns string under com.apple or a vendor.
    echo "$output" | grep -qE '^[a-zA-Z0-9]+\.[a-zA-Z0-9.]+$'
}

@test "--label は 1〜2 文字のラベルを返す" {
    run "$IS" --label
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE '^(A|あ|カ)$'
}

@test "2 回目以降はキャッシュされたバイナリで速い" {
    [ -n "$CI" ] && skip "wall-clock budget, local only"
    # A status line polling a 2.4s script-mode swift call would stall the editor;
    # the cache is the whole reason this wrapper exists.
    "$IS" >/dev/null                      # make sure it is built
    start=$(python3 -c 'import time; print(time.time())')
    "$IS" >/dev/null
    "$IS" >/dev/null
    "$IS" >/dev/null
    elapsed=$(python3 -c "import time; print(int((time.time() - $start) * 1000))")
    # Three calls in under a second means well under the 400ms poll interval.
    [ "$elapsed" -lt 1000 ]
}

@test "ソースを編集するとバイナリが作り直される" {
    cache="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles-bin/input-source"
    "$IS" >/dev/null
    [ -x "$cache" ]
    before=$(stat -f %m "$cache")
    # The wrapper compares mtimes with -nt, which is whole seconds. On a cold
    # cache the build above lands in the same second as the touch, so without
    # this the source never reads as newer and no rebuild is triggered.
    sleep 1
    touch "$REPO_DIR/bin/input-source.swift"
    "$IS" >/dev/null
    after=$(stat -f %m "$cache")
    [ "$after" -gt "$before" ]
}

@test "--set は引数がないと exit 64 で失敗する" {
    run "$IS" --set
    [ "$status" -eq 64 ]
}

@test "--set は存在しないソースで exit 1 を返す（黙って成功しない）" {
    run "$IS" --set com.example.nosuchinputsource
    [ "$status" -eq 1 ]
}

@test "ID からラベルへの写像が正しい" {
    # Asserted on behaviour, not on the source text: grepping for "あ" passed
    # even with the mapping deleted, because the usage comment mentions it too.
    # --label-for lets the mapping be exercised without switching the machine's
    # input source. The ids are the ones this Mac actually reports.
    run "$IS" --label-for com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese
    [ "$output" = "あ" ]
    run "$IS" --label-for com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese.Katakana
    [ "$output" = "カ" ]
    # 英数 inside the Japanese IME still types alphabet, so it reads as A.
    run "$IS" --label-for com.apple.inputmethod.Kotoeri.RomajiTyping.Roman
    [ "$output" = "A" ]
    run "$IS" --label-for com.apple.keylayout.ABC
    [ "$output" = "A" ]
    run "$IS" --label-for com.apple.keylayout.US
    [ "$output" = "A" ]
}

@test "--label-for は引数がないと exit 64 で失敗する" {
    run "$IS" --label-for
    [ "$status" -eq 64 ]
}

@test "ラベル取得が現在の入力ソースを変えない" {
    # A test that flips the input source and aborts would leave the machine in
    # Japanese; this asserts the read path has no side effect.
    before=$("$IS")
    "$IS" --label >/dev/null
    "$IS" --label-for com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese >/dev/null
    after=$("$IS")
    [ "$before" = "$after" ]
}

@test "ruler にインジケータが組み込まれている" {
    run bash -c "nvim --headless \
        -c 'lua vim.fn.writefile({ vim.o.rulerformat, tostring(vim.o.ruler) }, \"$BATS_TEST_TMPDIR/rf.txt\")' \
        -c 'qa' 2>&1"
    [ "$status" -eq 0 ]
    grep -qF 'v:lua.ime_ruler()' "$BATS_TEST_TMPDIR/rf.txt"
    # %= right-aligns it, so the label sits at the bottom right rather than
    # pushing the line/column readout around.
    grep -qF '%=' "$BATS_TEST_TMPDIR/rf.txt"
    grep -qxF 'true' "$BATS_TEST_TMPDIR/rf.txt"
}

@test "実画面でエラーを出さずにラベルを描画する" {
    [ -n "$CI" ] && skip "needs GUI/tmux, local only"
    # --headless cannot catch either half of this. The ruler only exists on a
    # screen, and a libuv callback that calls a Vimscript function raises E5560
    # on the first keystroke while every headless check still passes.
    printf 'local x = 1\n' > "$BATS_TEST_TMPDIR/t.lua"
    run python3 "$REPO_DIR/test/helpers/nvim-pty.py" "$BATS_TEST_TMPDIR/t.lua"
    [ "$status" -eq 0 ]
    printf '%s' "$output" > "$BATS_TEST_TMPDIR/out.json"

    run python3 -c "
import json, re, subprocess
d = json.load(open('$BATS_TEST_TMPDIR/out.json'))
problems = []
if d['errors']:
    problems.append('errors=' + ','.join(d['errors']))
want = subprocess.run(['$REPO_DIR/bin/input-source', '--label'],
                      capture_output=True, text=True).stdout.strip()
# The label has to be the live one, not merely present: a stale cached value
# would still render something.
if not re.search(r'(?:^|\\s)' + re.escape(want) + r'\\s+\\d+,\\d+', d['text']):
    problems.append('label ' + want + ' not on screen')
print(','.join(problems) if problems else 'OK')
"
    [ "$output" = "OK" ]
}

@test "IME を切り替えると画面の表示が追従する" {
    # Switches the machine to Kotoeri, which only exists as an enabled input
    # source on a real desktop session.
    [ -n "$CI" ] && skip "needs GUI/tmux, local only"
    # The end-to-end behaviour, and the only test that would have caught the two
    # bugs here: a busy flag left standing silences every later poll, and a
    # repaint that is never flushed leaves the ruler on the previous value.
    #
    # Run under tmux because a pty's byte stream cannot answer "what is on
    # screen" -- Neovim sends differential updates, so an unchanged cell is
    # never re-sent and a time-sliced scan of the stream misses it.
    if ! command -v tmux >/dev/null 2>&1; then skip "tmux が無い環境"; fi
    # Reads Japanese off the screen, so grep and cut have to agree that あ is
    # one character. Under a C locale they work in bytes and match a third of it.
    export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
    SCREEN="$REPO_DIR/test/helpers/tmux-screen.sh"
    SESSION="ime-bats-$$"
    IME_RESTORE=$("$IS")
    printf 'local x = 1\n' > "$BATS_TEST_TMPDIR/t.lua"

    label_now() {
        "$SCREEN" grab "$SESSION" | grep -oE '[Aあカ]  [0-9]+,[0-9]+' | tail -1 | cut -c1
    }

    # Poll instead of sleeping a fixed span. The indicator updates on its own
    # timer, so a fixed wait races it: too short and the old label is still up,
    # and lengthening it only makes the suite slower without removing the race.
    # Returns the last value seen either way, so a timeout fails on the value.
    # Each step below expects a label different from the one before it, so a
    # screen that has not refreshed yet cannot satisfy the wait early.
    wait_label() {  # $1 = expected label, $2 = seconds to allow
        local deadline=$(( SECONDS + $2 )) got=
        while [ "$SECONDS" -lt "$deadline" ]; do
            got=$(label_now)
            if [ "$got" = "$1" ]; then break; fi
            sleep 0.5
        done
        printf '%s' "$got"
        return 0
    }

    "$IS" --set com.apple.keylayout.ABC
    "$SCREEN" start "$SESSION" "nvim $BATS_TEST_TMPDIR/t.lua"
    first=$(wait_label A 20)

    # Switched from outside, with no keystroke sent: the indicator has to notice
    # on its own, which is the whole point of polling.
    "$IS" --set com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese
    second=$(wait_label あ 20)

    "$IS" --set com.apple.keylayout.ABC
    third=$(wait_label A 20)

    "$SCREEN" stop "$SESSION"

    # teardown restores the input source, so an assertion failing here cannot
    # leave the machine switched.
    echo "first=$first second=$second third=$third" >&2
    [ "$first" = "A" ]
    [ "$second" = "あ" ]
    [ "$third" = "A" ]
}

@test "spawn に失敗しても busy が残らない" {
    # A busy flag that sticks freezes the indicator on its last value, which
    # looks like it is working. Checked structurally because the failing spawn
    # cannot be provoked from outside.
    run python3 -c "
import re
s = open('$REPO_DIR/.config/nvim/init.lua', encoding='utf-8').read()
fn = re.search(r'local function ime_refresh\\((.*?)\\nend', s, re.S).group(1)
bad = []
if 'pcall(vim.system' not in fn:
    bad.append('spawn not guarded')
# Cleared on the failure path as well as in the callback.
if fn.count('ime.busy = false') < 2:
    bad.append('busy cleared only once')
print(','.join(bad) if bad else 'OK')
"
    [ "$output" = "OK" ]
}

@test "再描画が端末へ flush される" {
    # redrawstatus marks the line dirty and leaves the paint sitting; without an
    # explicit flush the ruler shows the previous value until something else
    # repaints.
    run python3 -c "
import re
s = open('$REPO_DIR/.config/nvim/init.lua', encoding='utf-8').read()
fn = re.search(r'local function ime_redraw\\((.*?)\\nend', s, re.S)
if not fn:
    print('no ime_redraw')
else:
    body = fn.group(1)
    ok = 'flush = true' in body and 'pcall' in body and 'redrawstatus' in body
    print('OK' if ok else 'missing flush or fallback')
"
    [ "$output" = "OK" ]
}

@test "ポーリングが止まらない（編集中でなくても更新される）" {
    # The source can be switched from normal mode too, and a stale indicator is
    # worse than none: it says "A" while the next key produces あ. So the timer
    # never stops -- it only changes interval, fast where it matters.
    run python3 -c "
import re
s = open('$REPO_DIR/.config/nvim/init.lua', encoding='utf-8').read()
bad = []
if not re.search(r'InsertEnter.*?ime_poll_every\\(IME_POLL_INSERT_MS\\)', s, re.S):
    bad.append('no fast interval on InsertEnter')
if not re.search(r'InsertLeave.*?ime_poll_every\\(IME_POLL_IDLE_MS\\)', s, re.S):
    bad.append('no idle interval on InsertLeave')
# Started once at load, so it runs before any mode change happens.
if not re.search(r'ime_refresh\\(\\)\\nime_poll_every\\(IME_POLL_IDLE_MS\\)', s):
    bad.append('not started at load')
# Only shutdown may stop it outright.
stops = re.findall(r'ime_timer:stop\\(\\)', s)
if len(stops) != 2:
    bad.append(f'{len(stops)} stop calls (expect retime + VimLeavePre)')
print(','.join(bad) if bad else 'OK')
"
    [ "$output" = "OK" ]
}

@test "insert のほうが間隔が短い" {
    run python3 -c "
import re
s = open('$REPO_DIR/.config/nvim/init.lua', encoding='utf-8').read()
ins = int(re.search(r'IME_POLL_INSERT_MS = (\\d+)', s).group(1))
idle = int(re.search(r'IME_POLL_IDLE_MS = (\\d+)', s).group(1))
print('OK' if ins < idle and idle <= 3000 else f'insert={ins} idle={idle}')
"
    [ "$output" = "OK" ]
}

@test "ラベルが色付きブロックで描画される" {
    # A terminal cannot make one element's font bigger, so prominence comes from
    # colour and padding. Asserted on the rendered string rather than on how the
    # concatenation is written -- checking for a literal '" "' passed nothing and
    # failed the moment the spaces moved inside the adjacent literals.
    run bash -c "nvim --headless \
        -c 'lua vim.fn.writefile({ _G.ime_ruler(\"あ\"), _G.ime_ruler(\"A\"), _G.ime_ruler(\"\") }, \"$BATS_TEST_TMPDIR/r.txt\")' \
        -c 'qa' 2>&1"
    [ "$status" -eq 0 ]
    run python3 -c "
lines = open('$BATS_TEST_TMPDIR/r.txt', encoding='utf-8').read().splitlines()
ja, alpha, empty = lines[0], lines[1], lines[2] if len(lines) > 2 else ''
bad = []
# Japanese is the loud one: it is the state that makes Esc feed commands to the
# input method.
if '%#IMEJapanese#' not in ja:
    bad.append('ja not highlighted')
if '%#IMEAlpha#' not in alpha:
    bad.append('alpha not highlighted')
for name, text, ch in (('ja', ja, 'あ'), ('alpha', alpha, 'A')):
    if ' ' + ch + ' ' not in text:
        bad.append(name + ' not padded')
    if not text.endswith('%*'):
        bad.append(name + ' highlight not closed')
# Nothing to show yet must render nothing, not an empty coloured block.
if empty != '':
    bad.append('empty label renders ' + repr(empty))
print(','.join(bad) if bad else 'OK')
"
    [ "$output" = "OK" ]
}

@test "両ハイライト群が実際に定義されている" {
    # A ruler referencing an undefined group renders unstyled, silently.
    run bash -c "nvim --headless \
        -c 'lua local o = {} for _, g in ipairs({ \"IMEJapanese\", \"IMEAlpha\" }) do
              local h = vim.api.nvim_get_hl(0, { name = g, link = false })
              o[#o+1] = g .. \"=\" .. tostring(vim.tbl_isempty(h) == false) end
            vim.fn.writefile(o, \"$BATS_TEST_TMPDIR/hl.txt\")' -c 'qa' 2>&1"
    [ "$status" -eq 0 ]
    grep -qxF 'IMEJapanese=true' "$BATS_TEST_TMPDIR/hl.txt"
    grep -qxF 'IMEAlpha=true' "$BATS_TEST_TMPDIR/hl.txt"
}

@test "タイマーのコールバックが Vimscript を呼ばない" {
    # A libuv callback runs in a fast event context: vim.fn.* raises E5560 there,
    # and only on the first tick, so it survives every headless check.
    run python3 -c "
import re
s = open('$REPO_DIR/.config/nvim/init.lua', encoding='utf-8').read()
body = re.search(r'ime_timer:start\\([^)]*,\\s*function\\((.*?)end\\)', s, re.S)
print('no timer' if not body else ('vim.fn in callback' if 'vim.fn.' in body.group(1) else 'OK'))
"
    [ "$output" = "OK" ]
}

@test "ラベルが変わったときだけ再描画する" {
    # redrawstatus on every poll would repaint the screen 2.5 times a second.
    run grep -cF 'out ~= ime.label' "$REPO_DIR/.config/nvim/init.lua"
    [ "$status" -eq 0 ]
}
