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
alias cl='clear'

# ----------------------------------------------------------
# Docker
# ----------------------------------------------------------
alias d='docker'
alias dc='docker compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias dimg='docker images'

# ----------------------------------------------------------
# Claude
# ----------------------------------------------------------
if command -v claude >/dev/null 2>&1; then
  _claude_review_prompt="${HOME}/.claude/prompts/review.txt"
  _claude_doc_prompt="${HOME}/.claude/prompts/doc.txt"
  _claude_commit_prompt="${HOME}/.claude/prompts/commit.txt"
  _claude_review_default="Review the code in the current directory. Point out bugs, style issues, and suggest improvements."
  _claude_doc_default="Create or improve documentation for the current project (README, API docs, or in-code comments as appropriate)."
  _claude_commit_default="Check staged changes (git status, git diff --staged), propose a clear commit message, then commit and push."

  clr () {
    local q="$*"
    [ -z "$q" ] && q="$_claude_review_default"
    claude --append-system-prompt "$(cat "$_claude_review_prompt" 2>/dev/null || true)" "$q"
  }
  cld () {
    local q="$*"
    [ -z "$q" ] && q="$_claude_doc_default"
    claude --append-system-prompt "$(cat "$_claude_doc_prompt" 2>/dev/null || true)" "$q"
  }
  clc () {
    local q="$*"
    [ -z "$q" ] && q="$_claude_commit_default"
    claude --append-system-prompt "$(cat "$_claude_commit_prompt" 2>/dev/null || true)" "$q"
  }
  alias cl='claude'
  alias claude-review='clr'
  alias claude-doc='cld'
  alias claude-commit='clc'

  # 自律実行モード（テスト→修正→再テストを自動で回す）
  cla () {
    local q="$*"
    [ -z "$q" ] && q="Implement the requested changes. Run tests, fix failures, and repeat until all tests pass."
    claude --dangerously-skip-permissions "$q"
  }
  alias claude-auto='cla'
fi

# ----------------------------------------------------------
# Others
# ----------------------------------------------------------
alias tenki='wttr'
alias h='history'
alias grep='grep --color=auto'
