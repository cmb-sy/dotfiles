# Dotfiles

個人的な開発環境を素早く構築するための設定ファイル集です。

## ディレクトリ構造

```
dotfiles/
├── .config/            # 各種アプリケーションの設定
│   ├── sheldon/        # Zshプラグイン管理
│   └── starship.toml   # ターミナルプロンプト設定
├── git/                # Git関連の設定
├── macos/              # macOS固有の設定
├── setup/              # セットアップスクリプト
│   ├── brew_install.sh # Homebrewパッケージインストール
│   ├── install.sh      # 全体のインストールスクリプト
│   └── setup.sh        # 環境セットアップスクリプト
├── vscode/             # Visual Studio Code設定
└── zsh/                # Zsh設定ファイル
    ├── .aliases.sh     # コマンドエイリアス
    ├── .zshenv         # Zsh環境変数
    ├── .zshrc          # Zsh実行時設定
    ├── .function.zsh   # 便利な関数定義
    └── applyZsh.zsh    # Zsh設定適用スクリプト
```

## 主な設定ファイルの説明

### Zsh 設定

#### `.zshenv`

- Zsh が起動する度に常に読み込まれる環境変数設定
- 言語・ロケール設定、エディタ設定、PATH 設定など
- どの Zsh モードでも必要な設定を記述

#### `.zshrc`

- ターミナルでインタラクティブシェルとして Zsh を使用する際に読み込まれる設定
- キーバインド、プロンプト、補完、エイリアスなど
- ターミナルでの操作を快適にするための設定

#### `.aliases.sh`

- 頻繁に使用するコマンドのエイリアス（短縮名）を定義
- `ls`、`cd`、`git`、`docker`などの短縮形

#### `.function.zsh`

- 便利な Zsh 関数を定義したファイル
- gitignore の生成、NPM スクリプト選択、天気情報取得など

### プラグイン管理

#### `.config/sheldon/plugins.toml`

- Sheldon を使用した Zsh プラグイン管理設定
- シンタックスハイライト、コマンド提案、補完機能などのプラグイン

#### `.config/starship.toml`

- Starship プロンプトの設定
- カラフルでわかりやすいコマンドプロンプトをカスタマイズ

## セットアップ方法

### 1. リポジトリをクローン

```bash
git clone https://github.com/yourusername/dotfiles.git ~/dotfiles
```

### 2. セットアップスクリプトを実行

```bash
cd ~/dotfiles
chmod +x setup/install.sh
./setup/install.sh
```

### 3. Zsh 設定を適用

```bash
cd ~/dotfiles
chmod +x zsh/applyZsh.zsh
./zsh/applyZsh.zsh
```

## 注意点

- `.config`ディレクトリをシンボリックリンクで置き換えるため、既存の設定がある場合はバックアップをとってから適用することをおすすめします
- 設定ファイルは自分の環境に合わせて適宜カスタマイズしてください

## 主な機能

- 見やすく効率的なターミナル環境
- Git の便利な設定とエイリアス
- Docker の操作を簡略化するエイリアス
- Homebrew による必要なアプリケーションの一括インストール
- macOS の便利な設定
