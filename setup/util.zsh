#!/bin/zsh

RED='\033[0;31m'     # Red
GREEN='\033[0;32m'   # Green
YELLOW='\033[1;33m'  # Yellow
NC='\033[0m'         # Reset color

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

# Request confirmation
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

# Check if symbolic link exists
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

# Create symbolic link
util::symlink() {
  local src="$1"
  local dst="$2"
  
  # Remove existing symbolic link
  if [[ -L "$dst" ]]; then
    unlink "$dst"
  fi
  
  # Create new symbolic link
  ln -sfv "$src" "$dst"
}

# Get absolute dotfiles directory path
util::dotfiles_dir() {
  echo "${HOME}/dotfiles"
}

# Get repository root directory path
util::repo_dir() {
  # If running from cloned repository (GitHub Actions)
  if [[ -d "${GITHUB_WORKSPACE}" ]]; then
    echo "${GITHUB_WORKSPACE}"
  else
    # Find .git directory from current directory or script directory
    local search_dir="${PWD}"
    # If called from a script, try to find repo from script's directory
    if [[ -n "${SCRIPT_DIR}" ]]; then
      search_dir="${SCRIPT_DIR}/.."
    fi
    
    # Walk up the directory tree to find .git
    local current_dir="${search_dir}"
    while [[ "${current_dir}" != "/" ]]; do
      if [[ -d "${current_dir}/.git" ]]; then
        echo "${current_dir}"
        return 0
      fi
      current_dir="$(dirname "${current_dir}")"
    done
    
    # If not found, use default dotfiles directory
    echo "$(util::dotfiles_dir)"
  fi
} 