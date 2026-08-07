#!/usr/bin/env bats
# Checks that every floating window this config opens looks like the same
# application. The memo and the keymap popup are built by different code -- one
# by nvim_open_win here, one by which-key -- so nothing keeps them in step
# except a shared style table and these assertions.
#
# Read from the running editor rather than from the source: which-key merges a
# preset under the user's options, so what the source says and what the window
# gets are two different things.
#
# bash 3.2 note: a mid-test [[ ]] is excluded from errexit and passes silently,
# so assertions here use [ ] and grep exit status only.

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# Runs lua in the real config and writes each returned line to a file.
nvim_lua() {
    nvim --headless -c 'Lazy! load which-key.nvim' -c "lua $1" -c 'qa!' 2>&1
}

@test "共有スタイルが定義されている" {
    run bash -c "nvim_lua() { nvim --headless -c 'Lazy! load which-key.nvim' -c \"lua \$1\" -c 'qa!' 2>&1; }
        nvim_lua 'local f = _G.float_style
          local miss = {}
          for _, k in ipairs({ \"border\", \"title_pos\", \"col\", \"row\", \"padding\" }) do
            if f[k] == nil then miss[#miss+1] = k end
          end
          vim.fn.writefile({ #miss == 0 and \"OK\" or table.concat(miss, \",\") }, \"$BATS_TEST_TMPDIR/f.txt\")'"
    [ "$status" -eq 0 ]
    grep -qxF 'OK' "$BATS_TEST_TMPDIR/f.txt"
}

@test "memo が共有スタイルどおりに開く" {
    # Asserted against the window the editor actually created, not against the
    # arguments the source passes.
    run bash -c "nvim --headless -c 'lua
        _G.toggle_memo()
        local c = vim.api.nvim_win_get_config(0)
        local f = _G.float_style
        local function border_char(b)
          local e = b[1]
          return type(e) == \"table\" and e[1] or e
        end
        local bad = {}
        if border_char(c.border) ~= \"╭\" then bad[#bad+1] = \"border=\" .. tostring(border_char(c.border)) end
        if c.title_pos ~= f.title_pos then bad[#bad+1] = \"title_pos=\" .. tostring(c.title_pos) end
        -- Centred by the shared fractions rather than by a hard-coded /2.
        local want_col = math.floor((vim.o.columns - c.width) * f.col)
        local want_row = math.floor((vim.o.lines - c.height) * f.row - 1)
        if c.col ~= want_col then bad[#bad+1] = (\"col=%d want %d\"):format(c.col, want_col) end
        if c.row ~= want_row then bad[#bad+1] = (\"row=%d want %d\"):format(c.row, want_row) end
        vim.fn.writefile({ #bad == 0 and \"OK\" or table.concat(bad, \",\") }, \"$BATS_TEST_TMPDIR/m.txt\")
      ' -c 'qa!' 2>&1"
    [ "$status" -eq 0 ]
    run cat "$BATS_TEST_TMPDIR/m.txt"
    [ "$output" = "OK" ]
}

@test "キーマップ popup が共有スタイルどおりに解決される" {
    run bash -c "nvim --headless -c 'Lazy! load which-key.nvim' -c 'lua
        local w = require(\"which-key.config\").options.win
        local f = _G.float_style
        local bad = {}
        for _, k in ipairs({ \"border\", \"title_pos\", \"col\", \"row\" }) do
          if w[k] ~= f[k] then bad[#bad+1] = (\"%s=%s want %s\"):format(k, tostring(w[k]), tostring(f[k])) end
        end
        if w.padding[1] ~= f.padding[1] or w.padding[2] ~= f.padding[2] then
          bad[#bad+1] = \"padding\"
        end
        vim.fn.writefile({ #bad == 0 and \"OK\" or table.concat(bad, \",\") }, \"$BATS_TEST_TMPDIR/w.txt\")
      ' -c 'qa!' 2>&1"
    [ "$status" -eq 0 ]
    run cat "$BATS_TEST_TMPDIR/w.txt"
    [ "$output" = "OK" ]
}

@test "plugin の float 色が共通の群にリンクされている" {
    # Without the links the popup keeps whatever colours the theme gives its own
    # groups, and the two floats drift apart on the next theme change.
    run bash -c "nvim --headless -c 'Lazy! load which-key.nvim' -c 'lua
        local want = { WhichKeyNormal = \"NormalFloat\", WhichKeyBorder = \"FloatBorder\", WhichKeyTitle = \"FloatTitle\" }
        local bad = {}
        for group, target in pairs(want) do
          local h = vim.api.nvim_get_hl(0, { name = group })
          if h.link ~= target then bad[#bad+1] = group .. \"->\" .. tostring(h.link) end
        end
        vim.fn.writefile({ #bad == 0 and \"OK\" or table.concat(bad, \",\") }, \"$BATS_TEST_TMPDIR/h.txt\")
      ' -c 'qa!' 2>&1"
    [ "$status" -eq 0 ]
    run cat "$BATS_TEST_TMPDIR/h.txt"
    [ "$output" = "OK" ]
}

@test "テーマ変更後もリンクが維持される" {
    # nvim_set_hl links are wiped by :colorscheme, so without the autocmd the
    # popup silently reverts the first time the theme is reapplied.
    run bash -c "nvim --headless -c 'Lazy! load which-key.nvim' \
      -c 'silent! colorscheme catppuccin' -c 'lua
        local h = vim.api.nvim_get_hl(0, { name = \"WhichKeyBorder\" })
        vim.fn.writefile({ tostring(h.link) }, \"$BATS_TEST_TMPDIR/c.txt\")
      ' -c 'qa!' 2>&1"
    [ "$status" -eq 0 ]
    run cat "$BATS_TEST_TMPDIR/c.txt"
    [ "$output" = "FloatBorder" ]
}

@test "memo と popup が同じ枠線文字を使う" {
    # The one difference a reader notices first. Compared as resolved values, so
    # changing either one alone fails.
    run bash -c "nvim --headless -c 'Lazy! load which-key.nvim' -c 'lua
        _G.toggle_memo()
        local b = vim.api.nvim_win_get_config(0).border
        local memo = type(b[1]) == \"table\" and b[1][1] or b[1]
        local popup = require(\"which-key.config\").options.win.border
        -- The popup names the style; the memo reports the resolved glyph. Both
        -- have to mean the same rounded box.
        local ok = popup == \"rounded\" and memo == \"╭\"
        vim.fn.writefile({ ok and \"OK\" or (\"memo=%s popup=%s\"):format(memo, tostring(popup)) },
          \"$BATS_TEST_TMPDIR/b.txt\")
      ' -c 'qa!' 2>&1"
    [ "$status" -eq 0 ]
    run cat "$BATS_TEST_TMPDIR/b.txt"
    [ "$output" = "OK" ]
}
