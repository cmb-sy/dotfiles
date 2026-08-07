#!/usr/bin/env bats
# test/skill-refs.bats — every relative reference in a SKILL.md must exist.
# Guards against the feature-dev case: 11 references that never existed.

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

@test "SKILL.md relative references resolve to real files" {
  missing=0
  while IFS= read -r skill; do
    dir="$(dirname "$skill")"
    # Extract ./xxx.md and ../xxx.md style references
    while IFS= read -r ref; do
      target="$dir/$ref"
      if [ ! -e "$target" ]; then
        echo "MISSING: $skill -> $ref"
        missing=$((missing + 1))
      fi
    done < <(grep -oE '\.\.?/[A-Za-z0-9_/.-]+\.md' "$skill" | sort -u)
  done < <(find "$REPO_DIR/claude/skills" -maxdepth 2 -name SKILL.md)
  [ "$missing" -eq 0 ]
}

@test "_shared directory carries no SKILL.md (must not be discovered as a skill)" {
  count=$(find "$REPO_DIR/claude/skills/_shared" -name SKILL.md 2>/dev/null | grep -c . || true)
  [ "$count" -eq 0 ]
}
