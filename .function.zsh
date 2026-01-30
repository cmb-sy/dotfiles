#!/bin/zsh

# ----------------------------------------------------------
# Weather function
# ----------------------------------------------------------
wttr() {
	local location="${1// /+}"
	shift 2>/dev/null
	local args=""
	for p in "$@"; do
		args+=" --data-urlencode $p "
	done
	curl -fsSL -H "Accept-Language: ${LANG%_*}" $args --compressed "wttr.in/${location}"
}

autoload -Uz wttr
