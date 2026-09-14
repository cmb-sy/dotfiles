#!/usr/bin/env bats
# test/skill-hygiene.bats — a skill md is an instruction sheet, not a changelog.

load "helpers/common"

# Prints one finding per line as "<kind> <file>:<line>: <match>".
#
# What stays allowed is the wording that an instruction needs:
#   - a date inside a `code span` or a path (`docs/plans/2026-03-06-x.md`) is a
#     format example, not a record of change
#   - a live compat rule says what to do (「2026-07-10 以前の旧リンクも同一視
#     する」), so a nearby 以前 / 場合 / 同一視 marks a condition, not history
skill_history_findings() {
  python3 - "$REPO_DIR/claude/skills" <<'PY'
import pathlib, re, sys

DATE = re.compile(r'20\d\d-\d\d(?:-\d\d)?|\d{1,2}月\d{1,2}日')
LINEAGE = re.compile(r'旧 [A-Za-z][A-Za-z0-9_-]*')
REMOVAL = re.compile(r'[はをも]廃止')
LIVE = re.compile(r'以前|以降|時点|なら|場合|とき|使わない|同一視|受け付け')

# Every md a skill loads, not only SKILL.md: shared specs, references and
# done-criteria are read at run time too, so the rule applies there as well.
for path in sorted(pathlib.Path(sys.argv[1]).rglob('*.md')):
    for num, line in enumerate(path.read_text().splitlines(), 1):
        bare = re.sub(r'`[^`]*`', '', line)
        for kind, pattern in (('dated', DATE), ('lineage', LINEAGE), ('removal', REMOVAL)):
            for hit in pattern.finditer(bare):
                head, tail = bare[:hit.start()], bare[hit.end():hit.end() + 12]
                if kind == 'dated' and (tail[:1] in '-.' or head[-1:] == '/'):
                    continue
                if LIVE.search(tail) or LIVE.search(head[-12:]):
                    continue
                print(f'{kind} {path}:{num}: {hit.group(0)}')
PY
}

skill_findings_of_kind() {
  skill_history_findings | grep "^$1 " || true
}

@test "no skill md carries a dated change note" {
  found="$(skill_findings_of_kind dated)"
  echo "$found"
  hits=$(echo "$found" | grep -c . ) || hits=0
  [ "$hits" -eq 0 ]
}

@test "no skill md describes what it absorbed or replaced" {
  found="$(skill_findings_of_kind lineage)"
  echo "$found"
  hits=$(echo "$found" | grep -c . ) || hits=0
  [ "$hits" -eq 0 ]
}

@test "no skill md records that something was removed" {
  found="$(skill_findings_of_kind removal)"
  echo "$found"
  hits=$(echo "$found" | grep -c . ) || hits=0
  [ "$hits" -eq 0 ]
}

# --- 外向き操作の承認ゲート ---
#
# 手順書に「起票する」「投稿する」と書くと、それが実行の許可として読まれる。
# issue は他メンバーへ通知が飛び、削除しても既読の痕跡は消えない。書いてよいのは
# 内容の指針までで、実行のタイミングは毎回ユーザーが決める。
#
# 検査は「承認」という語の件数ではなく、打ち消しの宣言そのものに当てる。語を
# 数えるだけだと、無関係な文脈の「承認」に当たって空振りする。
# 拾うのは命令形だけ。語だけで探すと、業務語彙の言い換え表に載っている
# 「`gh issue create` で起票」のような用例に当たって空振りする。
outward_skills() {  # 外向き操作を指示している SKILL.md を列挙
  grep -rl '起票する\|Slack へ投稿する\|外部サービスへ共有する' \
    "$REPO_DIR"/claude/skills/*/SKILL.md
}

# 2 つを別々に求める。片方だけだと、もう片方を消しても検査が通ってしまう。
#   打ち消し = この記述は実行の許可ではない、という明示
#   待ち     = 承認が来るまで投稿しない、という手順
@test "起票を指示するスキルは、それが許可でないことを明示している" {
  missing=""
  for f in $(outward_skills); do
    n=$(grep -c '許可ではない' "$f") || n=0
    [ "$n" -gt 0 ] || missing="$missing ${f#"$REPO_DIR"/claude/skills/}"
  done
  [ -z "$missing" ] || { echo "「許可ではない」の明示が無い:$missing"; return 1; }
}

@test "起票を指示するスキルは、承認を待つ手順を持っている" {
  missing=""
  for f in $(outward_skills); do
    n=$(grep -c '承認を得てから\|承認を待つ\|草案を提示して止まる\|草案だけを見せる' "$f") || n=0
    [ "$n" -gt 0 ] || missing="$missing ${f#"$REPO_DIR"/claude/skills/}"
  done
  [ -z "$missing" ] || { echo "承認を待つ手順が無い:$missing"; return 1; }
}

# 打ち消しは「起票する」と同じ節に無いと届かない。ファイルのどこかにあれば
# よいことにすると、別の節（Phase 6 の「承認つき適用」等）に当たって空振りする。
@test "起票を指示する節に、打ち消しの宣言が同じ節内にある" {
  run python3 -c "
import glob, re, sys
NG = []
for path in sorted(glob.glob('$REPO_DIR/claude/skills/*/SKILL.md')):
    text = open(path, encoding='utf-8').read()
    # '## ' 見出しで節に割る
    parts = re.split(r'^(## .*)\$', text, flags=re.M)
    secs = list(zip(parts[1::2], parts[2::2]))
    for head, body in secs:
        # 起票のやり方を書いている節だけを見る。禁止事項の一覧（Red Flags）にも
        # 「起票する」は現れるが、そこは打ち消しの置き場ではない。手順の節は
        # 必ず起票の入口（/github-issues）を名指しするので、それで見分ける。
        if '起票する' not in body or '/github-issues' not in body:
            continue
        whole = head + body
        if '許可ではない' not in whole:
            NG.append(path.split('/skills/')[1] + ' / ' + head.strip())
print(','.join(NG) if NG else 'OK')
"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF "OK"
}
