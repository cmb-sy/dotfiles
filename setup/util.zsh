#!/bin/zsh
# Setup utility functions

# Display error message in red
util::error() {
  local message="$1"
  echo -e "\e[31m${message}\e[m"
}

# Display warning message in yellow
util::warning() {
  local message="$1"
  echo -e "\e[33m${message}\e[m"
}

# Display info message in green
util::info() {
  local message="$1"
  echo -e "\e[32m${message}\e[m"
}

# Ask for confirmation
util::confirm() {
  local message="$1"

  # Auto-confirm if FORCE is set to 1 or in CI environment
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

# Check if running in CI environment
util::is_ci() {
  if [[ -n "${CI}" && "${CI}" == "true" ]]; then
    return 0
  fi

  return 1
}

# Check if command exists
util::has() {
  type "$1" > /dev/null 2>&1
  return $?
}

# Check if running on macOS
util::is_mac() {
  [[ "$(uname)" == "Darwin" ]]
  return $?
}

# Check if file exists
util::file_exists() {
  [[ -f "$1" ]]
  return $?
}

# Check if directory exists
util::dir_exists() {
  [[ -d "$1" ]]
  return $?
}

# Check if link exists
util::link_exists() {
  [[ -L "$1" ]]
  return $?
}

# Create directory if it doesn't exist
util::mkdir() {
  if [[ ! -d "$1" ]]; then
    mkdir -p "$1"
  fi
}

# Create symlink
util::symlink() {
  local src="$1"
  local dst="$2"
  
  # Remove existing symlink
  if [[ -L "$dst" ]]; then
    unlink "$dst"
  fi
  
  # Create new symlink
  ln -sfv "$src" "$dst"
}

# Get absolute dotfiles directory path
util::dotfiles_dir() {
  echo "${HOME}/.dotfiles"
}

# Get repository root directory path
util::repo_dir() {
  # If running from cloned repository
  if [[ -d "${PWD}/.git" ]]; then
    echo "${PWD}"
  else
    # If running from installed location
    echo "$(util::dotfiles_dir)"
  fi
} 