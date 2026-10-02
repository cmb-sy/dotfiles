#!/bin/bash
# PreToolUse hook for Bash. Refuses commands that would wipe the home
# directory, the root or a system area, and raw device writes.
#
# Sessions run with bypassPermissions, so nothing else stands between a bad
# command and the disk. The command is split at ; && || | & and newlines, and
# every rm in it is checked on its own, so chaining cannot hide one.
# Comments, strings and heredocs are not lexed: every word is checked, so an
# rm that is only written down is blocked too. That false block is the safe
# side; lexing them kept opening bypasses.
# Temporary areas stay deletable: /var/folders is macOS's $TMPDIR.

# A missing jq exits 0 here (fail-open); jq is installed from the Brewfile.
cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

block() {
  echo "BLOCK: Destructive system command detected ($1)" >&2
  exit 2
}

if printf '%s' "$cmd" | grep -qE '>[[:space:]]*/dev/(sd|disk|rdisk)|(^|[^[:alnum:]_])mkfs|(^|[^[:alnum:]_])dd[[:space:]]+if='; then
  block "device or filesystem write"
fi

home="${HOME%/}"

# Print an rm target with quotes removed, home spelled out and trailing
# "/", "/." and "/*" dropped. The root becomes the empty string.
norm() {
  local t
  t=$(printf '%s' "$1" | tr -d "\"'")
  case "$t" in
    \~ | \~/*) t="$home${t#\~}" ;;
    '$HOME' | '$HOME/'*) t="$home${t#\$HOME}" ;;
    '${HOME}' | '${HOME}/'*) t="$home${t#\$\{HOME\}}" ;;
    # ${HOME:?}, ${HOME%/}, ${HOME:-x} and the like all expand to home.
    '${HOME'[:%#/=+?^,-]*'}'*) t="$home${t##*\}}" ;;
  esac
  while :; do
    case "$t" in
      */\*) t="${t%/\*}" ;;
      */.) t="${t%/.}" ;;
      */) t="${t%/}" ;;
      *) break ;;
    esac
  done
  printf '%s' "$t"
}

# 0 when deleting the target recursively would take out root, home or a
# system area. A ".." component or another user's ~name could reach any of
# them, so both count as dangerous.
dangerous() {
  local t
  t=$(norm "$1")
  case "$t" in
    .. | ../* | */.. | */../*) return 0 ;;
    \~*/*) ;;
    \~?*) return 0 ;;
  esac
  case "$t" in
    "" | "$home" | /Users | /home) return 0 ;;
    /var/folders/* | /private/var/folders/* | /private/tmp/*) return 1 ;;
    /usr | /usr/* | /etc | /etc/* | /var | /var/* | /opt | /opt/* | \
      /System | /System/* | /Library | /Library/* | /bin | /bin/* | \
      /sbin | /sbin/* | /Applications | /Applications/* | /private | /private/*)
      return 0 ;;
  esac
  return 1
}

# The command as written, plus a copy with backslash-newline continuations
# joined, so a target moved to the next line is still seen with its rm.
input="$cmd"
cont=$'\\\n'  # bash 3.2 only matches this pattern from a quoted variable
joined="${cmd//"$cont"/}"
[ "$joined" = "$cmd" ] || input="$cmd"$'\n'"$joined"

while IFS= read -r seg; do
  read -r -a words <<<"$seg"
  in_rm=0 rec=0 endopts=0 hit=""
  for w in "${words[@]}"; do
    if [ "$in_rm" -eq 0 ]; then
      # A substitution can open mid-word (x=$(rm ..), pre`rm ..`): keep what
      # follows the last opener. Quotes around the command word, a subshell
      # paren and an alias-bypassing backslash are dropped.
      w="${w##*\$(}"; w="${w##*\`}"
      w="${w//\"/}"; w="${w//\'/}"; w="${w#\(}"; w="${w#\\}"
      [ "${w##*/}" = rm ] && in_rm=1
      continue
    fi
    w="${w%\"}"; w="${w%)}"; w="${w%\`}"
    [ -n "$w" ] || continue
    if [ "$endopts" -eq 0 ]; then
      case "$w" in
        --) endopts=1; continue ;;
        --recursive) rec=1; continue ;;
        --*) continue ;;
        -?*)
          case "$w" in *[rR]*) rec=1 ;; esac
          continue ;;
      esac
    fi
    dangerous "$w" && hit="$w"
  done
  if [ "$rec" -eq 1 ] && [ -n "$hit" ]; then
    block "recursive rm of $hit"
  fi
done < <(printf '%s\n' "$input" | awk '{ gsub(/\|\||&&|[;|&]/, "\n"); print }')

exit 0
