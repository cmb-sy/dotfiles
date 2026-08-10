#!/usr/bin/env bats
# test/docs-refs.bats — a doc referenced from code must survive a fresh clone.

load "helpers/common"

@test "every doc referenced from code is tracked by git" {
  cd "$REPO_DIR"
  missing=0
  while IFS= read -r doc; do
    [ -z "$doc" ] && continue
    [ -e "$doc" ] || continue
    tracked=$(git ls-files --error-unmatch "$doc" 2>/dev/null | grep -c .) || tracked=0
    if [ "$tracked" -eq 0 ]; then
      echo "UNTRACKED: $doc"
      missing=$((missing + 1))
    fi
  done < <(grep -rhoE 'docs/[A-Za-z0-9_/.-]+\.md' bin setup macos claude server 2>/dev/null | sort -u)
  [ "$missing" -eq 0 ]
}

# The check above skips paths that do not exist, because skills legitimately
# contain example paths (docs/plans/2026-03-06-xxx-design.md is a format sample).
# Shell and plist files carry no such samples, so there a missing target is a
# dangling reference — the exact thing this file exists to prevent.
@test "no shell or plist references a doc that does not exist" {
  cd "$REPO_DIR"
  dangling=0
  while IFS= read -r doc; do
    [ -z "$doc" ] && continue
    if [ ! -e "$doc" ]; then
      echo "DANGLING: $doc"
      dangling=$((dangling + 1))
    fi
  done < <(grep -rhoE 'docs/[A-Za-z0-9_/.-]+\.md' \
             --include='*.sh' --include='*.zsh' --include='*.plist' \
             bin setup macos server 2>/dev/null | sort -u
           grep -hoE 'docs/[A-Za-z0-9_/.-]+\.md' \
             $(git ls-files bin | xargs grep -lE '^#!' 2>/dev/null) 2>/dev/null | sort -u)
  [ "$dangling" -eq 0 ]
}
