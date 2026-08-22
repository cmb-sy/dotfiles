#!/usr/bin/env bats
# test/skill-refs.bats — every relative reference in a SKILL.md must exist.
# Guards against the feature-dev case: 11 references that never existed.

load "helpers/common"

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

# CLAUDE.md が存在しないスキルを名指ししていると、実行時に「呼べないスキル」を
# 呼びにいくことになる。スキルの改名・統合はこのリポジトリで実際に起きており
# （explain-basics → learn → 統合、tech-memo → distill-personal-memo → 消滅）、
# 参照側の追従漏れを人間の記憶で防ぐのは無理がある。
@test "CLAUDE.md が名指しするスキルはすべて実在する" {
  missing=0
  # `/skill-name` 形式の言及を拾い、skills/ に実体があるか確かめる。
  # スラッシュ始まりのパス断片を除くため、直後が英小文字とハイフンのみのものに限る。
  for name in $(grep -oE '`/[a-z][a-z0-9-]+`' "$REPO_DIR/claude/CLAUDE.md" \
                  | tr -d '`/' | sort -u); do
    [ -d "$REPO_DIR/claude/skills/$name" ] && continue
    # superpowers 等のプラグイン由来スキルは skills/ に無いので除外する
    case "$name" in brainstorming|writing-plans|subagent-driven-development) continue ;; esac
    echo "missing skill: /$name" >&2
    missing=$((missing + 1))
  done
  [ "$missing" -eq 0 ]
}
