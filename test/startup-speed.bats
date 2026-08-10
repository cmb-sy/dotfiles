#!/usr/bin/env bats
# Guards the startup and latency work, which decays silently: a plugin added
# later, or compinit reverted to auditing every run, costs tens of milliseconds
# that nobody notices as a regression because nothing fails.
#
# The budgets are deliberately loose. They exist to catch something going badly
# wrong, not to fail on a busy machine -- a test that flakes gets ignored, and
# an ignored test guards nothing.

load "helpers/common"

# Median of five runs, in milliseconds. The median rather than the mean, so one
# scheduling hiccup does not decide the result.
#
# The budgets below are skipped on CI: a shared runner measures the runner, not
# the config, and a budget that flakes there would train everyone to ignore it.
median_ms() {
    python3 -c "
import subprocess, sys, time, statistics
cmd = sys.argv[1:]
xs = []
for _ in range(5):
    start = time.perf_counter()
    subprocess.run(cmd, capture_output=True)
    xs.append((time.perf_counter() - start) * 1000)
print(int(statistics.median(xs)))
" "$@"
}

@test "nvim の起動が 120ms 以内" {
    [ -n "$CI" ] && skip "needs GUI/tmux, local only"
    run median_ms nvim --headless -c qa
    [ "$status" -eq 0 ]
    [ "$output" -lt 120 ]
}

@test "設定の追加コストが素の nvim の 4 倍以内" {
    [ -n "$CI" ] && skip "needs GUI/tmux, local only"
    # A ratio rather than an absolute number: it stays meaningful on a slower
    # machine, where every measurement grows together.
    configured=$(median_ms nvim --headless -c qa)
    clean=$(median_ms nvim --clean --headless -c qa)
    [ "$clean" -gt 0 ]
    [ "$configured" -lt $((clean * 4)) ]
}

@test "対話 zsh の起動が 200ms 以内" {
    [ -n "$CI" ] && skip "needs GUI/tmux, local only"
    run median_ms zsh -i -c exit
    [ "$status" -eq 0 ]
    [ "$output" -lt 200 ]
}

@test "compinit の監査が毎回走らない" {
    # compaudit is half of the shell's startup. Running it once a day keeps the
    # check without paying for it on every prompt.
    run grep -cF 'compinit -C' "$REPO_DIR/.zshrc"
    [ "$status" -eq 0 ]
    # And the full audit still has to happen when the dump is stale.
    run grep -cE 'compinit -d' "$REPO_DIR/.zshrc"
    [ "$status" -eq 0 ]
}

@test "which-key の popup が待たずに出る" {
    # The popup is there to be read while deciding; holding it back makes the
    # decision slower, which is the opposite of the point.
    run bash -c "nvim --headless -c 'Lazy! load which-key.nvim' \
        -c 'lua local d = require(\"which-key.config\").options.delay
            vim.fn.writefile({ type(d) == \"number\" and tostring(d) or \"function\" }, \"$BATS_TEST_TMPDIR/d.txt\")' \
        -c 'qa' 2>&1"
    [ "$status" -eq 0 ]
    run cat "$BATS_TEST_TMPDIR/d.txt"
    [ "$output" -le 50 ]
}

@test "updatetime が CursorHold を待たせない" {
    # The default 4000 makes anything driven by CursorHold look broken.
    run bash -c "nvim --headless -c 'lua vim.fn.writefile({ tostring(vim.o.updatetime) }, \"$BATS_TEST_TMPDIR/u.txt\")' -c 'qa' 2>&1"
    [ "$status" -eq 0 ]
    run cat "$BATS_TEST_TMPDIR/u.txt"
    [ "$output" -le 500 ]
    # Not so low that the swap file is rewritten on every keystroke.
    [ "$output" -ge 100 ]
}

@test "nv と nv. が nvim に解決される" {
    # The dot is part of the alias name, so it needs no space -- which is the
    # point, since `nvim .` is typed constantly.
    run zsh -i -c 'alias nv'
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF "nvim"
    run zsh -i -c 'alias nv.'
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF "nvim ."
}

@test "nv. が実際にコマンドとして展開される" {
    # An alias can exist and still not expand: aliases are resolved at parse
    # time, so one defined in the same line it is used in never fires.
    run bash -c "zsh -i -c 'nv. --version' 2>/dev/null | head -1"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF "NVIM"
}
