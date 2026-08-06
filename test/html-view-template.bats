#!/usr/bin/env bats
# The html-view template carries design decisions that are easy to undo by
# accident -- following the OS theme, opening the details, letting prose run the
# full page width. These check the ones that have a right answer.
#
# bash 3.2 note: a mid-test [[ ]] is excluded from errexit and passes silently,
# so assertions here use [ ] and grep exit status only.

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
TPL="$REPO_DIR/claude/skills/html-view/template.html"
SKILL="$REPO_DIR/claude/skills/html-view/SKILL.md"

@test "template.html が存在する" {
    [ -f "$TPL" ]
}

@test "SKILL.md が template.html を参照している" {
    run grep -cF 'template.html' "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "対象を選択式で確定する手順がある" {
    # Guessing what to render produces a page the user did not ask for, and the
    # cost lands on them: they have to read it to find out it is wrong.
    run grep -cF 'AskUserQuestion' "$SKILL"
    [ "$status" -eq 0 ]
    run grep -cF '直前のやり取り' "$SKILL"
    [ "$status" -eq 0 ]
    # The section must come before the build steps, or it gets read too late.
    run python3 -c "
s = open('$SKILL', encoding='utf-8').read()
ask, build = s.find('## 対象の確定'), s.find('## 手順')
print('OK' if 0 < ask < build else f'ask={ask} build={build}')
"
    [ "$output" = "OK" ]
}

@test "OS のテーマに追従しない（prefers-color-scheme の media query がない）" {
    # The machine runs the OS in dark mode; following it serves a dark page no
    # matter how far the ground is lifted. Only the at-rule is forbidden -- the
    # comment explaining the decision names it too, and that is not a defect.
    [ "$(grep -cE '@media[^{]*prefers-color-scheme' "$TPL")" -eq 0 ]
}

