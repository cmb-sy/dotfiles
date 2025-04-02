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
# 必要なディレクトリを作成
#----------------------------------------------------------
mkdir -p "$HOME/.config" "$HOME/Library/Application Support/Code/User"

#----------------------------------------------------------
# dotfilesのシンボリックリンク作成
#----------------------------------------------------------
echo "各種設定ファイルのシンボリックリンクを作成中..."

# ドットファイルのリンク
for name in *; do
  if [[ ! $name =~ ^(setup|config|vscode|README\.md|git)$ ]]; then
    ln -sf $DOTFILES_DIR/$name $HOME/.$name
  fi
done

# Gitの設定ファイル
ln -sf $DOTFILES_DIR/git/.gitconfig $HOME/.gitconfig

# configディレクトリのファイル
for config_file in config/*; do
  ln -sf $DOTFILES_DIR/$config_file $HOME/.config/$(basename $config_file)
done

# VSCode設定
ln -sf $DOTFILES_DIR/vscode/settings.json "$HOME/Library/Application Support/Code/User/settings.json"

#----------------------------------------------------------
# インストールスクリプトの実行
#----------------------------------------------------------
FORCE=1
. $DOTFILES_DIR/setup/install.zsh

echo "インストールが完了しました！ターミナルを再起動してください。" 