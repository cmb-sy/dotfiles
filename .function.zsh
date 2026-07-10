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

# ----------------------------------------------------------
# Usage: cdg or Cmd+Shift+F / Alt+Cmd+F (search all directories under $HOME)
# ----------------------------------------------------------
_fzf_cd_global_impl() {
	command -v fzf &>/dev/null || return 1
	[[ -d "$HOME" ]] || return 1
	local chosen
	local _find_cmd
	if command -v fd &>/dev/null; then
		# No --follow: it chases the ~/OneDrive symlink into Library/CloudStorage
		# (network-backed on-demand files), which hangs fd and freezes the picker.
		# Real targets of the dotfiles symlinks live under $HOME, so they are still found.
		_find_cmd="fd --type d --hidden -E .git -E node_modules -E .cache -E Library --max-depth 5 . $HOME"
	else
		_find_cmd="find $HOME -mindepth 1 -maxdepth 10 -type d \( -name .git -o -name node_modules -o -name .cache -o -name Library \) -prune -o -type d -print 2>/dev/null"
	fi
	chosen=$(eval "$_find_cmd" | \
		fzf --height=40% --reverse --border \
			--prompt=" cd > " \
			--header="Select directory (all under $HOME)" \
			--preview="ls -la {}" \
			--query="${1:-}")
	if [[ -n "$chosen" ]] && [[ -d "$chosen" ]]; then
		cd "$chosen" || return 1
		return 0
	fi
	return 1
}
cdg() { _fzf_cd_global_impl "$@"; }
fzf_cd_global() {
	_fzf_cd_global_impl "${LBUFFER}" && zle reset-prompt
}
zle -N fzf_cd_global
# Ghostty / WezTerm: Cmd+Shift+F or Alt+Cmd+F sends ESC [24;3~ (alt+F12 chord).
# herdr forwards only F1..F12 chords to panes and drops F13+ (CSI 25~),
# so the trigger stays in the F12 range. \e[25~ kept for real F13 keys.
for _map in emacs viins vicmd; do
	bindkey -M "$_map" '\e[24;3~' fzf_cd_global
	bindkey -M "$_map" '\e[25~' fzf_cd_global
done
# herdr tab/space chords (Cmd+Shift+[ / ], Cmd+Opt+Up / Down): consumed by herdr,
# but in plain terminal panes they reach zsh — map to no-op to avoid stray chars
for _map in emacs viins vicmd; do
	for _seq in '\e[23;2~' '\e[24;2~' '\e[23;5~' '\e[24;5~'; do
		bindkey -M "$_map" "$_seq" redisplay
	done
done
