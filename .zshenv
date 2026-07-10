#!/bin/zsh

# ----------------------------------------------------------
# Basic Settings
# ----------------------------------------------------------
export LANG=en_US.UTF-8 
export LC_ALL=en_US.UTF-8
export TZ=Asia/Tokyo
export EDITOR=vim
export PAGER=lv
export SHELL=zsh
export XDG_CONFIG_HOME=${HOME}/.config
export XDG_CACHE_HOME=${HOME}/.cache
export XDG_DATA_HOME=${HOME}/.local/share
export XDG_STATE_HOME=${HOME}/.local/state

# ----------------------------------------------------------
# History Settings
# ----------------------------------------------------------
export HISTFILE="${HOME}/.zsh-history"
export HISTSIZE=1000000
export SAVEHIST=1000000

# ----------------------------------------------------------
# PATH Settings
#
# .zshrc にも同じ prepend があるが重複ではない:
#   - ここ (.zshenv): 非対話シェル (zsh script.zsh, hooks) にも PATH を届ける
#   - .zshrc: login shell では /etc/zprofile の path_helper が .zshenv の後に
#     PATH を並べ替えるため、再 prepend して優先順位を復元する
# 片方だけ変更すると挙動が食い違うので、変更時は両方を揃えること。
# ----------------------------------------------------------
export PATH="/usr/local/bin:${PATH}"
export PATH="/opt/homebrew/bin:$PATH"
export PATH="${HOME}/dotfiles/bin:${PATH}"
export PATH="${HOME}/.local/bin:${PATH}"