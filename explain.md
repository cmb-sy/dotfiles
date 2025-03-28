# dotfiles プロジェクトの詳細説明

このドキュメントでは、dotfiles プロジェクトの各ファイルの詳細な説明を提供します。

## 目次

- [dotfiles プロジェクトの詳細説明](#dotfiles-プロジェクトの詳細説明)
  - [目次](#目次)
  - [ユーティリティ関数 (util.zsh)](#ユーティリティ関数-utilzsh)
    - [メッセージ出力関数](#メッセージ出力関数)
    - [確認関数](#確認関数)
    - [環境チェック関数](#環境チェック関数)
    - [ファイル操作関数](#ファイル操作関数)
    - [パス取得関数](#パス取得関数)
  - [メインインストールスクリプト (install.sh)](#メインインストールスクリプト-installsh)
  - [各種セットアップスクリプト](#各種セットアップスクリプト)
    - [Homebrew (01_brew.zsh)](#homebrew-01_brewzsh)
    - [Zsh (02_zsh.zsh)](#zsh-02_zshzsh)
    - [VSCode (03_vscode.zsh)](#vscode-03_vscodezsh)
    - [Cursor (04_cursor.zsh)](#cursor-04_cursorzsh)
    - [Git (05_git.zsh)](#git-05_gitzsh)
    - [macOS (06_macos.zsh)](#macos-06_macoszsh)
  - [CI/CD 設定 (test.yml)](#cicd-設定-testyml)
  - [まとめ](#まとめ)

## ユーティリティ関数 (util.zsh)

`setup/util.zsh`はセットアップスクリプト全体で使用される共通のユーティリティ関数を提供します。

### メッセージ出力関数

```zsh
# 赤色でエラーメッセージを表示
util::error() {
  local message="$1"
  echo -e "\e[31m${message}\e[m"
}

# 黄色で警告メッセージを表示
util::warning() {
  local message="$1"
  echo -e "\e[33m${message}\e[m"
}

# 緑色で情報メッセージを表示
util::info() {
  local message="$1"
  echo -e "\e[32m${message}\e[m"
}
```

これらの関数は、カラーコードを使って色付きのメッセージを表示します。視認性を高め、メッセージの種類（エラー、警告、情報）を直感的に理解できるようにしています。

### 確認関数

```zsh
# ユーザーに確認を求める
util::confirm() {
  local message="$1"

  # FORCE=1またはCI環境の場合は自動的に承認
  if [[ ${FORCE} = 1 ]] || util::is_ci; then
    return 0
  fi

  echo "${message} (y/N)"
  read confirmation
  if [[ ${confirmation} = "y" || ${confirmation} = "Y" ]]; then
    return 0
  fi

  return 1
}
```

この関数は、インストールプロセスの各ステップでユーザーに確認を求めます。`FORCE=1`が設定されている場合や、CI サーバー上で実行されている場合は自動的に承認されます。

### 環境チェック関数

```zsh
# CI環境での実行かチェック
util::is_ci() {
  if [[ -n "${CI}" && "${CI}" == "true" ]]; then
    return 0
  fi
  return 1
}

# コマンドが存在するかチェック
util::has() {
  type "$1" > /dev/null 2>&1
  return $?
}

# macOSかどうかチェック
util::is_mac() {
  [[ "$(uname)" == "Darwin" ]]
  return $?
}
```

これらの関数は、実行環境を確認するために使用されます。CI 環境での実行かどうか、特定のコマンドが利用可能かどうか、macOS 上で実行されているかどうかなどをチェックします。

### ファイル操作関数

```zsh
# ファイル存在チェック
util::file_exists() {
  [[ -f "$1" ]]
  return $?
}

# ディレクトリ存在チェック
util::dir_exists() {
  [[ -d "$1" ]]
  return $?
}

# シンボリックリンク存在チェック
util::link_exists() {
  [[ -L "$1" ]]
  return $?
}

# ディレクトリ作成
util::mkdir() {
  if [[ ! -d "$1" ]]; then
    mkdir -p "$1"
  fi
}

# シンボリックリンク作成
util::symlink() {
  local src="$1"
  local dst="$2"

  # 既存のシンボリックリンクを削除
  if [[ -L "$dst" ]]; then
    unlink "$dst"
  fi

  # 新しいシンボリックリンクを作成
  ln -sfv "$src" "$dst"
}
```

これらの関数は、ファイルやディレクトリの存在確認、ディレクトリの作成、シンボリックリンクの作成を行います。特に`util::symlink`は、既存のシンボリックリンクを安全に置き換えるために使用されます。

### パス取得関数

```zsh
# dotfilesディレクトリの絶対パスを取得
util::dotfiles_dir() {
  echo "${HOME}/.dotfiles"
}

# リポジトリのルートディレクトリパスを取得
util::repo_dir() {
  # クローンされたリポジトリから実行している場合
  if [[ -d "${PWD}/.git" ]]; then
    echo "${PWD}"
  else
    # インストール済み位置から実行している場合
    echo "$(util::dotfiles_dir)"
  fi
}
```

これらの関数は、dotfiles ディレクトリの絶対パスを取得するために使用されます。スクリプトがクローンされたリポジトリから実行されているか、インストール済みの位置から実行されているかに関わらず、正しいパスを返します。

## メインインストールスクリプト (install.sh)

`setup/install.sh`は dotfiles のインストールプロセス全体を管理するメインスクリプトです。

```zsh
#!/bin/bash
# Main installation script for dotfiles

# Exit on error
set -e

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/util.zsh"

util::info "Starting dotfiles installation..."

# Check if running on macOS
if ! util::is_mac; then
    util::error "This script is only for macOS"
    exit 1
fi
```

まず、スクリプトはエラーが発生した場合に実行を停止するように設定され（`set -e`）、必要なユーティリティ関数を読み込みます。そして、macOS 上で実行されているかどうかを確認します。

```zsh
# Create necessary directories
util::info "Creating necessary directories..."
util::mkdir "${HOME}/.config"
util::mkdir "${HOME}/.config/cursor/rules"
util::mkdir "${HOME}/Library/Application Support/Code/User"
util::mkdir "${HOME}/Library/LaunchAgents"

# Define dotfiles directory
DOTFILES_DIR="$(util::repo_dir)"
```

次に、必要なディレクトリを作成し、dotfiles ディレクトリの絶対パスを取得します。

```zsh
# Run all installation scripts or ask for confirmation
if [[ ${FORCE} = 1 ]] || util::is_ci; then
    util::info "Running all installation scripts in force mode..."
    for script in "${SCRIPT_DIR}/install"/*.zsh; do
        script_name="$(basename "${script}")"
        util::info "Running ${script_name}..."
        zsh "${script}"
    done
else
    # Ask for each installation script
    for script in "${SCRIPT_DIR}/install"/*.zsh; do
        script_name="$(basename "${script}")"
        util::confirm "Run ${script_name}?"
        if [[ $? = 0 ]]; then
            util::info "Running ${script_name}..."
            zsh "${script}"
        else
            util::warning "Skipping ${script_name}..."
        fi
    done
fi
```

このセクションでは、`setup/install`ディレクトリ内の全ての`.zsh`スクリプトを実行します。`FORCE=1`が設定されている場合や CI 環境で実行されている場合は、全てのスクリプトを自動的に実行します。それ以外の場合は、各スクリプトを実行する前にユーザーに確認を求めます。

```zsh
util::info "Installation completed successfully!"
util::info "Please restart your terminal to apply all changes."
```

最後に、インストールが正常に完了したことを通知し、ターミナルを再起動するよう促します。

## 各種セットアップスクリプト

### Homebrew (01_brew.zsh)

`setup/install/01_brew.zsh`は、Homebrew のインストールと必要なパッケージのインストールを行います。

```zsh
#!/bin/zsh
# Homebrew installation and package setup

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

util::info "Setting up Homebrew..."

# Disable auto-update during installation
export HOMEBREW_NO_AUTO_UPDATE=1
```

まず、ユーティリティ関数を読み込み、インストール中の Homebrew の自動更新を無効にします。

```zsh
# Command line tools to install
formulas=(
    # Shell utilities
    fzf
    ripgrep
    fd
    bat
    exa
    jq
    yq
    tldr

    # Version control
    git
    gh
    hub
    git-delta

    # Shell enhancements
    zsh
    starship
    sheldon
    tmux
    zoxide

    # Development tools
    neovim
    nodebrew
    yarn
)

# GUI applications to install
casks=(
    # Browsers
    google-chrome

    # Development tools
    visual-studio-code
    cursor
    iterm2
    docker
    postman

    # Communication
    slack
    zoom

    # Productivity
    notion
    rectangle
    alfred
)
```

このセクションでは、インストールするコマンドラインツールと GUI アプリケーションを定義しています。カテゴリごとに整理されており、コメントで説明が付けられています。

```zsh
# Install Homebrew if not installed
if ! util::has brew; then
    util::info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH
    if util::is_mac; then
        if [[ -x "/opt/homebrew/bin/brew" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ${HOME}/.zshrc
        else
            eval "$(/usr/local/bin/brew shellenv)"
            echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ${HOME}/.zshrc
        fi
    fi
else
    util::info "Homebrew already installed"
fi
```

このセクションでは、Homebrew がインストールされていない場合にインストールを行います。インストール後、Homebrew をパスに追加し、`.zshrc`ファイルに設定を追加して、ターミナルを再起動した後も有効になるようにします。

```zsh
# Update Homebrew
util::info "Updating Homebrew..."
brew update

# Install formulas
util::info "Installing command line tools..."
for formula in ${formulas[@]}; do
    if brew list --formula | grep -q "^${formula}\$"; then
        util::info "Already installed: ${formula}"
    else
        util::info "Installing: ${formula}"
        brew install "${formula}"
    fi
done

# Install casks
util::info "Installing GUI applications..."
for cask in ${casks[@]}; do
    if brew list --cask | grep -q "^${cask}\$"; then
        util::info "Already installed: ${cask}"
    else
        util::info "Installing: ${cask}"
        brew install --cask "${cask}"
    fi
done
```

このセクションでは、Homebrew をアップデートし、前のセクションで定義されたコマンドラインツールと GUI アプリケーションをインストールします。既にインストールされているパッケージはスキップされます。

```zsh
# Cleanup
util::info "Cleaning up Homebrew..."
brew cleanup

util::info "Homebrew setup completed!"
```

最後に、不要なファイルを削除し、Homebrew のセットアップが完了したことを通知します。

### Zsh (02_zsh.zsh)

`setup/install/02_zsh.zsh`は、Zsh の設定を行います。

```zsh
#!/bin/zsh
# Zsh configuration setup

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

util::info "Setting up Zsh..."

# Check if ZSH_DIR exists
DOTFILES_DIR="$(util::repo_dir)"
ZSH_DIR="${DOTFILES_DIR}/zsh"

if ! util::dir_exists "${ZSH_DIR}"; then
    util::error "Zsh directory not found: ${ZSH_DIR}"
    exit 1
fi
```

最初に、ユーティリティ関数を読み込み、Zsh 設定ディレクトリが存在するかを確認します。

```zsh
# Install Zsh if not installed
if ! util::has zsh; then
    util::info "Installing Zsh..."
    brew install zsh
else
    util::info "Zsh already installed"
fi

# Set Zsh as default shell if it's not
if [[ "$SHELL" != *"zsh"* ]]; then
    util::info "Setting Zsh as default shell..."
    chsh -s "$(which zsh)"
else
    util::info "Zsh is already the default shell"
fi
```

このセクションでは、Zsh がインストールされていない場合にインストールを行い、デフォルトシェルとして設定します。

```zsh
# Install Starship prompt if not installed
if ! util::has starship; then
    util::info "Installing Starship prompt..."
    brew install starship
else
    util::info "Starship prompt already installed"
fi

# Install Sheldon plugin manager if not installed
if ! util::has sheldon; then
    util::info "Installing Sheldon plugin manager..."
    brew install sheldon
else
    util::info "Sheldon plugin manager already installed"
fi
```

次に、Starship プロンプトと sheldon プラグインマネージャがインストールされていない場合にインストールを行います。

```zsh
# Create directories
util::info "Creating Zsh configuration directories..."
util::mkdir "${HOME}/.config"
util::mkdir "${HOME}/.config/zsh"
util::mkdir "${HOME}/.config/sheldon"
util::mkdir "${HOME}/.config/starship"

# Create symlinks for Zsh configuration files
util::info "Creating symlinks for Zsh configuration files..."
util::symlink "${ZSH_DIR}/.zshrc" "${HOME}/.zshrc"
util::symlink "${ZSH_DIR}/.zshenv" "${HOME}/.zshenv"
util::symlink "${ZSH_DIR}/.zprofile" "${HOME}/.zprofile"
util::symlink "${ZSH_DIR}/config/starship.toml" "${HOME}/.config/starship.toml"
util::symlink "${ZSH_DIR}/config/plugins.toml" "${HOME}/.config/sheldon/plugins.toml"
```

このセクションでは、Zsh 関連の設定ディレクトリを作成し、設定ファイルのシンボリックリンクを作成します。

```zsh
util::info "Zsh setup completed!"
```

最後に、Zsh のセットアップが完了したことを通知します。

### VSCode (03_vscode.zsh)

`setup/install/03_vscode.zsh`は、Visual Studio Code のインストールと設定を行います。

```zsh
#!/bin/zsh
# Visual Studio Code setup

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

util::info "Setting up Visual Studio Code..."

# Check if VSCODE_DIR exists
DOTFILES_DIR="$(util::repo_dir)"
VSCODE_DIR="${DOTFILES_DIR}/vscode"

if ! util::dir_exists "${VSCODE_DIR}"; then
    util::error "VSCode directory not found: ${VSCODE_DIR}"
    exit 1
fi
```

最初に、ユーティリティ関数を読み込み、VSCode 設定ディレクトリが存在するかを確認します。

```zsh
# Install VSCode if not installed
if ! util::has code; then
    util::info "Installing Visual Studio Code..."
    brew install --cask visual-studio-code
else
    util::info "Visual Studio Code already installed"
fi

# Create VSCode configuration directory
CONFIG_DIR="${HOME}/Library/Application Support/Code/User"
util::mkdir "${CONFIG_DIR}"
```

このセクションでは、VSCode がインストールされていない場合にインストールを行い、設定ディレクトリを作成します。

```zsh
# Create symlinks for VSCode configuration files
util::info "Creating symlinks for VSCode configuration files..."
util::symlink "${VSCODE_DIR}/settings.json" "${CONFIG_DIR}/settings.json"
util::symlink "${VSCODE_DIR}/keybindings.json" "${CONFIG_DIR}/keybindings.json"

# Install extensions
util::info "Installing VSCode extensions..."
if util::file_exists "${VSCODE_DIR}/extensions.txt"; then
    while read extension; do
        # Skip comments and empty lines
        [[ "${extension}" == \#* || -z "${extension}" ]] && continue

        util::info "Installing extension: ${extension}..."
        code --install-extension "${extension}" --force
    done < "${VSCODE_DIR}/extensions.txt"
else
    util::warning "Extensions list not found: ${VSCODE_DIR}/extensions.txt"
fi
```

このセクションでは、VSCode 設定ファイルのシンボリックリンクを作成し、`extensions.txt`ファイルに基づいて拡張機能をインストールします。

```zsh
util::info "Visual Studio Code setup completed!"
```

最後に、VSCode のセットアップが完了したことを通知します。

### Cursor (04_cursor.zsh)

`setup/install/04_cursor.zsh`は、Cursor エディタのインストールと設定を行います。

```zsh
#!/bin/zsh
# Cursor editor setup

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

util::info "Setting up Cursor editor..."

# Define dotfiles directory
DOTFILES_DIR="$(util::repo_dir)"
CONFIG_DIR="${HOME}/.config/cursor/rules"

# Check if the configuration directory exists, create if not
if ! util::dir_exists "${CONFIG_DIR}"; then
    util::info "Creating Cursor configuration directory..."
    util::mkdir "${CONFIG_DIR}"
fi
```

最初に、ユーティリティ関数を読み込み、Cursor 設定ディレクトリを定義します。ディレクトリが存在しない場合は作成します。

```zsh
# Install Cursor if not installed
if ! util::has cursor; then
    util::info "Installing Cursor editor..."
    brew install --cask cursor
else
    util::info "Cursor editor already installed"
fi

# Create Cursor configuration directory
CURSOR_CONFIG_DIR="${HOME}/.cursor"
util::mkdir "${CURSOR_CONFIG_DIR}"
```

このセクションでは、Cursor がインストールされていない場合にインストールを行い、設定ディレクトリを作成します。

```zsh
# Create default assistant.mdc file if it doesn't exist
ASSISTANT_FILE="${CURSOR_CONFIG_DIR}/assistant.mdc"
if ! util::file_exists "${ASSISTANT_FILE}"; then
    util::info "Creating default assistant configuration..."
    cat > "${ASSISTANT_FILE}" << EOL
# Cursor Assistant Configuration

## General Settings
- Default language mode: Japanese
- Memory: Remember session history
- Personality: Helpful, concise, and technical

## Code Generation Rules
- Follow project conventions and code style
- Add appropriate comments for complex logic
- Optimize for readability and maintainability
- Consider edge cases and error handling
- Use modern language features when appropriate
EOL
else
    util::info "Cursor assistant configuration already exists"
fi
```

ここでは、`assistant.mdc`ファイルが存在しない場合に、デフォルトの設定を作成します。これには Cursor アシスタントの一般設定とコード生成ルールが含まれています。

```zsh
# Create symlinks
util::info "Creating symlinks for Cursor configuration..."
util::symlink "${ASSISTANT_FILE}" "${CONFIG_DIR}/assistant.mdc"

util::info "Cursor setup completed!"
```

最後に、設定ファイルのシンボリックリンクを作成し、Cursor のセットアップが完了したことを通知します。

### Git (05_git.zsh)

`setup/install/05_git.zsh`は、Git のインストールと設定を行います。

```zsh
#!/bin/zsh
# Git configuration setup

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

util::info "Setting up Git..."

# Check if GIT_DIR exists
DOTFILES_DIR="$(util::repo_dir)"
GIT_DIR="${DOTFILES_DIR}/git"

if ! util::dir_exists "${GIT_DIR}"; then
    util::error "Git directory not found: ${GIT_DIR}"
    exit 1
fi
```

最初に、ユーティリティ関数を読み込み、Git 設定ディレクトリが存在するかを確認します。

```zsh
# Install Git if not installed
if ! util::has git; then
    util::info "Installing Git..."
    brew install git
else
    util::info "Git already installed"
fi

# Create symlinks for Git configuration files
util::info "Creating symlinks for Git configuration files..."
util::symlink "${GIT_DIR}/.gitconfig" "${HOME}/.gitconfig"
```

このセクションでは、Git がインストールされていない場合にインストールを行い、設定ファイルのシンボリックリンクを作成します。

```zsh
# Configure Git user if not already set
if ! git config --global user.name > /dev/null 2>&1 || ! git config --global user.email > /dev/null 2>&1; then
    util::info "Configuring Git user..."

    # In CI, set default values
    if util::is_ci; then
        git config --global user.name "CI User"
        git config --global user.email "ci@example.com"
    else
        # Ask for user input
        echo "Enter your Git username:"
        read git_username
        echo "Enter your Git email:"
        read git_email

        git config --global user.name "${git_username}"
        git config --global user.email "${git_email}"
    fi
else
    util::info "Git user already configured"
fi
```

このセクションでは、Git のユーザー設定が行われていない場合に、ユーザー名とメールアドレスを設定します。CI 環境では、デフォルト値が使用されます。それ以外の場合は、ユーザーに入力を求めます。

```zsh
# Configure Git defaults
util::info "Configuring Git defaults..."
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global core.editor vim

util::info "Git setup completed!"
```

最後に、Git のデフォルト設定を行い、Git のセットアップが完了したことを通知します。

### macOS (06_macos.zsh)

`setup/install/06_macos.zsh`は、macOS の設定を行います。

```zsh
#!/bin/zsh
# macOS specific setup

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

util::info "Setting up macOS specific configurations..."

# Check if running on macOS
if ! util::is_mac; then
    util::error "This script is only for macOS"
    exit 1
fi

# Check if MACOS_DIR exists
DOTFILES_DIR="$(util::repo_dir)"
MACOS_DIR="${DOTFILES_DIR}/macos"

if ! util::dir_exists "${MACOS_DIR}"; then
    util::error "macOS directory not found: ${MACOS_DIR}"
    exit 1
fi
```

最初に、ユーティリティ関数を読み込み、macOS 上で実行されていることを確認し、macOS 設定ディレクトリが存在するかを確認します。

```zsh
# Create necessary directories
util::info "Creating necessary directories..."
util::mkdir "${HOME}/Library/LaunchAgents"

# Create symlinks for macOS LaunchAgents
if util::file_exists "${MACOS_DIR}/system.environment.plist"; then
    util::info "Creating symlinks for macOS LaunchAgents..."
    util::symlink "${MACOS_DIR}/system.environment.plist" "${HOME}/Library/LaunchAgents/system.environment.plist"
else
    util::warning "LaunchAgent not found: ${MACOS_DIR}/system.environment.plist"
fi

# Apply macOS settings
if util::file_exists "${MACOS_DIR}/macos.sh"; then
    util::info "Applying macOS settings..."
    source "${MACOS_DIR}/macos.sh"
else
    util::warning "macOS settings script not found: ${MACOS_DIR}/macos.sh"
fi

util::info "macOS setup completed!"
```

このセクションでは、必要なディレクトリを作成し、環境変数を設定するための LaunchAgent のシンボリックリンクを作成します。また、`macos.sh`スクリプトを実行して macOS 固有の設定を適用します。これらのファイルが見つからない場合は、警告が表示されます。

## CI/CD 設定 (test.yml)

`.github/workflows/test.yml`は、GitHub Actions を使用して dotfiles のセットアップをテストするためのワークフローを定義します。

```yaml
name: Test Installation

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - name: Check out repository
        uses: actions/checkout@v3

      - name: Install Homebrew
        run: |
          /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
          echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc

      - name: Make scripts executable
        run: chmod +x ./setup/install.sh

      - name: Run setup script
        run: FORCE=1 ./setup/install.sh
        env:
          CI: true

      - name: Verify Zsh setup
        run: |
          if [ -f "${HOME}/.zshrc" ]; then
            echo "Zsh configuration verified successfully!"
          else
            echo "Failed to verify Zsh configuration!"
            exit 1
          fi

      - name: Verify Git setup
        run: |
          if [ -f "${HOME}/.gitconfig" ]; then
            echo "Git configuration verified successfully!"
          else
            echo "Failed to verify Git configuration!"
            exit 1
          fi

      - name: Verify VSCode setup
        run: |
          if [ -f "${HOME}/Library/Application Support/Code/User/settings.json" ]; then
            echo "VSCode configuration verified successfully!"
          else
            echo "Failed to verify VSCode configuration!"
            exit 1
          fi

      - name: Verify Cursor setup
        run: |
          if [ -f "${HOME}/.config/cursor/rules/assistant.mdc" ]; then
            echo "Cursor configuration verified successfully!"
          else
            echo "Failed to verify Cursor configuration!"
            exit 1
          fi
```

このセクションでは、GitHub Actions のワークフローを定義しています。次のステップが含まれています：

1. リポジトリのチェックアウト
2. Homebrew のインストール
3. インストールスクリプトの実行可能化
4. セットアップスクリプトの実行（強制モード）
5. 各種コンポーネント（Zsh、Git、VSCode、Cursor）の設定が正しく適用されたかの検証

ワークフローは macOS 環境で実行され、各ステップが正常に完了したことを確認します。検証ステップでは、各設定ファイルが期待する場所に存在するかをチェックします。

## まとめ

dotfiles プロジェクトは、macOS のセットアップと設定を自動化するための包括的なソリューションを提供します。以下は主要なコンポーネントです：

1. **ユーティリティ関数** (`util.zsh`) - ファイル操作、メッセージ表示、環境チェックなどの共通機能を提供
2. **メインインストールスクリプト** (`install.sh`) - セットアッププロセス全体を管理
3. **各種セットアップスクリプト**:
   - **Homebrew** (`01_brew.zsh`) - パッケージマネージャとソフトウェアのインストール
   - **Zsh** (`02_zsh.zsh`) - シェル環境のセットアップ
   - **VSCode** (`03_vscode.zsh`) - エディタの設定とプラグインのインストール
   - **Cursor** (`04_cursor.zsh`) - AI エディタの設定
   - **Git** (`05_git.zsh`) - バージョン管理システムの設定
   - **macOS** (`06_macos.zsh`) - OS 固有の設定と環境変数
4. **CI/CD 設定** (`test.yml`) - 自動テストと検証

このプロジェクトは、新しい macOS マシンのセットアップを迅速かつ一貫して行うために設計されています。ユーザーは必要なコンポーネントだけを選択してインストールすることも、一括でセットアップすることもできます。設定ファイルは集中管理され、バージョン管理下に置かれているため、異なるマシン間で一貫した環境を維持することが容易になります。

各スクリプトは、必要なコマンドラインツールと GUI アプリケーションのインストール、設定ファイルのシンボリックリンク作成、デフォルト設定の構成など、それぞれの責任領域に焦点を当てています。また、CI/CD パイプラインは、変更が全ての設定コンポーネントに対して正常に機能することを保証します。
