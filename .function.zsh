#!/bin/zsh

# ----------------------------------------------------------
# pip workaround functions (pip制限の回避関数)
# ----------------------------------------------------------
pip() {
	python3 -m pip "$@"
}

pip3() {
	python3 -m pip "$@"
}

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
