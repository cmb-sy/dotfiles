#!/bin/zsh

# Get directory where script is located
SCRIPT_DIR="${HOME}/.dotfiles/setup"
source "${SCRIPT_DIR}/util.zsh"

util::info "Starting dotfiles installation..."

for script in $(\ls ${HOME}/.dotfiles/setup/install); do   
  util::confirm "install ${script}?"
  if [[ $? = 0 ]]; then
    . ${HOME}/.dotfiles/setup/install/${script}
  fi
done

util::info "Installation completed successfully!"
util::info "Please restart your terminal to apply changes."