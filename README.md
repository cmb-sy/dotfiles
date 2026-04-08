# Dotfiles

macOS 開発環境の設定ファイルを管理するリポジトリ。

## 構成

```
.aliases.sh          # シェルエイリアス (docker, terraform, claude 等)
.function.zsh        # カスタムシェル関数
.zshrc / .zshenv     # Zsh 設定
.gitignore_global    # グローバル gitignore
Brewfile             # Homebrew パッケージ・Cask 定義
git/                 # .gitconfig
terminal/            # Ghostty, WezTerm 設定
macos/               # macOS システム設定スクリプト
claude/              # Claude Code 設定 (skills, agents, hooks, tools)
bin/                 # カスタムスクリプト
setup/               # セットアップスクリプト
```

## セットアップ

```bash
git clone https://github.com/cmb-sy/dotfiles.git
cd dotfiles
```

シンボリックリンク作成・基本設定:

```bash
zsh setup/setup.zsh
```

Homebrew パッケージ・VSCode/Cursor 拡張・macOS 設定の適用:

```bash
zsh setup/install.zsh
```

ターミナルを再起動して反映。

## CI

```bash
CI=true zsh setup/install.zsh
```
