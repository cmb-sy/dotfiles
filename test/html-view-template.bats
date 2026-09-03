#!/usr/bin/env bats
# The html-view template carries design decisions that are easy to undo by
# accident -- following the OS theme, opening the details, letting prose run the
# full page width. These check the ones that have a right answer.
# The SKILL.md prose is checked separately, in html-view-skill.bats.

load "helpers/common"

TPL="$REPO_DIR/claude/skills/html-view/template.html"

@test "template.html が存在する" {
    [ -f "$TPL" ]
}

@test "OS のテーマに追従しない（prefers-color-scheme の media query がない）" {
    # The machine runs the OS in dark mode, and the page is meant to be light
    # regardless: inheriting would hand it back the ground it was moved off.
    # Only the at-rule is forbidden -- the comment explaining the decision
    # names it too, and that is not a defect.
    [ "$(grep -cE '@media[^{]*prefers-color-scheme' "$TPL")" -eq 0 ]
}

@test "ダークは data-theme のトグルで用意されている" {
    # Light is the default; dark stays reachable but is not inherited from the OS.
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

@test "説明の文字が基準サイズを下回らない" {
    # Body copy in an opened row is the text that actually gets read; below the
    # base size it reads as fine print.
    run python3 -c "
import re
s = open('$TPL', encoding='utf-8').read()
body = re.search(r'\n  \.body \{(.*?)\n  \}', s, re.S).group(1)
v = float(re.search(r'font-size: ([\d.]+)rem', body).group(1))
lede = float(re.search(r'\.lede \{[^}]*font-size: ([\d.]+)rem', s).group(1))
bad = [n for n, x in (('body', v), ('lede', lede)) if x < 1.0]
print(','.join(bad) if bad else 'OK')
"
    [ "$output" = "OK" ]
}

@test "基準の文字サイズは 19px 以上" {
    run grep -cE 'font-size: (19|2[0-9])px' "$TPL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "地色が純白でも純黒でもない" {
    # Pure white is the brightest the display can emit; pure black maximises the
    # ratio against any text on it. Both ends are where halation lives.
    #
    # 0.95 sits between the light ground (0.9394) and #fafafa (0.9560): far
    # enough to leave the ground room to breathe, close enough that anything
    # reading as white is rejected. Checked in both themes -- guarding only one
    # let the default ground go to #fff unnoticed.
    run python3 -c "
import wcag
s = open('$TPL', encoding='utf-8').read()
bad = []
for theme in ('light', 'dark'):
    g = wcag.tokens(s, theme)['--ground']
    if not 0.002 <= wcag.lum(g) <= 0.95:
        bad.append(f'{theme}={wcag.lum(g)*100:.2f}%')
print(','.join(bad) if bad else 'OK')
"
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}

@test "本文のコントラストが高すぎない（ハレーションを避ける）" {
    # Contrast is not a "higher is better" axis. Black on white is 21:1 and the
    # glyphs bloom; body text is held inside 10-13:1, past AAA but short of the
    # range that strains. Checked in both themes.
    run python3 -c "
import wcag
s = open('$TPL', encoding='utf-8').read()
bad = []
for theme in ('dark', 'light'):
    tok = wcag.tokens(s, theme)
    r = wcag.ratio(tok['--ground'], tok['--ink'])
    if not 10.0 <= r <= 13.5:
        bad.append(f'{theme}={r:.2f}')
print(','.join(bad) if bad else 'OK')
"
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}

@test "アニメーションを持たない（追視の負担を作らない）" {
    [ "$(grep -cE 'transition:|animation:' "$TPL")" -eq 0 ]
}

@test "ページ幅が 44-56rem に収まっている" {
    run python3 -c "
import re
s = open('$TPL', encoding='utf-8').read()
v = float(re.search(r'\.wrap \{[^}]*max-width: ([\d.]+)rem', s, re.S).group(1))
print('OK' if 44 <= v <= 56 else f'{v}rem')
"
    [ "$output" = "OK" ]
}

@test "本文に行長の上限を付けない（幅いっぱいに流す）" {
    # A capped measure left prose as a narrow column against a wide blank. The
    # page's own max-width is the bound now, so no em cap may reappear inside
    # .body or on .lede.
    run python3 -c "
import re
s = open('$TPL', encoding='utf-8').read()
bad = []
body = re.search(r'\n  \.body \{.*?(?=\n  footer \{)', s, re.S)
if body and re.search(r'max-width: [\d.]+em', body.group(0)):
    bad.append('body')
lede = re.search(r'\.lede \{[^}]*\}', s)
if lede and re.search(r'max-width: [\d.]+em', lede.group(0)):
    bad.append('lede')
print(','.join(bad) if bad else 'OK')
"
    [ "$output" = "OK" ]
}

@test "開いた本文が地色と別の面に見える" {
    # A panel at 1.14:1 against the ground reads as no panel at all. The fill
    # plus a rule is what makes it a surface, and the text on it still has to
    # clear AAA for body copy and AA for captions.
    run python3 -c "
import re, wcag
s = open('$TPL', encoding='utf-8').read()
body = re.search(r'\n  \.body \{(.*?)\n  \}', s, re.S).group(1)
bad = []
if 'background:' not in body:
    bad.append('no background')
if 'border' not in body:
    bad.append('no rule')
for theme in ('dark', 'light'):
    tok = wcag.tokens(s, theme)
    sep = wcag.ratio(tok['--ground'], tok['--raised'])
    if sep < 1.15:
        bad.append(f'{theme}:sep={sep:.2f}')
    if wcag.ratio(tok['--raised'], tok['--dim']) < 7.0:
        bad.append(f'{theme}:dim')
    if wcag.ratio(tok['--raised'], tok['--faint']) < 4.5:
        bad.append(f'{theme}:faint')
print(','.join(bad) if bad else 'OK')
"
    [ "$output" = "OK" ]
}

@test "見出しに明朝体を使わない" {
    # Thin strokes at heading size read as washed out; one gothic family
    # throughout also keeps a heading consistent with the text it heads.
    # Only a declaration counts -- the comment explaining the choice names the
    # family too, and that is not a defect.
    [ "$(grep -cE 'font-family:[^;]*(Mincho|Yu Mincho)' "$TPL")" -eq 0 ]
    [ "$(grep -cE '(font-family|--serif):[^;]*serif;' "$TPL" | grep -v sans-serif)" -eq 0 ]
    [ "$(grep -cF 'var(--serif)' "$TPL")" -eq 0 ]
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

@test "表の部品が揃っている（見出し・桁揃え・良否）" {
    # A table without tabular-nums does not line its digits up, which is most of
    # the reason to use a table for numbers at all.
    run grep -cF 'font-variant-numeric: tabular-nums' "$TPL"
    [ "$status" -eq 0 ]
    run grep -cF 'caption' "$TPL"
    [ "$status" -eq 0 ]
    run grep -cE '\.(good|warn|bad)\s*\{' "$TPL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 3 ]
}

@test "ファイルパスの部品がある（控えめに読める）" {
    # The first thing a reader looks for in a row is which file it is about.
    # Small, monospace and faint: findable when looked for, quiet when not.
    run python3 -c "
import re
s = open('$TPL', encoding='utf-8').read()
m = re.search(r'\n  \.files \{(.*?)\n  \}', s, re.S)
if not m:
    print('missing')
else:
    b = m.group(1)
    size = float(re.search(r'font-size: ([\d.]+)rem', b).group(1))
    bad = []
    if 'var(--mono)' not in b:
        bad.append('not mono')
    if 'var(--faint)' not in b:
        bad.append('not faint')
    if size > 0.85:
        bad.append(f'{size}rem too large')
    print(','.join(bad) if bad else 'OK')
"
    [ "$output" = "OK" ]
}

@test "図の部品が揃っている（箱と矢印・状態つき）" {
    run grep -cE '\.flow\s' "$TPL"
    [ "$status" -eq 0 ]
    run grep -cE '\.flow \.step\.(blocked|pending|done)' "$TPL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 3 ]
}

@test "図の矢印が生成される（行末に取り残されない）" {
    # A standalone arrow element is a flex item that can end a wrapped line by
    # itself. Generating it from the following step ties the two together.
    run grep -cF '.flow .step + .step::after' "$TPL"
    [ "$status" -eq 0 ]
    # And the manual class must not exist, or a page using both doubles up.
    [ "$(grep -cE '\.flow \.arrow' "$TPL")" -eq 0 ]
    [ "$(grep -cE 'class="arrow"' "$TPL")" -eq 0 ]
}

@test "本文に空のカラムを作らない（幅が余って見えない）" {
    # The old body was a two-column grid whose second column nothing ever
    # filled, so an opened row was a narrow strip of text beside a wide blank.
    # Checked on the declaration, not on whichever rule happened to implement it.
    run python3 -c "
import re
s = open('$TPL', encoding='utf-8').read()
body = re.search(r'\n  \.body \{(.*?)\n  \}', s, re.S).group(1)
print('grid-columns' if 'grid-template-columns' in body else 'OK')
"
    [ "$output" = "OK" ]
}

@test "inline SVG がトークンで色付けされる（テーマに追従する）" {
    run grep -cE 'svg (text|\.stroke|\.fill)' "$TPL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}

@test "日本語が文節で折り返される（単語の途中で切れない）" {
    # Japanese may break between almost any two characters, so the default wrap
    # splits words down the middle. auto-phrase needs the content language to be
    # known, so lang="ja" is part of the fix, not decoration.
    run grep -cF 'word-break: auto-phrase' "$TPL"
    [ "$status" -eq 0 ]
    run grep -cF 'line-break: strict' "$TPL"
    [ "$status" -eq 0 ]
    run grep -cF 'class="wrap" lang="ja"' "$TPL"
    [ "$status" -eq 0 ]
}

@test "コードは文節で折り返さない" {
    # Phrase breaking inside a path or a command would put the break in a place
    # the reader cannot distinguish from the real text.
    run grep -cE 'pre, code \{ word-break: normal' "$TPL"
    [ "$status" -eq 0 ]
}

@test "行の見出しが太く大きい" {
    # The row title is the heading of its row; it was inheriting the body weight.
    run grep -cE '\.title \{[^}]*font-weight: 600' "$TPL"
    [ "$status" -eq 0 ]
    run python3 -c "
import re
s = open('$TPL', encoding='utf-8').read()
m = re.search(r'\.title \{([^}]*)\}', s)
size = re.search(r'font-size: ([\d.]+)rem', m.group(1))
print('OK' if size and float(size.group(1)) >= 1.15 else 'small')
"
    [ "$output" = "OK" ]
}

@test "節の見出しが見出しとして読める（大きさと主文字色）" {
    # h2 sets the page structure; at label size in a secondary colour it reads as
    # absent, so it takes --ink and a heading-sized step.
    run python3 -c "
import re
s = open('$TPL', encoding='utf-8').read()
m = re.search(r'\n  h2 \{(.*?)\n  \}', s, re.S).group(1)
size = float(re.search(r'font-size: ([\d.]+)rem', m).group(1))
weight = int(re.search(r'font-weight: (\d+)', m).group(1))
faint = '--faint' in m
print('OK' if size >= 1.0 and weight >= 600 and '--ink' in m else f'size={size} weight={weight} ink={"--ink" in m}')
"
    [ "$output" = "OK" ]
}

@test "コードの色がトークンで定義され、両テーマで読める" {
    # Highlighting is baked into the markup, so the colours are ordinary tokens
    # and have to clear AA against the code block's own ground, not the page's.
    run python3 -c "
import wcag
s = open('$TPL', encoding='utf-8').read()
bad = []
for theme in ('dark', 'light'):
    tok = wcag.tokens(s, theme)
    toks = [k for k in tok if k.startswith('--tok-')]
    if len(toks) < 7:
        bad.append(f'{theme}:only {len(toks)} tokens')
        continue
    for k in toks:
        r = wcag.ratio(tok['--sunken'], tok[k])
        if r < 4.5:
            bad.append(f'{theme}:{k}={r:.2f}')
print(','.join(bad) if bad else 'OK')
"
    [ "$output" = "OK" ]
}

@test "コードの色クラスが highlight-code の出力と一致する" {
    # The CSS names and the generator's class names are two lists that must
    # agree; if they drift the page renders code with no colour at all.
    run python3 -c "
import re, subprocess
css = set(re.findall(r'pre code \.([a-z]) \{', open('$TPL', encoding='utf-8').read()))
out = subprocess.run(['$REPO_DIR/bin/highlight-code', '--lang', 'python'],
                     input='# c\nx = \"s\"\nif 1: pass\n',
                     capture_output=True, text=True).stdout
emitted = set(re.findall(r'class=\"([a-z])\"', out))
missing = emitted - css
print(','.join(sorted(missing)) if missing else 'OK')
"
    [ "$output" = "OK" ]
}

@test "スクリプトに依存しない（mermaid 等を読み込まない）" {
    # No external script can load from a local file, and vendoring a diagram
    # library would dwarf the page it draws on.
    [ "$(grep -ciE '<script|mermaid' "$TPL")" -eq 0 ]
}

# Both themes answer to the same thresholds; only the :root block differs.
check_theme_contrast() {
    run python3 -c "
import wcag
tok = wcag.tokens(open('$TPL', encoding='utf-8').read(), '$1')
g = tok['--ground']
bad = []
# Primary and secondary text carry the page: hold them to AAA.
for k in ('--ink', '--dim'):
    if wcag.ratio(g, tok[k]) < 7.0:
        bad.append(f'{k}={wcag.ratio(g, tok[k]):.2f}<7')
# Accent, severity tones and captions only need AA.
for k in ('--accent', '--sev-high', '--sev-mid', '--sev-low', '--faint'):
    if wcag.ratio(g, tok[k]) < 4.5:
        bad.append(f'{k}={wcag.ratio(g, tok[k]):.2f}<4.5')
print(','.join(bad) if bad else 'OK')
"
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}

# bats derives an internal function name by transliterating the title, and
# non-ASCII collapses -- two titles differing only in Japanese become the same
# identifier and the file fails to load. Hence the ASCII light/dark markers.
@test "light テーマの文字コントラストが WCAG を満たす（既定）" {
    check_theme_contrast light
}

@test "dark テーマの文字コントラストも WCAG を満たす（トグル）" {
    check_theme_contrast dark
}
