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

# --- ハーネス参照は ~/.claude から解決する ---
#
# スキルや agent は作業中リポジトリを cwd にして動く。`claude/...` のような
# リポジトリ相対パスや `~/dotfiles` 固定パスは dotfiles の外で解決できない。
# ~/.claude はどのアカウントでもこのリポジトリの claude/ を指す。

# claude/ 配下の md と settings.json で、引数の固定文字列を含む行の件数を出す
claude_ref_hits() {
  grep -rnF --include='*.md' --include='settings.json' --exclude-dir=synced \
    -- "$1" "$REPO_DIR/claude" | grep -c . || true
}

@test "参照文書は agents/ の外にある（agent として登録されない）" {
  n=$(find "$REPO_DIR/claude/agents" -path '*/references*' | grep -c . || true)
  [ "$n" -eq 0 ]
  [ -f "$REPO_DIR/claude/skills/_shared/references/evidence-catalog.md" ]
  [ -f "$REPO_DIR/claude/skills/_shared/references/criteria-template.md" ]
}

@test "claude/ の md と settings.json に agents/references への参照が無い" {
  claude_ref_hits 'agents/references' >&2
  [ "$(claude_ref_hits 'agents/references')" -eq 0 ]
}

@test "phase-auditor は evidence-catalog を ~/.claude から読む" {
  grep -qF '~/.claude/skills/_shared/references/evidence-catalog.md' \
    "$REPO_DIR/claude/agents/phase-auditor.md"
}

@test "settings.json の hook は ~/dotfiles を経由しない" {
  [ "$(claude_ref_hits '${HOME}/dotfiles/claude/hooks')" -eq 0 ]
  [ "$(claude_ref_hits '~/dotfiles/claude/hooks')" -eq 0 ]
  jq -r '.. | .command? // empty' "$REPO_DIR/claude/settings.json" \
    | grep -qF '${HOME}/.claude/hooks/distill-record.sh'
}

@test "handover-lib は ~/.claude から読み込む" {
  [ "$(claude_ref_hits 'dotfiles/claude/skills/handover/scripts')" -eq 0 ]
}

@test "pptx-dev のスクリプトは cwd に依らず ~/.claude から呼ぶ" {
  f="$REPO_DIR/claude/skills/pptx-dev/SKILL.md"
  n=$(grep -c 'uv --directory claude/' "$f" || true)
  [ "$n" -eq 0 ]
  n=$(grep -cF 'uv --directory "$HOME/.claude/skills/pptx-dev/scripts"' "$f" || true)
  [ "$n" -eq 2 ]
  # 相対パスの引数は uv --directory の下で解決先が変わるので、$PWD で絶対化する
  n=$(grep -cE '^ +--[a-z]+ \.pptx-dev/' "$f" || true)
  [ "$n" -eq 0 ]
}

@test "kaizen はスキル一覧を ~/.claude から読む" {
  f="$REPO_DIR/claude/skills/kaizen/SKILL.md"
  n=$(grep -cF '`claude/skills/*/SKILL.md`' "$f" || true)
  [ "$n" -eq 0 ]
  grep -qF '`~/.claude/skills/*/SKILL.md`' "$f"
}

@test "session-bridge の受け渡し場所はアカウントに依存しない" {
  f="$REPO_DIR/claude/skills/session-bridge/SKILL.md"
  n=$(grep -cF '.claude/session-bridge' "$f" || true)
  [ "$n" -eq 0 ]
  grep -qF '~/.local/state/session-bridge/' "$f"
}

@test "skills-audit の棚卸しは synced/ を除く" {
  grep -qF 'claude/skills/synced/' "$REPO_DIR/claude/skills/skills-audit/SKILL.md"
}
