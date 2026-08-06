#!/usr/bin/env bats
# The artifact-view template carries design decisions that are easy to undo by
# accident -- following the OS theme, opening the details, letting prose run the
# full page width. These check the ones that have a right answer.
#
# bash 3.2 note: a mid-test [[ ]] is excluded from errexit and passes silently,
# so assertions here use [ ] and grep exit status only.

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
TPL="$REPO_DIR/claude/skills/artifact-view/template.html"
SKILL="$REPO_DIR/claude/skills/artifact-view/SKILL.md"

@test "template.html が存在する" {
    [ -f "$TPL" ]
}

@test "SKILL.md が template.html を参照している" {
    run grep -cF 'template.html' "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "OS のテーマに追従しない（prefers-color-scheme の media query がない）" {
    # The machine runs the OS in dark mode; following it serves a dark page no
    # matter how far the ground is lifted. Only the at-rule is forbidden -- the
    # comment explaining the decision names it too, and that is not a defect.
    [ "$(grep -cE '@media[^{]*prefers-color-scheme' "$TPL")" -eq 0 ]
}

@test "ダークは data-theme のトグルで用意されている" {
    run grep -cF ':root[data-theme="dark"]' "$TPL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "ライトとダークで同じトークン名が定義されている" {
    run python3 -c "
import re, sys
s = open('$TPL', encoding='utf-8').read()
blocks = re.findall(r':root(?:\[data-theme=\"dark\"\])?\s*\{(.*?)\}', s, re.S)
sets = [set(re.findall(r'(--[a-z-]+)\s*:', b)) for b in blocks[:2]]
light, dark = sets[0], sets[1]
missing = (light - {'--serif', '--sans', '--mono'}) - dark
print(','.join(sorted(missing)) if missing else 'OK')
"
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}

@test "details に open 属性が付いていない" {
    [ "$(grep -cE '<details[^>]* open' "$TPL")" -eq 0 ]
}

@test "既定の三角を両ブラウザ分消している" {
    run grep -cF '::-webkit-details-marker' "$TPL"
    [ "$status" -eq 0 ]
    run grep -cF 'list-style: none' "$TPL"
    [ "$status" -eq 0 ]
}

@test "基準の文字サイズは 18px" {
    run grep -cF 'font-size: 18px' "$TPL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "ページ幅は 82rem" {
    run grep -cF 'max-width: 82rem' "$TPL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "文章の行長が 42em で止まっている" {
    # The wide layout is for columns of information, not long lines of text.
    run grep -cF '42em' "$TPL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "重要度の縦線が 3px 以上ある" {
    run grep -cE 'width: [3-9]px' "$TPL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "外部リソースを参照していない（自己完結）" {
    # A CDN reference breaks the page offline and leaks a request from a local
    # file. Only the CSS comment block may mention a scheme.
    [ "$(grep -cE '(src|href)="https?:' "$TPL")" -eq 0 ]
    [ "$(grep -cE 'url\(https?:' "$TPL")" -eq 0 ]
    [ "$(grep -cF '@import' "$TPL")" -eq 0 ]
}

@test "横に広い要素がページ本体を横スクロールさせない" {
    run grep -cF 'overflow-x: auto' "$TPL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# bats derives an internal function name by transliterating the title, and
# non-ASCII collapses -- two titles differing only in Japanese become the same
# identifier and the file fails to load. Hence the ASCII light/dark markers.
@test "light テーマの文字コントラストが WCAG を満たす" {
    run python3 -c "
import re
s = open('$TPL', encoding='utf-8').read()
block = re.search(r':root\s*\{(.*?)\}', s, re.S).group(1)
tok = dict(re.findall(r'(--[a-z-]+)\s*:\s*(#[0-9a-fA-F]{6})', block))

def lum(h):
    c = [int(h[i:i+2], 16) / 255 for i in (1, 3, 5)]
    c = [(x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4) for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

def ratio(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)

g = tok['--ground']
bad = []
# Primary and secondary text carry the page: hold them to AAA.
for k in ('--ink', '--dim'):
    if ratio(g, tok[k]) < 7.0:
        bad.append(f'{k}={ratio(g, tok[k]):.2f}<7')
# Accent, severity tones and captions only need AA.
for k in ('--accent', '--sev-high', '--sev-mid', '--sev-low', '--faint'):
    if ratio(g, tok[k]) < 4.5:
        bad.append(f'{k}={ratio(g, tok[k]):.2f}<4.5')
print(','.join(bad) if bad else 'OK')
"
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}

@test "dark テーマの文字コントラストも WCAG を満たす" {
    run python3 -c "
import re
s = open('$TPL', encoding='utf-8').read()
block = re.search(r':root\[data-theme=\"dark\"\]\s*\{(.*?)\}', s, re.S).group(1)
tok = dict(re.findall(r'(--[a-z-]+)\s*:\s*(#[0-9a-fA-F]{6})', block))

def lum(h):
    c = [int(h[i:i+2], 16) / 255 for i in (1, 3, 5)]
    c = [(x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4) for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

def ratio(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)

g = tok['--ground']
bad = []
for k in ('--ink', '--dim'):
    if ratio(g, tok[k]) < 7.0:
        bad.append(f'{k}={ratio(g, tok[k]):.2f}<7')
for k in ('--accent', '--sev-high', '--sev-mid', '--sev-low', '--faint'):
    if ratio(g, tok[k]) < 4.5:
        bad.append(f'{k}={ratio(g, tok[k]):.2f}<4.5')
print(','.join(bad) if bad else 'OK')
"
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}
