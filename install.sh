#!/bin/sh

#実行前に 以下のコマンドで権限付与してください。
# chmod +x install.sh


# スクリプトがあるディレクトリの絶対パスを取得
dotfiles_root=$(cd "$(dirname "$0")" && pwd)

# dotfilesディレクトリの中身のリンクをホームディレクトリ直下に作成
cd "$dotfiles_root"/dotfiles || exit

for file in .*; do
    # ディレクトリや特殊なファイルを無視
    [ "$file" = "." ] && continue
    [ "$file" = ".." ] && continue
    [ "$file" = ".git" ] && continue

    # 既存のファイルやディレクトリがあればバックアップしてからシンボリックリンク作成
    if [ -e "$HOME/$file" ]; then
        mv "$HOME/$file" "$HOME/${file}.backup"
    fi

    ln -s "$dotfiles_root/dotfiles/$file" "$HOME"
done
