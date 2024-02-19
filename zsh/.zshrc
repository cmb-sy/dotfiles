# ------------------------------
# Load zplug
# ------------------------------
source ~/dotfiles/zsh/.zplugs.zsh

# -------------------------------------------------------------------
# command Settings
# -------------------------------------------------------------------
# zsh-syntax-highlighting
# brew install zsh-syntax-highlighting
source /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# brew install zsh-autosuggestions
source /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# -------------------------------------------------------------------
# vscode settings
# -------------------------------------------------------------------
cp ~/dotfiles/vscode/settings.json_with_comments.rb ~/dotfiles/vscode/settings.json
sed -i '' 's/\/\/.*//' ~/dotfiles/vscode/settings.json # //を含む行を削除して上書き
rm -rf ~/Library/Application\ Support/Code/User/settings.json
ln -s ~/dotfiles/vscode/settings.json ~/Library/Application\ Support/Code/User/settings.json
