#!/bin/zsh -eux

export HOMEBREW_NO_AUTO_UPDATE=1

# command isntall
formulas=(
  act
  asdf
  awscli
  bash-completion
  bat
  binutils
  bpytop
  cmake
  composer
  coreutils
  curl
  emojify
  evans
  exa
  expect
  ffmpeg
  font-hackgen-nerd
  fzf
  gallery-dl
  gawk
  gcc
  gibo
  git-extras
  git-flow
  git-lfs
  git-secrets
  gh
  golangci-lint
  gpg
  graphviz
  groff
  hacker1024/hacker1024/coretemp
  htop
  imagemagick
  jq
  kubectl
  kubectx
  lazydocker
  lazygit
  libpq
  mailhog
  minio/stable/mc
  mkvtoolnix
  nmap
  nkf
  pandoc
  pgcli
  php
  protobuf
  prototool
  rename
  rtorrent
  sheldon
  shellcheck
  sl
  sops
  starship
  telnet
  terraform
  terraformer
  tldr
  uniutils
  wget
  yarn
  youtube-dl
  yt-dlp
)

# GUI application install
casks=(
  docker
  github
  google-chrome
  iterm2
  keycastr
  microsoft-teams
  slack
  sourcetree
  visual-studio-code
  zoom
)

brew update
brew tap homebrew/cask-fonts
brew tap ktr0731/evans
brew tap jesseduffield/lazydocker

for formula in ${formulas[@]}; do
  brew install ${formula}
done

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

eval "$(starship init zsh)"