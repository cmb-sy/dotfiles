#!/usr/bin/env bats
# Checks the terminal-to-Neovim key path, which is where these bindings break
# silently: a mapping written for the wrong key name loads fine, reports no
# error, and simply never fires.
#
# The chain is Ghostty -> herdr -> Neovim, and each link renames the key:
#   Cmd+/  ->  CSI 21;3~ (alt+F10)  ->  forwarded, unbound in herdr  ->  <F58>
#
# bash 3.2 note: a mid-test [[ ]] is excluded from errexit and passes silently,
# so assertions here use [ ] and grep exit status only.

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
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
    run grep -cF "\"$expect\"" "$INIT"
    [ "$status" -eq 0 ]
    [ "$output" -ge 3 ]
}

@test "コメント切替が normal / visual / insert の3モードにある" {
    run bash -c "nvim --headless -c 'redir! > $BATS_TEST_TMPDIR/m.txt' \
        -c 'silent map <F58>' -c 'silent map! <F58>' -c 'redir END' -c 'qa' 2>&1"
    [ "$status" -eq 0 ]
    grep -qE '^n +<F58>' "$BATS_TEST_TMPDIR/m.txt"
    grep -qE '^x +<F58>' "$BATS_TEST_TMPDIR/m.txt"
    grep -qE '^i +<F58>' "$BATS_TEST_TMPDIR/m.txt"
}

@test "init.lua がエラーなく読み込まれる" {
    run bash -c "nvim --headless -c 'qa' 2>&1"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
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
