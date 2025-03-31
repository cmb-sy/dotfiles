#!/bin/sh
# =========================================================
# Zshエイリアス設定
# =========================================================
# ----------------------------------------------------------
# ディレクトリ移動
# ----------------------------------------------------------
alias cd='f() { local dir; dir=$(find . -type d -maxdepth 1 | fzf --reverse); if [ -n "$dir" ]; then command cd "$dir"; fi; }; f'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
# ----------------------------------------------------------
# Docker関連
# ----------------------------------------------------------
alias d='docker'
alias dc='docker compose'
alias dps='docker ps'
alias dimg='docker images'

# ----------------------------------------------------------
# その他
# ----------------------------------------------------------
alias kusa='curl https://github-contributions-api.deno.dev/$(git config user.name).term'
alias tenki='wttr'
alias h='history'
alias grep='grep --color=auto'
