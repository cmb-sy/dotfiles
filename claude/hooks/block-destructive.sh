#!/bin/bash
# PreToolUse hook for Bash. Refuses commands that would wipe the home
# directory, the root or a system area, and raw device writes.
#
# Sessions run with bypassPermissions, so nothing else stands between a bad
# command and the disk. The command is split at ; && || | & and newlines, and
# every rm in it is checked on its own, so chaining cannot hide one. Text
# after an unquoted # is a comment and is not checked.
# Temporary areas stay deletable: /var/folders is macOS's $TMPDIR.

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
# system area.
dangerous() {
  local t
  t=$(norm "$1")
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

while IFS= read -r seg; do
  read -r -a words <<<"$seg"
  in_rm=0 rec=0 endopts=0 hit="" dq="" sq=""
  for w in "${words[@]}"; do
    # An unquoted word starting with # opens a comment. An odd count of
    # either quote so far may mean we are inside a string, where # is literal.
    case "$w" in
      \#*) [ $((${#dq} % 2)) -eq 0 ] && [ $((${#sq} % 2)) -eq 0 ] && break ;;
    esac
    dq="$dq${w//[^\"]/}"
    sq="$sq${w//[^\']/}"
    if [ "$in_rm" -eq 0 ]; then
      # Command substitution and subshells glue their opener to the word.
      w="${w#\$(}"; w="${w#(}"; w="${w#\`}"
      [ "${w##*/}" = rm ] && in_rm=1
      continue
    fi
    w="${w%)}"; w="${w%\`}"
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
done < <(printf '%s\n' "$cmd" | awk '{ gsub(/\|\||&&|[;|&]/, "\n"); print }')

exit 0
