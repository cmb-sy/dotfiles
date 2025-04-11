#!/bin/zsh

source ${HOME}/dotfiles/setup/util.zsh

DOTFILES_DIR=${HOME}/dotfiles

#----------------------------------------------------------
# Clone or update dotfiles
#----------------------------------------------------------
if [[ ! -e $DOTFILES_DIR ]]; then
  git clone --recursive https://github.com/cmb-sy/dotfiles.git $DOTFILES_DIR
else
  (cd $DOTFILES_DIR && git pull)
fi

cd $DOTFILES_DIR

#----------------------------------------------------------
# Create symbolic links for dotfiles
#----------------------------------------------------------
for name in *; do
  if [[ ${name} != 'setup' ]] && [[ ${name} != 'config' ]] && [[ ${name} != 'vscode' ]] && [[ ${name} != 'README.md' ]]; then
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
# FORCE=1
# . ${DOTFILES_DIR}/setup/install.zsh

#----------------------------------------------------------
# Other
#----------------------------------------------------------
cp ${HOME}/dotfiles/.config/alacritty/alacritty.toml ${HOME}/.config/alacritty/alacritty.toml   


#----------------------------------------------------------
# last message
#----------------------------------------------------------
util::info "Installation completed! Please restart terminal." 