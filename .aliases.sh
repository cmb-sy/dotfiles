#!/bin/sh

# ----------------------------------------------------------
# Shell Commands
# ----------------------------------------------------------
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
if command -v gls >/dev/null 2>&1; then
  export LS_COLORS='di=34:fi=37'
  alias ls='gls --color=auto'
  alias l='gls --color=auto'
  alias la='gls -a --color=auto'
else
  alias l='ls'
  alias la='ls -a'
fi

# ----------------------------------------------------------
# Docker
# ----------------------------------------------------------
alias d='docker'
alias dc='docker compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias dimg='docker images'

# ----------------------------------------------------------
# Claude Code (multi-account via CLAUDE_CONFIG_DIR)
# ----------------------------------------------------------
# One-time setup:
#   1. Create per-account config dirs if missing, e.g.:
#        ~/.claude-private  (personal)
#        ~/.claude-work     (company)
#      Use mkdir, or mv ~/.claude ~/.claude-private if migrating an existing tree.
#   2. Sign in once per account (either approach):
#        - Recommended: run `clp` and `clw` once each and complete login in the UI.
#        - Or: CLAUDE_CONFIG_DIR=~/.claude-private claude
#              CLAUDE_CONFIG_DIR=~/.claude-work claude
#   3. Share dotfiles-backed config into both dirs (once), if not already done
#      (e.g. setup.zsh may run this): `claude-link-shared`, or:
#        zsh "${DOTFILES:-${HOME}/dotfiles}/claude/link-shared-config.zsh"
#   4. Make ~/.claude a symlink (not a plain directory), or clp/clw may not behave
#      as intended. Example default target (pick one):
#        ln -sfn ~/.claude-private ~/.claude
# Daily: `clp` / `clw` switch account + launch; `clpa` / `clwa` same + autonomous mode.
# New terminals do not inherit CLAUDE_CONFIG_DIR; ~/.claude symlink persists.
# ----------------------------------------------------------
: "${CLAUDE_ACCOUNT_PRIVATE_DIR:=${HOME}/.claude-private}"
: "${CLAUDE_ACCOUNT_WORK_DIR:=${HOME}/.claude-work}"

  _claude_account_link() {
    local target="$1"
    ln -sfn "$target" "${HOME}/.claude"
  }

  claude-use-private() {
    _claude_account_link "${CLAUDE_ACCOUNT_PRIVATE_DIR}"
    export CLAUDE_CONFIG_DIR="${CLAUDE_ACCOUNT_PRIVATE_DIR}"
  }

  claude-use-work() {
    _claude_account_link "${CLAUDE_ACCOUNT_WORK_DIR}"
    export CLAUDE_CONFIG_DIR="${CLAUDE_ACCOUNT_WORK_DIR}"
  }

_claude_require_cli() {
  if ! command -v claude >/dev/null 2>&1; then
    echo "claude command not found on PATH." >&2
    return 127
  fi
}

_claude_sync_shared() {
  local d="${DOTFILES:-${HOME}/dotfiles}"
  CLAUDE_LINK_SHARED_QUIET=1 zsh "$d/claude/link-shared-config.zsh" >/dev/null 2>&1
}

claude-private() {
  _claude_require_cli || return $?
  _claude_sync_shared
  claude-use-private
  command claude "$@"
}

claude-work() {
  _claude_require_cli || return $?
  _claude_sync_shared
  claude-use-work
  command claude "$@"
}

# Short: clp / clw / clpa / clwa
clp() {
  claude-private "$@"
}

clw() {
  claude-work "$@"
}

_claude_autonomous_default_prompt='Implement the requested changes. Run tests, fix failures, and repeat until all tests pass.'

clpa() {
  _claude_require_cli || return $?
  _claude_sync_shared
  claude-use-private
  local q="$*"
  [ -z "$q" ] && q="$_claude_autonomous_default_prompt"
  command claude --dangerously-skip-permissions "$q"
}

clwa() {
  _claude_require_cli || return $?
  _claude_sync_shared
  claude-use-work
  local q="$*"
  [ -z "$q" ] && q="$_claude_autonomous_default_prompt"
  command claude --dangerously-skip-permissions "$q"
}

alias claude-auto='clwa'

claude-link-shared() {
  local d="${DOTFILES:-${HOME}/dotfiles}"
  zsh "$d/claude/link-shared-config.zsh"
}

if [ -n "${ZSH_VERSION-}" ]; then
  builtin unfunction cla 2>/dev/null
  unalias cla cl 2>/dev/null
fi

# ----------------------------------------------------------
# Others
# ----------------------------------------------------------
alias tenki='wttr'
alias h='history'
alias grep='grep --color=auto'
