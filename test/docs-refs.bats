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
