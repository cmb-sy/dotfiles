#!/usr/bin/env bats
# The html-view SKILL.md carries the instructions that decide how deep a page
# goes and what it must contain. Prose decays quietly -- a dropped table turns a
# concrete rule back into a platitude -- so the parameters are checked here.
# The rendered template is checked separately, in html-view-template.bats.

load "helpers/common"

TPL="$REPO_DIR/claude/skills/html-view/template.html"
SKILL="$REPO_DIR/claude/skills/html-view/SKILL.md"

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

@test "深さの 4 パラメータが SKILL.md にある" {
    # Depth is not one dial. Reader/decision and item structure set the
    # direction, verification sets the cost, and the bounds control variance.
    run python3 -c "
import re
s = open('$SKILL', encoding='utf-8').read()
need = ['読者と判断', '項目の構成', '情報源と検証', '分量の上下限']
print(','.join(n for n in need if n not in s) or 'OK')
"
    [ "$output" = "OK" ]
}

@test "5 スロットが template と SKILL.md の両方に揃っている" {
    # The slots are the mechanism; the prose only names them. If the template
    # loses one, the page silently stops asking for it.
    run python3 -c "
import re
tpl = open('$TPL', encoding='utf-8').read()
skl = open('$SKILL', encoding='utf-8').read()
slots = ['前提', '実装', 'なぜこの選択か', '無いと壊れるもの', '採らなかった案']
dl = re.search(r'<dl class=\"aspects\">(.*?)</dl>', tpl, re.S)
bad = []
if not dl:
    bad.append('no dl')
else:
    dts = re.findall(r'<dt>([^<]+)</dt>', dl.group(1))
    if len(dts) != 5:
        bad.append(f'{len(dts)} slots')
    bad += [f'tpl:{x}' for x in slots if x not in dts]
bad += [f'skill:{x}' for x in slots if x not in skl]
print(','.join(bad) if bad else 'OK')
"
    [ "$output" = "OK" ]
}

@test "一次情報がタスク別に具体化されている" {
    # This is the parameter that actually moves effort, and it is the one that
    # decays into "check your sources" if the per-task table is dropped.
    run python3 -c "
import re
s = open('$SKILL', encoding='utf-8').read()
sec = re.search(r'### ③ 情報源と検証(.*?)(?=\n### )', s, re.S)
if not sec:
    print('missing section')
else:
    body = sec.group(1)
    rows = len(re.findall(r'^\| .+ \| .+ \| .+ \|$', body, re.M)) - 1   # minus header
    kinds = ['PR レビュー', '技術選定', '障害', '設計レビュー', '学習教材']
    miss = [k for k in kinds if k not in body]
    print(f'rows={rows}' if rows < 5 else (','.join(miss) if miss else 'OK'))
"
    [ "$output" = "OK" ]
}

@test "分量に上限と下限の両方がある" {
    # A floor alone invites padding; a ceiling alone invites skimping.
    run python3 -c "
import re
s = open('$SKILL', encoding='utf-8').read()
sec = re.search(r'### ④ 分量の上下限(.*?)(?=\n### )', s, re.S).group(1)
print('OK' if '下限' in sec and '上限' in sec and re.search(r'\d+ 行', sec) else 'incomplete')
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
