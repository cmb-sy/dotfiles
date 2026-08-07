#!/usr/bin/env bats
# Checks bin/input-source and the ruler indicator that reads it.
#
# The indicator's failure mode is silence: if the helper stops reporting, the
# label goes blank and the ruler still looks fine, so nothing tells you the
# state you are reading is stale.
#
# These tests never change the input source. Switching it mid-test would leave
# the machine in a Japanese state if a test aborted, and the label logic can be
# checked without touching the live setting.
#
# bash 3.2 note: a mid-test [[ ]] is excluded from errexit and passes silently,
# so assertions here use [ ] and grep exit status only.

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
IS="$REPO_DIR/bin/input-source"

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
    grep -qF 'v:lua.ime_label()' "$BATS_TEST_TMPDIR/rf.txt"
    # %= right-aligns it, so the label sits at the bottom right rather than
    # pushing the line/column readout around.
    grep -qF '%=' "$BATS_TEST_TMPDIR/rf.txt"
    grep -qxF 'true' "$BATS_TEST_TMPDIR/rf.txt"
}

@test "実画面でエラーを出さずにラベルを描画する" {
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

@test "ポーリングが insert の間だけ動く" {
    # Outside insert nothing on the keyboard can change the IME, so a poll there
    # spends process startup to learn nothing. Checked as a property -- the timer
    # is started and stopped by the mode's own events -- rather than by naming
    # whichever call implements it; the previous version of this test asserted
    # the presence of vim.fn.mode(), which was the bug.
    run python3 -c "
import re
s = open('$REPO_DIR/.config/nvim/init.lua', encoding='utf-8').read()
bad = []
if not re.search(r'InsertEnter.*?ime_timer:start', s, re.S):
    bad.append('not started on InsertEnter')
if not re.search(r'InsertLeave.*?ime_timer:stop', s, re.S):
    bad.append('not stopped on InsertLeave')
print(','.join(bad) if bad else 'OK')
"
    [ "$output" = "OK" ]
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
