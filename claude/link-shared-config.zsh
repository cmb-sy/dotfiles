#!/bin/zsh
# Symlink shared Claude Code config from this repo into both account dirs.
# See English setup comments in .aliases.sh (Claude Code section).

emulate -L zsh

: "${DOTFILES:=${DOTFILES_DIR:-$HOME/dotfiles}}"
: "${CLAUDE_ACCOUNT_PRIVATE_DIR:=$HOME/.claude-private}"
: "${CLAUDE_ACCOUNT_WORK_DIR:=$HOME/.claude-work}"

if [[ ! -d "$DOTFILES/claude" ]]; then
  print -u2 "link-shared-config: missing $DOTFILES/claude"
  exit 1
fi

_link_into() {
  local root="$1"
  [[ -n "$root" ]] || return 1
  mkdir -p "$root"

  local name src dst
  for name in settings.json hooks statusline.sh skills agents; do
    src="$DOTFILES/claude/$name"
    [[ -e "$src" ]] || continue
    dst="$root/$name"
    if [[ -e "$dst" && ! -L "$dst" ]]; then
      print -u2 "link-shared-config: skip $name (exists and not a symlink): $dst"
      continue
    fi
    ln -sfn "$src" "$dst"
    print "linked $dst -> $src"
  done
}

_link_into "$CLAUDE_ACCOUNT_PRIVATE_DIR"
_link_into "$CLAUDE_ACCOUNT_WORK_DIR"
print "done (private + work). Credentials stay under each directory."
