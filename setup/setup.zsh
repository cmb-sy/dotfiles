#!/bin/zsh

DOTFILES_DIR="$HOME/.dotfiles"

#----------------------------------------------------------
# dotfilesのクローンまたは更新
#----------------------------------------------------------
if [[ ! -e $DOTFILES_DIR ]]; then
  git clone --recursive https://github.com/cmb-sy/dotfiles.git $DOTFILES_DIR
else
  (cd $DOTFILES_DIR && git pull)
fi

cd $DOTFILES_DIR

#----------------------------------------------------------
# dotfilesのシンボリックリンク作成
#----------------------------------------------------------
if [[ ! -d ${HOME}/.config ]]; then
  mkdir ${HOME}/.config
fi

cd config

for name in *; do
  if [[ ! $name =~ ^(setup|config|vscode|README\.md|git)$ ]]; then
    ln -sf $DOTFILES_DIR/$name $HOME/.$name
  fi
done

for config_file in config/*; do
  ln -sf $DOTFILES_DIR/$config_file $HOME/.config/$(basename $config_file)
done

cd ..

#----------------------------------------------------------
# VSCode設定
#----------------------------------------------------------
if [[ ! -d ${HOME}/Library/Application\ Support/Code/User ]]; then
  mkdir -p ${HOME}/Library/Application\ Support/Code/User
fi

ln -sf $DOTFILES_DIR/vscode/settings.json "$HOME/Library/Application Support/Code/User/settings.json"

#----------------------------------------------------------
# インストールスクリプトの実行
#----------------------------------------------------------
FORCE=1
. $DOTFILES_DIR/setup/install.zsh

util::info "インストールが完了しました！ターミナルを再起動してください。" 