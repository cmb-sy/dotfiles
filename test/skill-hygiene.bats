#!/usr/bin/env bats
# test/skill-hygiene.bats — SKILL.md is an instruction sheet, not a changelog.

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

for path in sorted(pathlib.Path(sys.argv[1]).rglob('SKILL.md')):
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

@test "no SKILL.md carries a dated change note" {
  found="$(skill_findings_of_kind dated)"
  echo "$found"
  hits=$(echo "$found" | grep -c . ) || hits=0
  [ "$hits" -eq 0 ]
}

@test "no SKILL.md describes what it absorbed or replaced" {
  found="$(skill_findings_of_kind lineage)"
  echo "$found"
  hits=$(echo "$found" | grep -c . ) || hits=0
  [ "$hits" -eq 0 ]
}

@test "no SKILL.md records that something was removed" {
  found="$(skill_findings_of_kind removal)"
  echo "$found"
  hits=$(echo "$found" | grep -c . ) || hits=0
  [ "$hits" -eq 0 ]
}
