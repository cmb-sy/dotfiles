#!/usr/bin/env bats
# Checks for bin/highlight-code. The failure that matters most is silent: if the
# highlighter throws or emits raw HTML, a page either loses its code or gains a
# script tag.

load "helpers/common"

HL="$REPO_DIR/bin/highlight-code"

@test "実行可能である" {
    [ -x "$HL" ]
}

@test "python 構文が通る" {
    run python3 -m py_compile "$HL"
    [ "$status" -eq 0 ]
    rm -rf "$REPO_DIR/bin/__pycache__"
}

@test "コメント・文字列・キーワードに class が付く" {
    python3 -c 'import pygments' 2>/dev/null || skip "pygments not installed"
    run bash -c "printf '# note\nx = \"s\"\nif x: pass\n' | '$HL' --lang python"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF 'class="c"'
    echo "$output" | grep -qF 'class="s"'
    echo "$output" | grep -qF 'class="k"'
}

@test "HTML を エスケープする（タグを注入させない）" {
    run bash -c "printf 'a = \"<script>x</script>\"\n' | '$HL' --lang python"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF '&lt;script&gt;'
    # A surviving raw tag would execute in the page.
    [ "$(echo "$output" | grep -cF '<script>')" -eq 0 ]
}

@test "アンパサンドもエスケープする" {
    run bash -c "printf 'a && b\n' | '$HL' --lang bash"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF '&amp;'
}

@test "未知の言語では素のまま返し、失敗しない" {
    # Losing the code is worse than losing the colour.
    run bash -c "printf 'x = 1\n' | '$HL' --lang nosuchlanguage 2>/dev/null"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF 'x = 1'
    [ "$(echo "$output" | grep -cF 'class=')" -eq 0 ]
}

@test "空入力では何も出さず、失敗しない" {
    run bash -c "printf '' | '$HL' --lang python"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "日本語のコメントを壊さない" {
    run bash -c "printf '# 本番相当のため必須\nx = 1\n' | '$HL' --lang python"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF '本番相当のため必須'
}

@test "terraform を扱える（画面で使う言語）" {
    python3 -c 'import pygments' 2>/dev/null || skip "pygments not installed"
    run bash -c "printf 'variable \"env\" {\n  type = string\n}\n' | '$HL' --lang terraform"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF 'class='
}

@test "--list は言語名を返す" {
    # --list is the one path that hard-errors without pygments, by design: it
    # has nothing to fall back to.
    python3 -c 'import pygments' 2>/dev/null || skip "pygments not installed"
    run bash -c "'$HL' --list"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF 'terraform'
}

@test "空白だけのトークンを span で包まない（ソースを読めるまま保つ）" {
    run bash -c "printf 'x = 1\n' | '$HL' --lang python"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | grep -cE 'class="[a-z]"> +<')" -eq 0 ]
}

@test "pygments が無い環境でも素のまま返す" {
    # Simulated by shadowing the import with an empty module directory.
    mkdir -p "$BATS_TEST_TMPDIR/pygments"
    printf 'raise ImportError\n' > "$BATS_TEST_TMPDIR/pygments/__init__.py"
    run bash -c "printf 'x = 1\n' | PYTHONPATH='$BATS_TEST_TMPDIR' '$HL' --lang python 2>/dev/null"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF 'x = 1'
}
