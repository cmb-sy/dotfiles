#!/usr/bin/env bats
# Checks the terminal-to-Neovim key path, which is where these bindings break
# silently: a mapping written for the wrong key name loads fine, reports no
# error, and simply never fires.
#
# The chain is Ghostty -> herdr -> Neovim, and each link renames the key:
#   Cmd+/  ->  CSI 21;3~ (alt+F10)  ->  forwarded, unbound in herdr  ->  <F58>

load "helpers/common"

KEYS="$REPO_DIR/terminal/ghostty/keybindings.conf"
HERDR="$REPO_DIR/terminal/herdr/config.toml"
INIT="$REPO_DIR/.config/nvim/init.lua"

@test "Ghostty が Cmd+/ を F1..F12 の chord で送る" {
    # F13+ (CSI 25~) is dropped by herdr, so the sequence has to stay in range.
    run grep -cE '^keybind = super\+slash=csi:2[0-4];[2-8]~' "$KEYS"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "Cmd+/ の chord が herdr に奪われていない" {
    # A chord bound in herdr's [keys] never reaches the pane.
    seq=$(grep -oE '^keybind = super\+slash=csi:[0-9]+;[0-9]+~' "$KEYS" | grep -oE '[0-9]+;[0-9]+')
    num="${seq%%;*}"; mod="${seq##*;}"
    case "$num" in
        20) fkey="f9" ;;  21) fkey="f10" ;;  23) fkey="f11" ;;  24) fkey="f12" ;;
        *)  fkey="unknown" ;;
    esac
    case "$mod" in
        2) prefix="shift" ;;  3) prefix="alt" ;;  5) prefix="ctrl" ;;  *) prefix="unknown" ;;
    esac
    [ "$fkey" != "unknown" ]
    [ "$prefix" != "unknown" ]
    # herdr must not claim it, in [keys] or in a [[keys.command]] block.
    [ "$(grep -cE "\"$prefix\\+$fkey\"" "$HERDR")" -eq 0 ]
}

@test "nvim 側のマッピングが Ghostty のシーケンスと対応している" {
    # Neovim renames a modified function key into the extended range. The pairs
    # below are measured, not derived: writing <M-F10> matches nothing at all.
    seq=$(grep -oE '^keybind = super\+slash=csi:[0-9]+;[0-9]+~' "$KEYS" | grep -oE '[0-9]+;[0-9]+')
    case "$seq" in
        "21;3") expect="<F58>" ;;   # alt+F10
        "21;2") expect="<F22>" ;;   # shift+F10
        "20;3") expect="<F57>" ;;   # alt+F9
        *)      expect="UNMEASURED" ;;
    esac
    [ "$expect" != "UNMEASURED" ]
    # Presence only: whether all three modes are covered is checked live below,
    # against the running editor rather than against the shape of the source.
    run grep -cF "\"$expect\"" "$INIT"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "コメント切替が両経路 x 3モードにある" {
    # Two delivery paths: Ghostty's chord once its config is reloaded, and the
    # kitty keyboard protocol's <D-/> otherwise. An unmapped <D-/> types itself
    # into the buffer, so a gap here is worse than inert.
    run bash -c "nvim --headless -c 'redir! > $BATS_TEST_TMPDIR/m.txt' \
        -c 'silent map <F58>' -c 'silent map! <F58>' \
        -c 'silent map <D-/>' -c 'silent map! <D-/>' -c 'redir END' -c 'qa' 2>&1"
    [ "$status" -eq 0 ]
    for mode in n x i; do
        grep -qE "^$mode +<F58>" "$BATS_TEST_TMPDIR/m.txt"
        grep -qE "^$mode +<D-/>" "$BATS_TEST_TMPDIR/m.txt"
    done
}

@test "Ghostty の設定に検証エラーがない" {
    # An invalid value is dropped with a warning nobody reads, and the setting
    # then does nothing at all -- which is how 19 font-codepoint-map lines sat
    # rejected while looking correct.
    G="/Applications/Ghostty.app/Contents/MacOS/ghostty"
    command -v ghostty >/dev/null 2>&1 && G=ghostty
    if [ ! -x "$G" ] && ! command -v ghostty >/dev/null 2>&1; then
        skip "ghostty が無い環境"
    fi
    run bash -c "'$G' +validate-config 2>&1 | grep -c 'invalid value'"
    [ "$output" -eq 0 ]
}

