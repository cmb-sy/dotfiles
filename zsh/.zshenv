#!/bin/zsh

# ----------------------------------------------------------
# 基本設定
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
# 履歴の設定
# ----------------------------------------------------------
export HISTFILE="${HOME}/.zsh-history"
export HISTSIZE=1000000
export SAVEHIST=1000000

# ----------------------------------------------------------
# PATHの設定
# ----------------------------------------------------------
export PATH="/usr/local/bin:${PATH}"
export PATH="${HOME}/.asdf/bin:${PATH}"
export PATH="${HOME}/.asdf/shims:${PATH}"
export PATH="/opt/homebrew/bin:$PATH"

export PATH="/usr/bin/python:$PATH"
export PATH="${HOME}/miniconda3/bin:$PATH"
