#!/usr/bin/env bats
# Checks for bin/view-html. Everything here exercises --print-url or the error
# paths, so no browser is launched and no automation prompt appears.
#
# bash 3.2 note: a mid-test [[ ]] is excluded from errexit and passes silently,
# so assertions here use [ ] and grep exit status only.

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
VIEW="$REPO_DIR/bin/view-html"

setup() {
    TMP="$(mktemp -d /private/tmp/view-html-test.XXXXXX)"
    printf '<title>t</title>\n' > "$TMP/page.html"
}

teardown() {
    rm -rf "$TMP"
}

@test "実行可能である" {
    [ -x "$VIEW" ]
}

@test "bash 構文が通る" {
    run bash -n "$VIEW"
    [ "$status" -eq 0 ]
}

@test "--print-url は file:// URL を返す" {
    run "$VIEW" --print-url "$TMP/page.html"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF "file://$TMP/page.html"
}

@test "--print-url は相対パスを絶対パスに解決する" {
    cd "$TMP"
    run "$VIEW" --print-url ./page.html
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF "file://$TMP/page.html"
    # A relative path must not survive into the URL.
    [ "$(echo "$output" | grep -cF './page.html')" -eq 0 ]
}

@test "--print-url は空白を %20 にエンコードする" {
    mv "$TMP/page.html" "$TMP/two words.html"
    run "$VIEW" --print-url "$TMP/two words.html"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF "two%20words.html"
    [ "$(echo "$output" | grep -cF 'two words.html')" -eq 0 ]
}

@test "--print-url は # を %23 にエンコードする" {
    mv "$TMP/page.html" "$TMP/a#b.html"
    run "$VIEW" --print-url "$TMP/a#b.html"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF "a%23b.html"
}

@test "--print-url は二重引用符を %22 にエンコードする（AppleScript 文字列の脱出防止）" {
    mv "$TMP/page.html" "$TMP/a\"b.html"
    run "$VIEW" --print-url "$TMP/a\"b.html"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF "a%22b.html"
    # A surviving raw quote would close the AppleScript string literal.
    [ "$(echo "$output" | grep -cF '"')" -eq 0 ]
}

@test "--print-url はバックスラッシュを %5C にエンコードする" {
    mv "$TMP/page.html" "$TMP/a\\b.html"
    run "$VIEW" --print-url "$TMP/a\\b.html"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF "a%5Cb.html"
    [ "$(echo "$output" | grep -cF '\')" -eq 0 ]
}

@test "--print-url は改行を %0A にエンコードする" {
    printf '<title>t</title>\n' > "$TMP/$(printf 'a\nb').html"
    run "$VIEW" --print-url "$TMP/$(printf 'a\nb').html"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF "a%0Ab.html"
    # One line only: an unencoded newline would split the URL.
    [ "$(printf '%s' "$output" | grep -c '')" -eq 1 ]
}

@test "--print-url は非 ASCII をパーセントエンコードする（ブラウザの URL 表記に合わせる）" {
    mv "$TMP/page.html" "$TMP/日本語.html"
    run "$VIEW" --print-url "$TMP/日本語.html"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF "%E6%97%A5%E6%9C%AC%E8%AA%9E.html"
}

@test "AppleScript に URL を文字列補間していない（argv 経由で渡している）" {
    # `is "$target"` in the script text is the injection shape this must avoid.
    [ "$(grep -cF 'is "$target"' "$VIEW")" -eq 0 ]
    run grep -c 'item 1 of argv' "$VIEW"
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}

@test "--print-url はブラウザを起動しない（open を呼ばない）" {
    # A stub `open` earlier on PATH would be invoked if the script fell through
    # to the launch path; the marker file proves it did not.
    mkdir -p "$TMP/stub"
    printf '#!/bin/sh\ntouch "%s/open-was-called"\n' "$TMP" > "$TMP/stub/open"
    chmod +x "$TMP/stub/open"
    PATH="$TMP/stub:$PATH" run "$VIEW" --print-url "$TMP/page.html"
    [ "$status" -eq 0 ]
    [ ! -f "$TMP/open-was-called" ]
}

@test "存在しないファイルは exit 1 で失敗する" {
    run "$VIEW" --print-url "$TMP/missing.html"
    [ "$status" -eq 1 ]
    echo "$output" | grep -qF "no such file"
}

@test "引数なしは exit 64 で usage を出す" {
    run "$VIEW"
    [ "$status" -eq 64 ]
    echo "$output" | grep -qF "usage:"
}

@test "引数が2つ以上なら exit 64 で usage を出す" {
    run "$VIEW" "$TMP/page.html" "$TMP/page.html"
    [ "$status" -eq 64 ]
    echo "$output" | grep -qF "usage:"
}

@test "Safari と Chromium の両分岐が実装されている" {
    run grep -c 'safari_script\|chromium_script' "$VIEW"
    [ "$status" -eq 0 ]
    [ "$output" -ge 4 ]
}

@test "スクリプト経路が失敗したら open にフォールバックする分岐がある" {
    run grep -cF 'opened (via open)' "$VIEW"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
