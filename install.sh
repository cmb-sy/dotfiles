#!/bin/sh
DOT_DIR="${HOME}/dotfiles"

# --------------------------------------------------------------------
# Adapting symbolic links
# --------------------------------------------------------------------
echo "Create dotfile links..."
Source "${DOT_DIR}/git/apply_gitconfig.zsh
Source "${DOT_DIR}/vscode/apply_vscode.zsh
Source "${DOT_DIR}/zsh/apply_zsh.zsh
Source "${DOT_DIR}/macos/apply_macos.zsh

# --------------------------------------------------------------------
# Install modules
# --------------------------------------------------------------------
echo "Install modules..."
source "${DOT_DIR}/brew_install.zsh"

# --------------------------------------------------------------------
# Adapting zsh
# --------------------------------------------------------------------
echo "Loading dotfiles..."
source "${DOT_DIR}/.zshrc"


echo "install.sh all done!"
