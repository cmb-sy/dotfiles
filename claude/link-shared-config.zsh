#!/bin/zsh
# Symlink shared Claude Code config from this repo into both account dirs.
# See English setup comments in .aliases.sh (Claude Code section).

emulate -L zsh

: "${DOTFILES:=${DOTFILES_DIR:-$HOME/dotfiles}}"
: "${CLAUDE_ACCOUNT_PRIVATE_DIR:=$HOME/.claude-private}"
: "${CLAUDE_ACCOUNT_WORK_DIR:=$HOME/.claude-work}"
: "${CLAUDE_LINK_SHARED_QUIET:=0}"
_backup_suffix="$(date +%Y%m%d-%H%M%S)"

_msg() {
  [[ "$CLAUDE_LINK_SHARED_QUIET" == "1" ]] && return 0
  print -- "$@"
}

_warn() {
  [[ "$CLAUDE_LINK_SHARED_QUIET" == "1" ]] && return 0
  print -u2 -- "$@"
}

if [[ ! -d "$DOTFILES/claude" ]]; then
  _warn "link-shared-config: missing $DOTFILES/claude"
  exit 1
fi

_link_into() {
  local root="$1"
  [[ -n "$root" ]] || return 1
  mkdir -p "$root"

  local name src dst backup
  for name in settings.json hooks statusline.sh skills agents CLAUDE.md; do
    src="$DOTFILES/claude/$name"
    [[ -e "$src" ]] || continue
    dst="$root/$name"
    if [[ -e "$dst" && ! -L "$dst" ]]; then
      backup="${dst}.bak-${_backup_suffix}"
      while [[ -e "$backup" ]]; do
        backup="${dst}.bak-${_backup_suffix}-$RANDOM"
      done
      mv "$dst" "$backup"
      _warn "link-shared-config: moved existing $dst -> $backup"
    fi
    ln -sfn "$src" "$dst"
    _msg "linked $dst -> $src"
  done
}

_link_into "$CLAUDE_ACCOUNT_PRIVATE_DIR"
_link_into "$CLAUDE_ACCOUNT_WORK_DIR"
_msg "done (private + work). Credentials stay under each directory."
