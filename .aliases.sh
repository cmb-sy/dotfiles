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
# When Claude Code is missing, keep `cl` as clear; otherwise defined below as personal launcher
if ! command -v claude >/dev/null 2>&1; then
  alias cl='clear'
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
# Claude Code
# ----------------------------------------------------------
if command -v claude >/dev/null 2>&1; then
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

  claude-private() {
    claude-use-private
    command claude "$@"
  }

  claude-work() {
    claude-use-work
    command claude "$@"
  }

  _claude_autonomous_default_prompt='Implement the requested changes. Run tests, fix failures, and repeat until all tests pass.'

  # Short: clp/clw = normal, clpa/clwa = autonomous
  clp() {
    claude-private "$@"
  }

  clw() {
    claude-work "$@"
  }

  clpa() {
    claude-use-private
    local q="$*"
    [ -z "$q" ] && q="$_claude_autonomous_default_prompt"
    command claude --dangerously-skip-permissions "$q"
  }

  clwa() {
    claude-use-work
    local q="$*"
    [ -z "$q" ] && q="$_claude_autonomous_default_prompt"
    command claude --dangerously-skip-permissions "$q"
  }

  cl() {
    clp "$@"
  }

  alias claude-auto='clpa'
fi

# ----------------------------------------------------------
# Others
# ----------------------------------------------------------
alias tenki='wttr'
alias h='history'
alias grep='grep --color=auto'
