# zsh script meant to be sourced from .zshrc (not executed directly).
# Uses zsh-only syntax (arrays, read -rs, read "var?prompt"); not POSIX sh.

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
#   1. Create per-account config dirs (e.g. ~/.claude-private, ~/.claude-work),
#      or mv ~/.claude ~/.claude-private when migrating an existing tree.
#   2. Mint a per-account long-lived token (required — see "Why" below):
#        claude-setup-token-private  then  claude-save-token-private
#        claude-setup-token-work     then  claude-save-token-work
#      Run setup and save as SEPARATE commands: setup-token's interactive TUI
#      leaves stdin in a state where a chained read gets immediate EOF. The
#      save step stores the token (chmod 600) plus an account label (the email
#      used at setup-token) in oauth-token.account; statusline.sh shows it as
#      the token-consuming account. The label is the ONLY identity record:
#      setup-token tokens carry just the user:inference scope, so the owner
#      cannot be resolved from the token via API, and token-injected sessions
#      never refresh .claude.json's oauthAccount cache. Rotate only via
#      setup + save (hand-editing oauth-token leaves a stale label; "(?)" in
#      the statusline means no label — re-run claude-save-token-*).
#   3. Link shared dotfiles config into both dirs (once): `claude-link-shared`.
#   4. Make ~/.claude a symlink (not a plain directory), e.g.:
#        ln -sfn ~/.claude-private ~/.claude
# Why per-account tokens: on macOS the OAuth session lives in ONE global
# Keychain item, NOT scoped by CLAUDE_CONFIG_DIR — switching config dirs only
# changes settings/skills/history, while the last `/login` account silently
# serves API calls for BOTH clp and clw. A per-account CLAUDE_CODE_OAUTH_TOKEN
# (valid 1 year) bypasses Keychain and is injected per command only.
# Daily: clp / clw switch account + launch; clpa / clwa add autonomous mode.
# New terminals do not inherit CLAUDE_CONFIG_DIR; the ~/.claude symlink is the
# persistent default. Per-account effort/model defaults: export overrides for
# CLAUDE_PRIVATE_DEFAULT_* / CLAUDE_WORK_DEFAULT_* before sourcing this file.
# ----------------------------------------------------------
: "${CLAUDE_ACCOUNT_PRIVATE_DIR:=${HOME}/.claude-private}"
: "${CLAUDE_ACCOUNT_WORK_DIR:=${HOME}/.claude-work}"

: "${CLAUDE_PRIVATE_DEFAULT_EFFORT:=medium}"
: "${CLAUDE_PRIVATE_DEFAULT_MODEL:=}"
: "${CLAUDE_WORK_DEFAULT_EFFORT:=xhigh}"
: "${CLAUDE_WORK_DEFAULT_MODEL:=}"

