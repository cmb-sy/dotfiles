#!/usr/bin/env bats
# The PreToolUse guard that refuses commands wiping home, root or system areas.
# Sessions run with bypassPermissions, so this hook is the only layer that stops
# them; every evasion seen in the 2026-10-02 audit is pinned here.

load "helpers/common"

HOOK="$REPO_DIR/claude/hooks/block-destructive.sh"

# run_hook <command>: feed the command to the hook as PreToolUse input.
run_hook() {
  run env HOME=/Users/tester bash "$HOOK" <<<"$(jq -n --arg c "$1" '{tool_input:{command:$c}}')"
}

blocked() { run_hook "$1"; [ "$status" -eq 2 ]; }
allowed() { run_hook "$1"; [ "$status" -eq 0 ]; }

@test "root を消す形はすべて止める" {
  for c in 'rm -rf /' 'rm -rf /*' 'rm -fr /' 'rm -r -f /' 'rm -Rf /' \
           'rm --recursive --force /' 'rm -rf -- /' 'rm -r /' 'sudo rm -rf /'; do
    blocked "$c" || { echo "not blocked: $c"; return 1; }
  done
}

@test "home を消す形はすべて止める" {
  for c in 'rm -rf ~' 'rm -rf ~/' 'rm -rf ~/*' 'rm -rf $HOME' 'rm -rf $HOME/' \
           'rm -rf "$HOME"' 'rm -rf "${HOME}/"' 'rm -rf /Users/tester' 'rm -rf /Users' \
           'rm -rf "$HOME"/' 'rm -rf ~/..' 'rm -rf /Users/tester/../tester' \
           'rm -rf ~tester' 'rm -rf ~tester/' "$(printf 'rm -rf \\\n~')"; do
    blocked "$c" || { echo "not blocked: $c"; return 1; }
  done
}

@test "連結やコマンド置換の中の rm も止める" {
  for c in 'rm -rf ~ ; echo x' 'echo ok && rm -rf ~' 'true || rm -rf /' \
           'ls | xargs rm -rf ~' 'echo $(rm -rf ~)' 'echo x;rm -rf ~' \
           "$(printf 'cat <<EOF\n$(rm -rf ~)\nEOF')" \
           "$(printf 'cat <<EOF\n# `rm -rf /` runs here\nEOF')"; do
    blocked "$c" || { echo "not blocked: $c"; return 1; }
  done
}

@test "システム領域の削除を止める" {
  for c in 'rm -rf /usr/local' 'rm -rf /System/Library' 'rm -rf /etc' 'rm -rf /var/log' \
           'rm -rf /opt/homebrew' 'rm -rf /Library' 'rm -rf /Applications/Foo.app'; do
    blocked "$c" || { echo "not blocked: $c"; return 1; }
  done
}

@test "デバイスへの書き込みとファイルシステム作成を止める" {
  for c in 'dd if=/dev/zero of=/dev/disk2' 'mkfs.ext4 /dev/sda1' 'echo x > /dev/sda'; do
    blocked "$c" || { echo "not blocked: $c"; return 1; }
  done
}

@test "一時領域とプロジェクト配下の削除は通す" {
  for c in 'rm -rf /private/tmp/foo' 'rm -rf /var/folders/xx/T/foo' \
           'rm -rf /private/var/folders/xx/T/foo' 'rm -rf "$TMPDIR/foo"' \
           'rm -rf ./build' 'rm -rf ~/project/build' 'rm -rf node_modules' \
           'rm file.txt' 'rm -f /usr/local/foo' 'ls /usr' 'rm -rf build && ls ~'; do
    allowed "$c" || { echo "wrongly blocked: $c"; return 1; }
  done
}

@test "文字列の中に書かれただけの rm は通す" {
  for c in 'echo "rm -rf ~"' 'git commit -m "rm -rf ~ is blocked"'; do
    allowed "$c" || { echo "wrongly blocked: $c"; return 1; }
  done
}

@test "コメントの中に書かれただけの rm は通す" {
  for c in '# `rm -rf /` belongs to the hook' 'echo ok # rm -rf ~' \
           "$(printf "cat <<'EOF'\n# \`rm -rf /\` is pinned\nEOF")" \
           "$(printf "python3 - <<'EOF'\nprint(\"it's\")  # rm -rf ~\nEOF\necho done")"; do
    allowed "$c" || { echo "wrongly blocked: $c"; return 1; }
  done
}

@test "引用符の中の # はコメント扱いせず後ろの rm を止める" {
  for c in 'echo "a #b" $(rm -rf /)' "echo 'x #y' \`rm -rf ~\`" \
           "echo \"it's #x\" \$(rm -rf /)" 'echo "a;#" $(rm -rf ~)' \
           'echo "a|#" `rm -rf ~`' 'echo "a\" #" $(rm -rf ~)' \
           "$(printf 'echo "a\n#" $(rm -rf ~)')" 'echo `x #` ; rm -rf ~'; do
    blocked "$c" || { echo "not blocked: $c"; return 1; }
  done
}

@test "止めたときは理由を stderr に出す" {
  run_hook 'rm -rf ~'
  printf '%s\n' "$output" | grep -qF 'BLOCK:'
}

@test "コマンドが無い入力は通す" {
  run bash "$HOOK" <<<'{}'
  [ "$status" -eq 0 ]
}
