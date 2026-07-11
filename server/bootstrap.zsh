#!/bin/zsh
# OCI サーバー初回セットアップ（初回 tailscale ssh ログイン後に手動実行）。
# 冪等: 2回実行しても安全。secrets は一切ファイルに書かず対話で注入する。
# 使い方: zsh ~/dotfiles/server/bootstrap.zsh [--dry-run]
set -e
setopt pipe_fail

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

# --- 2. claude -------------------------------------------------------
install_claude() {
  if ! util::has claude; then
    curl -fsSL https://claude.ai/install.sh | bash
  fi
  # Linux では credential は ~/.claude/.credentials.json に保存される（keychain なし）
  if [[ ! -f "$HOME/.claude/.credentials.json" ]]; then
    util::warning "ブラウザの開けない環境のため long-lived token を使う:"
    claude setup-token
  fi
}
step "claude install + setup-token" install_claude

# --- 3. gh -----------------------------------------------------------
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

# --- 4. systemd user units -------------------------------------------
setup_units() {
  sudo loginctl enable-linger "$USER"
  mkdir -p "$HOME/.config/systemd/user"
  for unit in tmux.service keepalive.service keepalive.timer; do
    ln -sf "${SCRIPT_DIR}/${unit}" "$HOME/.config/systemd/user/${unit}"
  done
  systemctl --user daemon-reload
  systemctl --user enable --now tmux.service keepalive.timer
}
step "systemd user units (tmux, keepalive)" setup_units

# --- 5. claude global CLAUDE.md --------------------------------------
link_claude_md() {
  mkdir -p "$HOME/.claude"
  ln -sf "${REPO_DIR}/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
}
step "claude global CLAUDE.md link" link_claude_md

if [[ $DRY_RUN == 1 ]]; then exit 0; fi
util::info "Bootstrap complete. Attach: tmux attach -t main"
