# .zshrc から source される前提の zsh スクリプト（実行ファイルではない）。
# zsh 固有構文（配列、read -rs、read "var?prompt"）を含むため POSIX sh では動かない。

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
#   2. Mint a per-account long-lived token (required — see "Why" below). Run
#      these as two SEPARATE commands (not chained) — `claude setup-token` is
#      an interactive TUI that leaves the terminal's stdin in a state where a
#      capture command chained right after it will read EOF immediately:
#        claude-setup-token-private   # opens browser login, prints a token
#        claude-save-token-private    # then, in a fresh prompt, paste it here
#        claude-setup-token-work      # same, for the work account
#        claude-save-token-work
#      The token is saved to CLAUDE_ACCOUNT_*_DIR/oauth-token (chmod 600, not
#      echoed back to the terminal) and read automatically by clp/clw/clpa/clwa
#      from then on. The save step also asks for an ACCOUNT LABEL (the email
#      of the account you logged in as during setup-token) and stores it in
#      CLAUDE_ACCOUNT_*_DIR/oauth-token.account — statusline.sh shows this as
#      the token-consuming account, e.g. "private (alice)". The label
#      is the ONLY identity record: setup-token tokens carry just the
#      user:inference OAuth scope, so the owning account can never be resolved
#      from the token itself (API returns 403), and <dir>/.claude.json's
#      oauthAccount cache is never refreshed by token-injected sessions.
#      OPERATIONAL RULES:
#        - Rotate tokens ONLY via claude-setup-token-* + claude-save-token-*.
#          Never hand-edit oauth-token alone — the label would silently go
#          stale and the statusline would show the wrong account.
#        - When statusline shows "(?)", the token has no label: re-run
#          claude-save-token-* (or write the email to oauth-token.account).
#        - Log in with the CORRECT account in the browser during setup-token;
#          nothing downstream can detect a private/work mix-up at that step.
#   3. Share dotfiles-backed config into both dirs (once), if not already done
#      (e.g. setup.zsh may run this): `claude-link-shared`, or:
#        zsh "${DOTFILES:-${HOME}/dotfiles}/claude/link-shared-config.zsh"
#   4. Make ~/.claude a symlink (not a plain directory), or clp/clw may not behave
#      as intended. Example default target (pick one):
#        ln -sfn ~/.claude-private ~/.claude
# Why per-account tokens (not just `/login` per config dir): on macOS, Claude
# Code's OAuth session is stored in ONE global Keychain item
# ("Claude Code-credentials"), not scoped by CLAUDE_CONFIG_DIR. Switching
# CLAUDE_CONFIG_DIR only changes where settings/skills/history are read from —
# it does NOT change which account's token is used for API calls. Whichever
# account you last ran `/login` as silently becomes active for BOTH clp and
# clw. A per-account CLAUDE_CODE_OAUTH_TOKEN (from `claude setup-token`, valid
# 1 year) bypasses Keychain entirely and is injected only for the duration of
# that one command, so private/work usage can never cross-contaminate.
# Daily: `clp` / `clw` switch account + launch; `clpa` / `clwa` same + autonomous mode.
# New terminals do not inherit CLAUDE_CONFIG_DIR; ~/.claude symlink persists.
# Per-account defaults (effort/model) live in CLAUDE_PRIVATE_DEFAULT_* /
# CLAUDE_WORK_DEFAULT_* below — export an override before sourcing this file
# to change them (e.g. in ~/.zshrc.local).
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
  # プラグイン installPath の symlink パス混入を毎回正規化する。これを怠ると、
  # symlink 切替時にもう一方のアカウントの稼働中セッションが
  # "Plugin directory does not exist" を毎 Stop で吐く（詳細はスクリプト内コメント）。
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
# Terraform (tfenv 経由でインストール — Brewfile 参照)
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