_claude_account_link() {
  local target="$1"
  ln -sfn "$target" "${HOME}/.claude"
  # Normalize plugin installPath symlink contamination on every switch;
  # otherwise the other account's live sessions emit "Plugin directory does
  # not exist" on every Stop (details in that script's header comments).
  zsh "${DOTFILES:-${HOME}/dotfiles}/claude/normalize-plugin-paths.zsh" 2>/dev/null
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

# Build --effort/--model flags for an account's defaults into the global
# _claude_default_flags array. Empty effort/model means "let Claude Code use
# its own built-in default" — no flag is passed for that one.
_claude_default_flags=()
_claude_build_default_flags() {
  local effort="$1" model="$2"
  _claude_default_flags=()
  [ -n "$effort" ] && _claude_default_flags+=(--effort "$effort")
  [ -n "$model" ] && _claude_default_flags+=(--model "$model")
}

# Run `claude` scoped to one account's long-lived token, if one has been set
# up (see claude-setup-token-private/-work). CLAUDE_CODE_OAUTH_TOKEN is set as
# a command-prefix assignment, not exported, so it never leaks into the
# interactive shell's persistent environment. Falls back to whatever
# credential Keychain/`/login` currently holds if no token file exists yet.
_claude_run_for_account() {
  local account_dir="$1"
  shift
  local token_file="${account_dir}/oauth-token"
  if [ -r "$token_file" ]; then
    CLAUDE_CODE_OAUTH_TOKEN="$(cat "$token_file")" command claude "$@"
  else
    command claude "$@"
  fi
}

# `claude setup-token` is an interactive Ink TUI; it must be its own top-level
# command. Do not chain a stdin-reading step after it in the same function —
# the TUI's raw-mode teardown races with the next read and yields an
# immediate EOF (empty token file) rather than waiting for paste input.
# Save the token afterwards with claude-save-token-private/-work instead.
claude-setup-token-private() {
  _claude_require_cli || return $?
  claude-use-private
  claude setup-token
  echo "Copy the token above, then in a NEW command run: claude-save-token-private"
}

claude-setup-token-work() {
  _claude_require_cli || return $?
  claude-use-work
  claude setup-token
  echo "Copy the token above, then in a NEW command run: claude-save-token-work"
}

# Alongside the token, save a human-readable label of the account it belongs
# to into <dir>/oauth-token.account. setup-token's long-lived tokens carry
# only the user:inference scope (no user:profile), so neither we nor Claude
# Code itself can resolve the owning account from the token via API — the
# label recorded here at save time is the only reliable identity record.
# statusline.sh displays it as the token-consuming account.
_claude_save_token_for() {
  local dir="$1" which="$2" token label
  read -rs "token?Paste the ${which}-account token, then press Enter: "
  echo
  [ -z "$token" ] && { echo "No token entered; aborting." >&2; return 1; }
  read -r "label?Account label for this token (e.g. you@gmail.com): "
  printf '%s' "$token" > "${dir}/oauth-token"
  chmod 600 "${dir}/oauth-token"
  if [ -n "$label" ]; then
    printf '%s' "$label" > "${dir}/oauth-token.account"
    chmod 600 "${dir}/oauth-token.account"
  fi
  echo "Saved to ${dir}/oauth-token${label:+ (account: ${label})}"
}

claude-save-token-private() {
  _claude_save_token_for "${CLAUDE_ACCOUNT_PRIVATE_DIR}" private
}

claude-save-token-work() {
  _claude_save_token_for "${CLAUDE_ACCOUNT_WORK_DIR}" work
}

claude-private() {
  _claude_require_cli || return $?
  _claude_sync_shared
  claude-use-private
  _claude_build_default_flags "$CLAUDE_PRIVATE_DEFAULT_EFFORT" "$CLAUDE_PRIVATE_DEFAULT_MODEL"
  _claude_run_for_account "${CLAUDE_ACCOUNT_PRIVATE_DIR}" "${_claude_default_flags[@]}" "$@"
}

claude-work() {
  _claude_require_cli || return $?
  _claude_sync_shared
  claude-use-work
  _claude_build_default_flags "$CLAUDE_WORK_DEFAULT_EFFORT" "$CLAUDE_WORK_DEFAULT_MODEL"
  _claude_run_for_account "${CLAUDE_ACCOUNT_WORK_DIR}" "${_claude_default_flags[@]}" "$@"
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
  _claude_build_default_flags "$CLAUDE_PRIVATE_DEFAULT_EFFORT" "$CLAUDE_PRIVATE_DEFAULT_MODEL"
  _claude_run_for_account "${CLAUDE_ACCOUNT_PRIVATE_DIR}" "${_claude_default_flags[@]}" --dangerously-skip-permissions "$q"
}

clwa() {
  _claude_require_cli || return $?
  _claude_sync_shared
  claude-use-work
  local q="$*"
  [ -z "$q" ] && q="$_claude_autonomous_default_prompt"
  _claude_build_default_flags "$CLAUDE_WORK_DEFAULT_EFFORT" "$CLAUDE_WORK_DEFAULT_MODEL"
  _claude_run_for_account "${CLAUDE_ACCOUNT_WORK_DIR}" "${_claude_default_flags[@]}" --dangerously-skip-permissions "$q"
}

alias claude-auto='clwa'

claude-link-shared() {
  local d="${DOTFILES:-${HOME}/dotfiles}"
  zsh "$d/claude/link-shared-config.zsh"
}

# ----------------------------------------------------------
# Terraform (installed via tfenv — see Brewfile)
# ----------------------------------------------------------
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'
alias tfv='terraform validate'
alias tff='terraform fmt'
alias tfs='terraform show'
alias tfo='terraform output'
alias tfw='terraform workspace'

# ----------------------------------------------------------
# Voice input engine switch (Handy / Typeless via voice-switch)
# ----------------------------------------------------------
alias vsja='voice-switch ja'
alias vsen='voice-switch en'
alias vscl='voice-switch cloud'
alias vsty='voice-switch typeless'
alias vslo='voice-switch local'   # same as vsja (local mode is ja-locked)

# ----------------------------------------------------------
# Others
# ----------------------------------------------------------
alias tenki='wttr'
alias h='history'
alias grep='grep --color=auto'
