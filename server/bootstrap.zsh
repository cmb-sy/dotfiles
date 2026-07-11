#!/bin/zsh
# Initial OCI server setup (run manually after the first tailscale ssh login).
# Idempotent: safe to re-run. Secrets are injected interactively, never written to files.
# Usage: zsh ~/dotfiles/server/bootstrap.zsh [--dry-run]
set -e
setopt pipe_fail

# The claude installer targets ~/.local/bin, which on fresh Ubuntu is absent from
# PATH (~/.profile adds it only if it exists, and zsh after chsh never reads
# ~/.profile). Ensure claude is callable right after install.
export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="${0:A:h}"
REPO_DIR="${SCRIPT_DIR:h}"
source "${REPO_DIR}/setup/util.zsh"

DRY_RUN=0
if [[ $# -gt 0 ]]; then
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    *) echo "Unknown argument: $1 (usage: bootstrap.zsh [--dry-run])" >&2; exit 1 ;;
  esac
fi

plan() { echo "PLAN: $1"; }
step() {  # step <label> <command...>
  local label="$1"; shift
  if [[ $DRY_RUN == 1 ]]; then plan "$label"; return 0; fi
  util::info "==> $label"
  "$@"
}

# --- 1. apt packages -------------------------------------------------
step "apt packages" zsh "${SCRIPT_DIR}/install.zsh"

# --- 2. zsh env (PATH) -----------------------------------------------
setup_zsh_env() {
  # Keep ~/.local/bin (claude) on PATH for future shells;
  # ~/.zshenv is read by every zsh, login or not.
  local line='export PATH="$HOME/.local/bin:$PATH"'
  touch "$HOME/.zshenv"
  grep -qxF "$line" "$HOME/.zshenv" || echo "$line" >> "$HOME/.zshenv"
}
step "zsh env (PATH)" setup_zsh_env

# --- 3. claude -------------------------------------------------------
install_claude() {
  if ! util::has claude; then
    curl -fsSL https://claude.ai/install.sh | bash
  fi
  # On Linux credentials live in ~/.claude/.credentials.json (no keychain).
  # `claude setup-token` only prints a token (for CLAUDE_CODE_OAUTH_TOKEN) and
  # saves nothing, so authenticate via the interactive /login flow.
  if [[ ! -f "$HOME/.claude/.credentials.json" ]]; then
    util::warning "claude を起動します。/login でログインを完了し、終了（/exit または Ctrl+C）してください"
    claude || true
    if [[ ! -f "$HOME/.claude/.credentials.json" ]]; then
      util::warning "ログインが完了していません（~/.claude/.credentials.json が無い）。bootstrap を再実行してください"
      exit 1
    fi
  fi
}
step "claude install + login" install_claude

# --- 4. gh -----------------------------------------------------------
install_gh() {
  if ! util::has gh; then
    sudo mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt-get update -qq && sudo apt-get install -y -qq gh
  fi
  gh auth status 2>/dev/null || gh auth login
}
step "gh auth login" install_gh

# --- 5. systemd user units -------------------------------------------
setup_units() {
  # Tailscale SSH registers no logind session, so XDG_RUNTIME_DIR is unset and
  # systemctl --user fails with "Failed to connect to bus". Guard against that.
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  sudo loginctl enable-linger "$USER"
  # After enabling linger, wait for the user manager's bus socket (up to 10s)
  for i in {1..10}; do [[ -S "$XDG_RUNTIME_DIR/bus" ]] && break; sleep 1; done
  mkdir -p "$HOME/.config/systemd/user"
  for unit in tmux.service keepalive.service keepalive.timer; do
    ln -sf "${SCRIPT_DIR}/${unit}" "$HOME/.config/systemd/user/${unit}"
  done
  systemctl --user daemon-reload
  systemctl --user enable --now tmux.service keepalive.timer
}
step "systemd user units (tmux, keepalive)" setup_units

# --- 6. claude global CLAUDE.md --------------------------------------
link_claude_md() {
  mkdir -p "$HOME/.claude"
  ln -sf "${REPO_DIR}/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
}
step "claude global CLAUDE.md link" link_claude_md

if [[ $DRY_RUN == 1 ]]; then exit 0; fi
util::info "Bootstrap complete. Attach: tmux attach -t main"
