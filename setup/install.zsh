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
  util::info "Installing VSCode extensions..."
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    code --install-extension "${line%% *}" 2>/dev/null || true
  done < "${REPO_DIR}/.vscode/extensions.zsh"
fi

#----------------------------------------------------------
# macOS settings
#----------------------------------------------------------
util::confirm "Apply macOS settings?"
if [[ $? = 0 ]]; then
  util::info "Applying macOS settings..."
  source "${REPO_DIR}/macos/install.zsh"
fi

#----------------------------------------------------------
# Finalize
#----------------------------------------------------------
util::info "Cleanup..."
brew cleanup
util::info "Done!"
