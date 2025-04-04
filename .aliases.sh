#!/bin/sh

# ----------------------------------------------------------
# シェルコマンド
# ----------------------------------------------------------
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias l='ls'
alias la='ls -a'
# ----------------------------------------------------------
# Docker
# ----------------------------------------------------------
alias d='docker'
alias dc='docker compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias dimg='docker images'

# ----------------------------------------------------------
# その他
# ----------------------------------------------------------
alias kusa='curl https://github-contributions-api.deno.dev/$(git config user.name).term'
alias tenki='wttr'
alias h='history'
alias grep='grep --color=auto'
