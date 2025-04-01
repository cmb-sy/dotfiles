#!/bin/zsh
# =========================================================
# Zsh環境変数設定 - システム全体の環境変数を定義
# =========================================================

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
export HISTSIZE=1000000     # メモリに保存される履歴の件数
export SAVEHIST=1000000     # ファイルに保存される履歴の件数

# ----------------------------------------------------------
# PATHの設定
# ----------------------------------------------------------
export PATH="/usr/local/bin:${PATH}"
export PATH="${HOME}/.asdf/bin:${PATH}"
export PATH="${HOME}/.asdf/shims:${PATH}"
export PATH="/opt/homebrew/bin:$PATH"

# ----------------------------------------------------------
# Python設定
# ----------------------------------------------------------
export PATH="/usr/bin/python:$PATH"

