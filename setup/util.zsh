#!/bin/zsh

RED='\033[0;31m'     # 赤色
GREEN='\033[0;32m'   # 緑色
YELLOW='\033[1;33m'  # 黄色
NC='\033[0m'         # 色のリセット

# エラーメッセージを赤色で表示
util::error() {
  local message="$1"
  echo -e "\e[31m${message}\e[m"
}

# 警告メッセージを黄色で表示
util::warning() {
  local message="$1"
  echo -e "\e[33m${message}\e[m"
}

# 情報メッセージを緑色で表示
util::info() {
  local message="$1"
  echo -e "\e[32m${message}\e[m"
}

# 確認を要求
util::confirm() {
  local message="$1"

  # FORCEが1に設定されている場合、またはCI環境の場合は自動確認
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

# CI環境で実行されているかどうかを確認
util::is_ci() {
  if [[ -n "${CI}" && "${CI}" == "true" ]]; then
    return 0
  fi

  return 1
}

# コマンドが存在するかどうかを確認
util::has() {
  type "$1" > /dev/null 2>&1
  return $?
}

# macOSで実行されているかどうかを確認
util::is_mac() {
  [[ "$(uname)" == "Darwin" ]]
  return $?
}

# ファイルが存在するかどうかを確認
util::file_exists() {
  [[ -f "$1" ]]
  return $?
}

# ディレクトリが存在するかどうかを確認
util::dir_exists() {
  [[ -d "$1" ]]
  return $?
}

# シンボリックリンクが存在するかどうかを確認
util::link_exists() {
  [[ -L "$1" ]]
  return $?
}

# ディレクトリが存在しない場合は作成
util::mkdir() {
  if [[ ! -d "$1" ]]; then
    mkdir -p "$1"
  fi
}

# シンボリックリンクを作成
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

# 絶対dotfilesディレクトリパスを取得
util::dotfiles_dir() {
  echo "${HOME}/.dotfiles"
}

# リポジトリのルートディレクトリパスを取得
util::repo_dir() {
  # クローンされたリポジトリから実行されている場合（GitHub Actions）
  if [[ -d "${GITHUB_WORKSPACE}" ]]; then
    echo "${GITHUB_WORKSPACE}"
  elif [[ -d "${PWD}/.git" ]]; then
    echo "${PWD}"
  else
    # インストールされた場所から実行されている場合
    echo "$(util::dotfiles_dir)"
  fi
} 