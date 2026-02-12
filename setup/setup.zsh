#!/bin/zsh

# Load the path relative to the directory where the script is being executed
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/util.zsh"

# Get the path using util::repo_dir()
export SCRIPT_DIR
DOTFILES_DIR="$(util::repo_dir)"

#----------------------------------------------------------
# Clone or update dotfiles
#----------------------------------------------------------
if [[ -z "${CI}" || "${CI}" != "true" ]]; then
  if [[ ! -e ${DOTFILES_DIR} ]]; then
    git clone --recursive https://github.com/cmb-sy/dotfiles.git ${DOTFILES_DIR}
  else
    (cd ${DOTFILES_DIR} && git pull)
  fi
fi

cd ${DOTFILES_DIR}

#----------------------------------------------------------
# Create symbolic links for dotfiles
#----------------------------------------------------------
for name in *; do
  if [[ ${name} != 'setup' ]] && [[ ${name} != 'config' ]] && [[ ${name} != 'vscode' ]] && [[ ${name} != 'README.md' ]] && [[ ${name} != 'wezterm' ]]; then
    if [[ -L ${HOME}/.${name} ]]; then
      unlink ${HOME}/.${name}
    fi
    ln -sfv ${PWD}/${name} ${HOME}/.${name}
  fi
done

if [[ ! -d ${HOME}/.config ]]; then
  mkdir ${HOME}/.config
fi

cd .config

for name in *; do
  if [[ ! $name =~ ^(setup|.config|vscode|README\.md|git)$ ]]; then
    ln -sf ${PWD}/$name ${HOME}/.$name
  fi
done

cd ..

#----------------------------------------------------------
# VSCode Settings
#----------------------------------------------------------
if [[ ! -d ${HOME}/Library/Application\ Support/Code/User ]]; then
  mkdir -p ${HOME}/Library/Application\ Support/Code/User
fi
ln -sfv ${PWD}/.vscode/settings.json ${HOME}/Library/Application\ Support/Code/User/settings.json


#----------------------------------------------------------
# Run installation scripts
#----------------------------------------------------------
FORCE=1
. ${DOTFILES_DIR}/setup/install.zsh

#----------------------------------------------------------
# Wezterm
#----------------------------------------------------------
if [[ -d ${DOTFILES_DIR}/wezterm ]] && [[ -f ${DOTFILES_DIR}/wezterm/wezterm.lua ]]; then
  mkdir -p ${HOME}/.config
  if [[ -L ${HOME}/.config/wezterm ]]; then
    unlink ${HOME}/.config/wezterm
  elif [[ -d ${HOME}/.config/wezterm ]]; then
    rm -rf ${HOME}/.config/wezterm
  fi
  ln -sfn ${DOTFILES_DIR}/wezterm ${HOME}/.config/wezterm
  echo "Created: ${HOME}/.config/wezterm -> ${DOTFILES_DIR}/wezterm"
fi

#----------------------------------------------------------
util::info "Installation completed! Please restart terminal." 