@test "ライトは data-theme のトグルで用意されている" {
    # Dark is the default; light stays reachable but is not inherited from the OS.
    run grep -cF ':root[data-theme="light"]' "$TPL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "ライトとダークで同じトークン名が定義されている" {
    run python3 -c "
import re, sys
s = open('$TPL', encoding='utf-8').read()
blocks = re.findall(r':root(?:\[data-theme=\"light\"\])?\s*\{(.*?)\}', s, re.S)
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

@test "基準の文字サイズは 19px 以上" {
    run grep -cE 'font-size: (19|2[0-9])px' "$TPL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "地色が純白でも純黒でもない" {
    # Pure white is the brightest the display can emit; pure black maximises the
    # ratio against any text on it. Both ends are where halation lives.
    run python3 -c "
import re
s = open('$TPL', encoding='utf-8').read()
block = re.search(r':root\s*\{(.*?)\}', s, re.S).group(1)
g = dict(re.findall(r'(--[a-z-]+)\s*:\s*(#[0-9a-fA-F]{6})', block))['--ground']

def lum(h):
    c = [int(h[i:i+2], 16) / 255 for i in (1, 3, 5)]
    c = [(x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4) for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

print('OK' if 0.002 <= lum(g) <= 0.92 else f'{lum(g)*100:.2f}%')
"
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}

@test "本文のコントラストが高すぎない（ハレーションを避ける）" {
    # Contrast is not a "higher is better" axis. Black on white is 21:1 and the
    # glyphs bloom; body text is held inside 10-13:1, past AAA but short of the
    # range that strains. Checked in both themes.
    run python3 -c "
import re
s = open('$TPL', encoding='utf-8').read()

def lum(h):
    c = [int(h[i:i+2], 16) / 255 for i in (1, 3, 5)]
    c = [(x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4) for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

def ratio(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)

bad = []
for name, pat in (('dark', r':root\s*\{(.*?)\}'),
                  ('light', r':root\[data-theme=\"light\"\]\s*\{(.*?)\}')):
    tok = dict(re.findall(r'(--[a-z-]+)\s*:\s*(#[0-9a-fA-F]{6})',
                          re.search(pat, s, re.S).group(1)))
    r = ratio(tok['--ground'], tok['--ink'])
    if not 10.0 <= r <= 13.5:
        bad.append(f'{name}={r:.2f}')
print(','.join(bad) if bad else 'OK')
"
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}

@test "アニメーションを持たない（追視の負担を作らない）" {
    [ "$(grep -cE 'transition:|animation:' "$TPL")" -eq 0 ]
}

@test "ページ幅が 70-82rem に収まっている" {
    run python3 -c "
import re
s = open('$TPL', encoding='utf-8').read()
v = float(re.search(r'\.wrap \{[^}]*max-width: ([\d.]+)rem', s, re.S).group(1))
print('OK' if 70 <= v <= 82 else f'{v}rem')
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
import re
s = open('$TPL', encoding='utf-8').read()

def lum(h):
    c = [int(h[i:i+2], 16) / 255 for i in (1, 3, 5)]
    c = [(x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4) for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

def ratio(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)

body = re.search(r'\n  \.body \{(.*?)\n  \}', s, re.S).group(1)
bad = []
if 'background:' not in body:
    bad.append('no background')
if 'border' not in body:
    bad.append('no rule')
for name, pat in (('dark', r':root\s*\{(.*?)\n  \}'),
                  ('light', r':root\[data-theme=\"light\"\]\s*\{(.*?)\n  \}')):
    tok = dict(re.findall(r'(--[a-z-]+)\s*:\s*(#[0-9a-fA-F]{6})',
                          re.search(pat, s, re.S).group(1)))
    sep = ratio(tok['--ground'], tok['--raised'])
    if sep < 1.15:
        bad.append(f'{name}:sep={sep:.2f}')
    if ratio(tok['--raised'], tok['--dim']) < 7.0:
        bad.append(f'{name}:dim')
    if ratio(tok['--raised'], tok['--faint']) < 4.5:
        bad.append(f'{name}:faint')
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

@test "図表を既定にする指針が SKILL.md にある" {
    # Without a trigger list the rule degrades to "use them when obvious", which
    # is where it started.
    run grep -cF '既定を図表側に置く' "$SKILL"
    [ "$status" -eq 0 ]
    # The trigger table must actually list cases, not just state the principle.
    run python3 -c "
import re
s = open('$SKILL', encoding='utf-8').read()
sec = re.search(r'既定を図表側に置く.*?(?=\n情報の型)', s, re.S)
rows = len(re.findall(r'^\| .+ \| .+ \|$', sec.group(0), re.M)) if sec else 0
print('OK' if rows >= 6 else f'{rows} rows')
"
    [ "$output" = "OK" ]
}

@test "ファイルパスの規約が SKILL.md にある" {
    run grep -cF '触ったファイルのパスを添える' "$SKILL"
    [ "$status" -eq 0 ]
    run grep -cF 'リポジトリ相対パス' "$SKILL"
    [ "$status" -eq 0 ]
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

@test "節の見出しが薄すぎない" {
    # h2 was the faintest token at the smallest size, which reads as absent.
    run python3 -c "
import re
s = open('$TPL', encoding='utf-8').read()
m = re.search(r'\n  h2 \{(.*?)\n  \}', s, re.S).group(1)
size = float(re.search(r'font-size: ([\d.]+)rem', m).group(1))
weight = int(re.search(r'font-weight: (\d+)', m).group(1))
faint = '--faint' in m
print('OK' if size >= 0.82 and weight >= 600 and not faint else f'size={size} weight={weight} faint={faint}')
"
    [ "$output" = "OK" ]
}

@test "コードの色がトークンで定義され、両テーマで読める" {
    # Highlighting is baked into the markup, so the colours are ordinary tokens
    # and have to clear AA against the code block's own ground, not the page's.
    run python3 -c "
import re
s = open('$TPL', encoding='utf-8').read()

def lum(h):
    c = [int(h[i:i+2], 16) / 255 for i in (1, 3, 5)]
    c = [(x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4) for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

def ratio(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)

bad = []
for name, pat in (('dark', r':root\s*\{(.*?)\n  \}'),
                  ('light', r':root\[data-theme=\"light\"\]\s*\{(.*?)\n  \}')):
    tok = dict(re.findall(r'(--[a-z-]+)\s*:\s*(#[0-9a-fA-F]{6})',
                          re.search(pat, s, re.S).group(1)))
    toks = [k for k in tok if k.startswith('--tok-')]
    if len(toks) < 7:
        bad.append(f'{name}:only {len(toks)} tokens')
        continue
    for k in toks:
        r = ratio(tok['--sunken'], tok[k])
        if r < 4.5:
            bad.append(f'{name}:{k}={r:.2f}')
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

# bats derives an internal function name by transliterating the title, and
# non-ASCII collapses -- two titles differing only in Japanese become the same
# identifier and the file fails to load. Hence the ASCII light/dark markers.
@test "dark テーマの文字コントラストが WCAG を満たす（既定）" {
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

@test "light テーマの文字コントラストも WCAG を満たす（トグル）" {
    run python3 -c "
import re
s = open('$TPL', encoding='utf-8').read()
block = re.search(r':root\[data-theme=\"light\"\]\s*\{(.*?)\}', s, re.S).group(1)
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
