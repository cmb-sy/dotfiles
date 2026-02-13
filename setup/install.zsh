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
# LLM Agent Skills
#----------------------------------------------------------
util::confirm "Install LLM remote skills?"
if [[ $? = 0 ]]; then
  for dir in "${HOME}/.claude" "${HOME}/.cursor"; do
    mkdir -p "${dir}"
    [[ -L "${dir}/skills" ]] && unlink "${dir}/skills"
    [[ ! -d "${dir}/skills" ]] && mkdir -p "${dir}/skills"
  done
  source "${REPO_DIR}/claude/install-llm-skills.zsh"
  rm -rf "${HOME}/.cursor/skills"
  ln -sfn "${HOME}/.claude/skills" "${HOME}/.cursor/skills"
fi

#----------------------------------------------------------
# macOS settings (skip password prompt when FORCE=1)
#----------------------------------------------------------
if [[ ${FORCE} != 1 ]] && util::confirm "Apply macOS settings?"; then
  source "${REPO_DIR}/macos/install.zsh"
fi

util::info "Cleanup..."
brew cleanup 2>/dev/null || true
util::info "Done!"
