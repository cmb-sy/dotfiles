#!/bin/zsh
# --------------------------------------------------------------------
# General Settings
# --------------------------------------------------------------------
export LANG=en_US.UTF-8 
export LC_ALL=en_US.UTF-8
export TZ=Asia/Tokyo

# --------------------------------------------------------------------
# Editter Settings
# --------------------------------------------------------------------
export EDITOR=vim
export PAGER=lv

# --------------------------------------------------------------------
# History Settings
# --------------------------------------------------------------------
export HISTFILE="${HOME}/.zsh-history"
export HISTSIZE=1000000
export SAVEHIST=1000000

# --------------------------------------------------------------------
# path setting
# --------------------------------------------------------------------
export PATH="/usr/local/bin:${PATH}"
export PATH="${HOME}/.asdf/bin:${PATH}"
export PATH="${HOME}/.asdf/shims:${PATH}"
export PATH="/opt/homebrew/bin:$PATH"

# --------------------------------------------------------------------
# Python Settings
# --------------------------------------------------------------------
export PATH="/usr/bin/python:$PATH"

