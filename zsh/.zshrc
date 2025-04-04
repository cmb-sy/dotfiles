# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

#!/bin/zsh

# ----------------------------------------------------------
# Zsh
# ----------------------------------------------------------
# 履歴関連の設定
setopt hist_ignore_dups     # 直前と同じコマンドを履歴に残さない
setopt hist_no_store        # historyコマンドを履歴に残さない
setopt share_history        # 履歴を共有する
setopt hist_reduce_blanks   # 余分な空白を削除
setopt hist_ignore_space    # スペースで始まるコマンドは履歴に残さない

# 補完関連の設定
setopt auto_list            # 補完候補を一覧表示
setopt auto_menu            # 補完キー連打で補完候補を順に表示
setopt auto_param_slash     # ディレクトリ名の補完で末尾にスラッシュを追加
setopt auto_param_keys      # カッコの対応などを自動的に補完
setopt list_packed          # 補完候補をできるだけ詰めて表示
setopt list_types           # 補完候補にファイルの種類も表示

# ディレクトリ移動関連
setopt auto_cd              # ディレクトリ名のみでcdする
setopt auto_pushd           # cd時にディレクトリスタックに追加
setopt pushd_ignore_dups    # 重複したディレクトリをスタックに追加しない

# その他
setopt correct              # コマンドのスペルミスを修正する
setopt no_beep              # ビープ音を鳴らさない
setopt interactive_comments # コマンドラインでコメントを使用できる

# ----------------------------------------------------------
# 補完の設定
# ----------------------------------------------------------
autoload -Uz compinit && compinit
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'       # 大文字小文字を区別しない
zstyle ':completion:*:default' menu select=2              # 補完候補をカーソルで選択可能に
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"   # 補完候補を色分け

# ----------------------------------------------------------
# zshプラグイン管理 (sheldon)とテーマ
# ----------------------------------------------------------
eval "$(sheldon source)"
cp .config/.p10k.zsh ~/ && source ${HOME}/.p10k.zsh

# ----------------------------------------------------------
# 設定ファイル
# ----------------------------------------------------------
source ${HOME}/.function.zsh
source ${HOME}/.aliases

# ----------------------------------------------------------
# Node.js
# ----------------------------------------------------------
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# ----------------------------------------------------------
# conda
# ----------------------------------------------------------
source ${HOME}/miniconda3/etc/profile.d/conda.sh
conda config --set auto_activate_base false
