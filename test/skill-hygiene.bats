#!/usr/bin/env bats
# test/skill-hygiene.bats — SKILL.md is an instruction sheet, not a changelog.

load "helpers/common"

# Each date occurrence with its surrounding words, so the allowed forms can be
# told apart from a change note: a condition boundary (「2026-07-10 以前の旧
# リンク」= live compat branch) and a format example (「例: 2026-07-22 締切分」).
skill_dated_notes() {
  grep -rnoE '.{0,12}20[0-9][0-9]-[0-9]{2}-[0-9]{2} [^ ]*' \
    "$REPO_DIR/claude/skills" --include=SKILL.md |
    grep -vE '例|以前|以降|時点'
}

# Lineage of a merged or renamed skill. A live compat rule states the rule
# itself (「旧リンクも同一視する」), so it does not name a former skill.
skill_lineage_notes() {
  grep -rnE '旧 [A-Za-z-]+ (を吸収|互換)|旧 [A-Za-z-]+）' \
    "$REPO_DIR/claude/skills" --include=SKILL.md
}

@test "no SKILL.md carries a dated change note" {
  found="$(skill_dated_notes || true)"
  echo "$found"
  hits=$(echo "$found" | grep -c . ) || hits=0
  [ "$hits" -eq 0 ]
}

@test "no SKILL.md describes what it absorbed or replaced" {
  found="$(skill_lineage_notes || true)"
  echo "$found"
  hits=$(echo "$found" | grep -c . ) || hits=0
  [ "$hits" -eq 0 ]
}
