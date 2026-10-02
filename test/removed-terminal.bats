#!/usr/bin/env bats
# The removed terminal (spelled by concatenation so this file does not match itself)
# must not be referenced outside docs/.

load "helpers/common"

@test "docs/ 以外に撤去済みターミナルへの参照が残っていない" {
  gone="wez""term"
  hits=$(git -C "$REPO_DIR" grep -n -i "$gone" -- ':!docs' | grep -c .) || hits=0
  [ "$hits" -eq 0 ]
  [ ! -e "$REPO_DIR/terminal/$gone" ]
}
