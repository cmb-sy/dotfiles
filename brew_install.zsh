#!/bin/zsh -eux

export HOMEBREW_NO_AUTO_UPDATE=1

# command install
formulas=(
    fzf
    sheldon
    git
    nodebrew
    yarn
    gengig
    tsc
)

# GUI application install
casks=(
  docker
  github
  google-chrome
  microsoft-teams
  slack
  sourcetree
  visual-studio-code
  zoom
)

# Install Homebrew if not installed
which brew >/dev/null 2>&1 || /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

# Run brew doctor
which brew >/dev/null 2>&1 && brew doctor

# Run brew update
which brew >/dev/null 2>&1 && brew update

# Run brew upgrade
brew upgrade

brew update
brew tap homebrew/cask-fonts
brew tap ktr0731/evans
brew tap jesseduffield/lazydocker

# Install formulas
for formula in "${formulas[@]}"; do
  brew install "$formula"
done

# Initialize starship if installed
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

case "${OSTYPE}" in
darwin*)
  for cask in "${casks[@]}"; do
    brew install --cask "$cask"
  done

  GCC_VER=$(ls $(brew --prefix)/bin | grep -E "^g\+\+\-(\d+) \->" | awk '{print $1}' | sed -e "s/g++-//g")
  sudo ln -snfv "$(brew --prefix gcc)/gcc-${GCC_VER}" /usr/local/bin/gcc
  sudo ln -snfv "$(brew --prefix gcc)/g++-${GCC_VER}" /usr/local/bin/g++
  ;;
linux*)
  brew install docker
  ;;
esac

unset HOMEBREW_NO_AUTO_UPDATE
