#!/bin/zsh

SCRIPT_DIR="${0:A:h}"
REPO_DIR="${SCRIPT_DIR:h}"
source "${SCRIPT_DIR}/util.zsh"

util::info "Starting dotfiles installation..."

#----------------------------------------------------------
# Homebrew (Brewfile)
#----------------------------------------------------------
util::confirm "Install packages from Brewfile?"
if [[ $? = 0 ]]; then
  export HOMEBREW_NO_AUTO_UPDATE=1
  export HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1
  brew bundle --file="${REPO_DIR}/Brewfile" --quiet
fi

#----------------------------------------------------------
# VSCode Extensions
#----------------------------------------------------------
util::confirm "Install VSCode extensions?"
if [[ $? = 0 ]]; then
  source "${REPO_DIR}/.vscode/install.zsh"
fi

#----------------------------------------------------------
# Cursor Extensions
#----------------------------------------------------------
util::confirm "Install Cursor extensions?"
if [[ $? = 0 ]]; then
  source "${REPO_DIR}/.cursor/install.zsh"
fi

#----------------------------------------------------------
# macOS settings (skip password prompt when FORCE=1)
#----------------------------------------------------------
if [[ ${FORCE} != 1 ]] && util::confirm "Apply macOS settings?"; then
  source "${REPO_DIR}/macos/install.zsh"
fi

#----------------------------------------------------------
# tmux
#----------------------------------------------------------
util::confirm "Set up tmux config?"
if [[ $? = 0 ]]; then
  mkdir -p "$HOME/.config/tmux"
  ln -sf "${REPO_DIR}/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf"
  mkdir -p "$HOME/.local/bin"
  ln -sf "${REPO_DIR}/tmux/sessionizer.sh" "$HOME/.local/bin/tmux-sessionizer"
  chmod +x "${REPO_DIR}/tmux/sessionizer.sh"
  util::info "tmux config and sessionizer linked."
fi

#----------------------------------------------------------
# Cursor (skills shared with Claude)
#----------------------------------------------------------
util::confirm "Set up Cursor config?"
if [[ $? = 0 ]]; then
  mkdir -p "$HOME/.cursor"
  if [[ -d "${REPO_DIR}/claude/skills" ]]; then
    ln -sfn "${REPO_DIR}/claude/skills" "$HOME/.cursor/skills"
    util::info "Cursor skills linked (shared with Claude)."
  fi
fi

util::info "Cleanup..."
brew cleanup 2>/dev/null || true
util::info "Done!"
