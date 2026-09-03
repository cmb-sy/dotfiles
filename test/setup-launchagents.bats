#!/usr/bin/env bats

load "helpers/common"

# Every user LaunchAgent in macos/, so adding one does not need this file edited.
#
# The __DOTFILES__ placeholder is what separates them from the system daemon
# alongside: an agent runs a script out of this repo, so install.zsh has to
# substitute the repo path into it. The daemon calls sysctl by absolute path and
# is loaded into a different domain, so the rules below do not apply to it.
agent_plists() {
  grep -l '__DOTFILES__' "$REPO_DIR"/macos/*.plist
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
    [ "$prog" = "$REPO_DIR/bin/${label#local.}" ]
    [ -x "$prog" ]
    leftovers=$(grep -c '__DOTFILES__' "$out") || leftovers=0
    [ "$leftovers" -eq 0 ]
  done < <(agent_plists)
}

@test "every user LaunchAgent label is prefixed local." {
  # Structural, so the rule holds without naming what it excludes: a label
  # carrying a person or a domain fails on the prefix alone.
  offenders=0
  while IFS= read -r plist; do
    label=$(/usr/libexec/PlistBuddy -c 'Print :Label' "$plist")
    case "$label" in
      local.*) : ;;
      *) echo "NOT local.: $label"; offenders=$((offenders + 1)) ;;
    esac
    base=$(basename "$plist" .plist)
    [ "$base" = "$label" ] || { echo "FILENAME != LABEL: $plist"; offenders=$((offenders + 1)); }
  done < <(agent_plists)
  [ "$offenders" -eq 0 ]
}

@test "tracked files carry no account name" {
  # The name is read from the running account rather than written here: spelling
  # it out in the assertion would put back the very string being excluded.
  me=$(id -un)
  # Too short to grep for without matching ordinary words.
  [ "${#me}" -ge 4 ] || skip "account name too short to search for safely"
  hits=$(git grep -l -i -- "$me" 2>/dev/null | grep -c .) || hits=0
  if [ "$hits" -ne 0 ]; then git grep -l -i -- "$me" 2>/dev/null; fi
  [ "$hits" -eq 0 ]
}
