#!/bin/bash
# PreToolUse hook for Bash. Refuses commands that would wipe the home
# directory, the root or a system area, and raw device writes.
#
# Sessions run with bypassPermissions, so nothing else stands between a bad
# command and the disk. The command is split at ; && || | & and newlines, and
# every rm in it is checked on its own, so chaining cannot hide one.
# Before splitting, one pass over the whole command joins backslash-newline
# continuations and drops comments and quoted-delimiter heredoc bodies.
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

# Print stdin with continuations joined, comments removed and the bodies of
# heredocs with a quoted delimiter (pure data) removed. Quote state carries
# across the whole input and honours backslash escapes. # starts a comment
# only at the start of a word outside quotes and backticks; when unsure,
# text is kept, so the check errs towards blocking. Unquoted heredoc bodies
# are kept because the shell expands $( ) and backticks in them.
strip_comments() {
  awk -v SQ="'" '
    { s = s (NR > 1 ? "\n" : "") $0 }
    function word_end(ch) { return ch == "" || ch ~ /[ \t\n;&|()<>]/ }
    END {
      n = length(s); out = ""; q = ""; bt = 0; prev = "\n"; nh = 0
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (q == SQ) { out = out c; if (c == SQ) q = ""; prev = c; continue }
        if (c == "\\") {
          d = substr(s, i + 1, 1); i++
          if (d == "\n") continue
          out = out c d; prev = d; continue
        }
        if (c == "`") bt = !bt
        if (q == "\"") { out = out c; if (c == "\"") q = ""; prev = c; continue }
        if (c == SQ || c == "\"") { q = c; out = out c; prev = c; continue }
        if (c == "#" && !bt && prev ~ /[ \t\n;&|()<>]/) {
          while (i < n && substr(s, i + 1, 1) != "\n") i++
          prev = "#"; continue
        }
        if (c == "<" && substr(s, i + 1, 1) == "<" && substr(s, i + 2, 1) != "<" && prev != "<") {
          out = out "<<"; i++
          dash = 0
          if (substr(s, i + 1, 1) == "-") { dash = 1; out = out "-"; i++ }
          while (substr(s, i + 1, 1) ~ /[ \t]/) { i++; out = out substr(s, i, 1) }
          delim = ""; quoted = 0
          while (!word_end(substr(s, i + 1, 1))) {
            i++; ch = substr(s, i, 1); out = out ch
            if (ch == "\\") { quoted = 1; i++; ch = substr(s, i, 1); out = out ch; delim = delim ch; continue }
            if (ch == SQ || ch == "\"") {
              quoted = 1
              while (i < n && substr(s, i + 1, 1) != ch) { i++; out = out substr(s, i, 1); delim = delim substr(s, i, 1) }
              if (i < n) { i++; out = out ch }
              continue
            }
            delim = delim ch
          }
          if (delim != "") { nh++; hd[nh] = delim; hdash[nh] = dash; hq[nh] = quoted }
          prev = "x"; continue
        }
        out = out c; prev = c
        if (c == "\n" && nh > 0) {
          for (k = 1; k <= nh; k++) {
            while (i < n) {
              e = index(substr(s, i + 1), "\n")
              line = e ? substr(s, i + 1, e - 1) : substr(s, i + 1)
              i += e ? e : n - i
              l = line
              if (hdash[k]) sub(/^\t+/, "", l)
              if (l == hd[k]) break
              if (hq[k]) continue
              if (line ~ /\\$/) out = out substr(line, 1, length(line) - 1)
              else out = out line "\n"
            }
          }
          nh = 0; out = out "\n"
        }
      }
      print out
    }'
}

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

while IFS= read -r seg; do
  read -r -a words <<<"$seg"
  in_rm=0 rec=0 endopts=0 hit=""
  for w in "${words[@]}"; do
    if [ "$in_rm" -eq 0 ]; then
      # Command substitution and subshells glue their opener to the word.
      w="${w#\$(}"; w="${w#\(}"; w="${w#\`}"
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
done < <(printf '%s\n' "$cmd" | strip_comments | awk '{ gsub(/\|\||&&|[;|&]/, "\n"); print }')

exit 0
