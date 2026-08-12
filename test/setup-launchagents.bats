#!/usr/bin/env bats

load "helpers/common"

# Every user LaunchAgent in macos/, so adding one does not need this file edited.
agent_plists() {
  ls "$REPO_DIR"/macos/com.snakashima.*.plist
}

@test "user plists carry no hardcoded user path" {
  offenders=0
  while IFS= read -r plist; do
    hits=$(grep -c '/Users/' "$plist") || hits=0
    if [ "$hits" -ne 0 ]; then echo "HARDCODED: $plist"; offenders=$((offenders + 1)); fi
  done < <(agent_plists)
  [ "$offenders" -eq 0 ]
}

@test "install.zsh installs every user LaunchAgent" {
  missing=0
  while IFS= read -r plist; do
    label=$(basename "$plist" .plist)
    hits=$(grep -cF "$label" "$REPO_DIR/setup/install.zsh") || hits=0
    if [ "$hits" -eq 0 ]; then echo "NOT INSTALLED: $label"; missing=$((missing + 1)); fi
  done < <(agent_plists)
  [ "$missing" -eq 0 ]
}

@test "install.zsh substitutes and bootstraps on live code, not in a comment" {
  code=$(grep -v '^[[:space:]]*#' "$REPO_DIR/setup/install.zsh")
  printf '%s' "$code" | grep -qF 'sed "s|__DOTFILES__|'
  printf '%s' "$code" | grep -qF 'launchctl bootstrap "gui/$(id -u)"'
}

@test "plist placeholder substitution produces loadable plists" {
  while IFS= read -r plist; do
    label=$(basename "$plist" .plist)
    out="$BATS_TEST_TMPDIR/$label.plist"
    sed "s|__DOTFILES__|$REPO_DIR|g" "$plist" > "$out"
    plutil -lint "$out"
    # The program must be the executable the agent is named after, not merely
    # something executable: a plist pointing at /bin/ls would otherwise pass.
    prog=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$out")
    [ "$prog" = "$REPO_DIR/bin/${label#com.snakashima.}" ]
    [ -x "$prog" ]
    leftovers=$(grep -c '__DOTFILES__' "$out") || leftovers=0
    [ "$leftovers" -eq 0 ]
  done < <(agent_plists)
}
