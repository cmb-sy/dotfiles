#!/bin/zsh -eux

export HOMEBREW_NO_AUTO_UPDATE=1

# homebrew install
echo "installing homebrew..."
which brew >/dev/null 2>&1 || /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

# brew doctor
echo "run brew doctor..."
which brew >/dev/null 2>&1 && brew doctor

# brew update
echo "run brew update..."
which brew >/dev/null 2>&1 && brew update

# command install
formulas=(
    fzf
    sheldon
    git
    miniconda
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
  macrosoft-powerpoint
  macrosoft-excel
  macrosoft-word
  visual-studio-code
  slack
  sourcetree
  cursor
  notion
  zoom
)

brew update
brew tap homebrew/cask-fonts
brew tap ktr0731/evans
brew tap jesseduffield/lazydocker

for formula in ${formulas[@]}; do
  brew install ${formula}
done

eval "$(starship init zsh)"
case "${OSTYPE}" in
darwin*)
  for cask in ${casks[@]}; do
    brew install --cask ${cask}
  done

  GCC_VER=$(ls $(brew --prefix)/bin | grep -E "^g\+\+\-(\d+) \->" | awk '{print $1}' | sed -e "s/g++-//g")
  sudo ln -snfv $(brew --prefix gcc)/gcc-${GCC_VER} /usr/local/bin/gcc
  sudo ln -snfv $(brew --prefix gcc)/g++-${GCC_VER} /usr/local/bin/g++
  ;;
linux*)
  brew install docker
  ;;
esac

unset HOMEBREW_NO_AUTO_UPDATE
