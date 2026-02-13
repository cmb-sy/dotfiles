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
  brew bundle --file="${REPO_DIR}/Brewfile"
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
# LLM Skills (Claude Code リモートスキル)
#----------------------------------------------------------
util::confirm "Install LLM remote skills?"
if [[ $? = 0 ]]; then
  source "${REPO_DIR}/claude/install-llm-skills.zsh"
fi

#----------------------------------------------------------
# macOS settings
#----------------------------------------------------------
util::confirm "Apply macOS settings?"
if [[ $? = 0 ]]; then
  source "${REPO_DIR}/macos/install.zsh"
fi

util::info "Cleanup..."
brew cleanup
util::info "Done!"