@test "font-codepoint-map の範囲が両端に U+ を持つ" {
    # Ghostty rejects U+E000-E00A; the end of a range needs the prefix too.
    CFG="$REPO_DIR/terminal/ghostty/config"
    [ "$(grep -cE 'font-codepoint-map = .*U\+[0-9A-Fa-f]+-[0-9A-Fa-f]+' "$CFG")" -eq 0 ]
    run grep -cE 'font-codepoint-map = .*U\+[0-9A-Fa-f]+-U\+[0-9A-Fa-f]+' "$CFG"
    [ "$status" -eq 0 ]
    [ "$output" -ge 15 ]
}

@test "init.lua がエラーなく読み込まれる" {
    # Counts nvim's own error codes rather than demanding total silence: on a
    # machine with no treesitter parsers built yet every start prints download
    # notices, and those are progress, not breakage.
    run bash -c "nvim --headless -c 'qa' 2>&1"
    [ "$status" -eq 0 ]
    errors=$(printf '%s\n' "$output" | grep -cE 'E[0-9]+:') || errors=0
    [ "$errors" -eq 0 ]
}

@test "which-key の窓が helix 既定より大きい" {
    # The preset caps at 30-60 columns with padding {0,1}, which reads as a hint
    # strip. User opts merge after the preset, so these values are the effective
    # ones -- resolved by loading the plugin rather than read off the source.
    run bash -c "nvim --headless -c 'Lazy! load which-key.nvim' \
        -c 'lua local o = require(\"which-key.config\").options
            local w, l = o.win, o.layout
            vim.fn.writefile({ (w.width.min or 0) .. \" \" .. (w.height.min or 0) .. \" \"
              .. (w.padding[2] or 0) .. \" \" .. (l.width.min or 0) .. \" \" .. (l.spacing or 0) },
              \"$BATS_TEST_TMPDIR/wk.txt\")' -c 'qa' 2>&1"
    [ "$status" -eq 0 ]
    read -r wmin hmin pad lwidth spacing < "$BATS_TEST_TMPDIR/wk.txt"
    [ "$wmin" -gt 30 ]
    [ "$hmin" -gt 4 ]
    [ "$pad" -gt 1 ]
    [ "$lwidth" -gt 30 ]
    [ "$spacing" -gt 3 ]
}

@test "git の群（<leader>h）に差分一覧・履歴・status・blame のキーがある" {
    # Reading what Claude Code changed across files needs a view wider than one
    # buffer's hunks. These sit beside gitsigns' hp/hd under the same prefix.
    run bash -c "nvim --headless -c 'redir! > $BATS_TEST_TMPDIR/h.txt' \
        -c 'silent nmap <Space>hD' -c 'silent nmap <Space>hh' -c 'silent nmap <Space>hH' \
        -c 'silent nmap <Space>hq' -c 'silent nmap <Space>hs' -c 'silent nmap <Space>hb' \
        -c 'redir END' -c 'qa' 2>&1"
    [ "$status" -eq 0 ]
    for k in hD hh hH hq hs hb; do
        grep -qF "<Space>$k" "$BATS_TEST_TMPDIR/h.txt"
    done
}

@test "diffview と fugitive のコマンドが読み込める" {
    run bash -c "nvim --headless -c 'Lazy! load diffview.nvim vim-fugitive' \
        -c 'lua vim.fn.writefile({ vim.fn.exists(\":DiffviewOpen\") .. \" \" .. vim.fn.exists(\":Git\") }, \"$BATS_TEST_TMPDIR/c.txt\")' \
        -c 'qa' 2>&1"
    [ "$status" -eq 0 ]
    read -r dv fg < "$BATS_TEST_TMPDIR/c.txt"
    [ "$dv" -eq 2 ]
    [ "$fg" -eq 2 ]
}

@test "which-key が <leader>h を git の群として見せる" {
    grep -qF '{ "<leader>h", group = "git" }' "$INIT"
}

@test "<leader>g は全文検索のまま" {
    grep -qF '{ "<leader>g", "<Cmd>Telescope live_grep<CR>"' "$INIT"
}

@test "左の列で file tree の下に Changes（git_status）が並ぶ" {
    # Both neo-tree views must land in the same left column, files on top and
    # changes below, so what moved is visible beside the tree without switching.
    cd "$REPO_DIR"
    run bash -c "nvim --headless -c 'lua require(\"lazy\").load({ plugins = { \"edgy.nvim\" } }); require(\"edgy\").open(\"left\")' \
        -c 'lua vim.defer_fn(function()
              local out = {}
              for _, w in ipairs(vim.api.nvim_list_wins()) do
                local b = vim.api.nvim_win_get_buf(w)
                local src = vim.b[b].neo_tree_source
                if src then
                  local p = vim.api.nvim_win_get_position(w)
                  table.insert(out, src .. \" \" .. p[1] .. \" \" .. p[2])
                end
              end
              vim.fn.writefile(out, \"$BATS_TEST_TMPDIR/e.txt\")
              vim.cmd(\"qa!\")
            end, 2000)' 2>&1"
    [ "$status" -eq 0 ]
    read -r _ frow fcol < <(grep '^filesystem ' "$BATS_TEST_TMPDIR/e.txt")
    read -r _ grow gcol < <(grep '^git_status ' "$BATS_TEST_TMPDIR/e.txt")
    [ -n "$frow" ] && [ -n "$grow" ]
    [ "$fcol" -eq "$gcol" ]
    [ "$frow" -lt "$grow" ]
}

@test "<leader>e は左の列（file tree と Changes）をまとめて開閉する" {
    grep -qF '{ "<leader>e", function() require("edgy").toggle("left") end' "$INIT"
}

@test "nvim . で起動しても Changes が file tree の下に出る" {
    cd "$REPO_DIR"
    run bash -c "nvim --headless . -c 'lua vim.defer_fn(function()
              local out = {}
              for _, w in ipairs(vim.api.nvim_list_wins()) do
                local src = vim.b[vim.api.nvim_win_get_buf(w)].neo_tree_source
                if src then table.insert(out, src) end
              end
              vim.fn.writefile(out, \"$BATS_TEST_TMPDIR/d.txt\")
              vim.cmd(\"qa!\")
            end, 2500)' 2>&1"
    [ "$status" -eq 0 ]
    grep -qx 'filesystem' "$BATS_TEST_TMPDIR/d.txt"
    grep -qx 'git_status' "$BATS_TEST_TMPDIR/d.txt"
}

@test "左の列の幅が揺れない（neo-tree の自動拡幅と edgy の固定幅が引っ張り合わない）" {
    # neo-tree's auto_expand_width grows the column to fit a long name and edgy
    # snaps it back to its fixed size; every redraw repeated the tug, so the
    # separator kept shaking. Sample the width and require it to hold still,
    # in a repo whose git_status header is longer than the column.
    d="$BATS_TEST_TMPDIR/a-rather-long-directory-name-for-the-header"
    mkdir -p "$d" && git -C "$d" init -q && touch "$d/x"
    cd "$d"
    run bash -c "nvim --headless . -c 'lua local o, n = {}, 0
          local t = vim.uv.new_timer()
          t:start(1500, 100, vim.schedule_wrap(function()
            n = n + 1
            for _, w in ipairs(vim.api.nvim_list_wins()) do
              if vim.b[vim.api.nvim_win_get_buf(w)].neo_tree_source == \"filesystem\" then
                table.insert(o, tostring(vim.api.nvim_win_get_width(w)))
              end
            end
            if n >= 10 then t:stop(); vim.fn.writefile(o, \"$BATS_TEST_TMPDIR/w.txt\"); vim.cmd(\"qa!\") end
          end))' 2>&1"
    [ "$status" -eq 0 ]
    [ "$(sort -u "$BATS_TEST_TMPDIR/w.txt" | wc -l | tr -d ' ')" -eq 1 ]
    [ "$(wc -l < "$BATS_TEST_TMPDIR/w.txt" | tr -d ' ')" -eq 10 ]
}
