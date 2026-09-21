# herdr-marks.sh — the set of session markers, shared by herdr-mark and
# herdr-sort. Sourced, not executed.
#
# The set is data, not code: the picker can add to it, so it lives in a state
# file rather than in either script. Seeded from the defaults below the first
# time it is read, so a fresh machine still has something to pick from.
#
# Format: one "<marker><TAB><label>" per line. The label is what the picker
# shows next to the marker and may be empty.

HERDR_MARKS_FILE="${HERDR_MARKS_FILE:-$HOME/.local/state/herdr/marks.tsv}"

# Retired from the picker but still stripped, so rows marked before a marker
# was removed can still be cleared.
HERDR_LEGACY_MARKS="${HERDR_LEGACY_MARKS:-🔵}"

marks_seed() {
  [ -f "$HERDR_MARKS_FILE" ] && return 0
  mkdir -p "${HERDR_MARKS_FILE%/*}" || return 1
  printf '%s\t%s\n' "🤖" "対応中" "📤" "返事待ち" "🟢" "general" > "$HERDR_MARKS_FILE"
}

# "<marker><TAB><label>" per line, in picker order.
marks_entries() {
  marks_seed || return 1
  grep -v '^[[:space:]]*$' "$HERDR_MARKS_FILE" 2>/dev/null || true
}

# Markers only, one per line, offered ones first then the retired ones. Both
# are stripped from a label; only the offered ones appear in the picker.
marks_strippable() {
  marks_entries | cut -f1
  printf '%s\n' $HERDR_LEGACY_MARKS
}

marks_is_offered() {  # $1 = marker
  marks_entries | cut -f1 | grep -qxF "$1"
}

# Append a marker. Refuses anything that would break the file or the parser:
# an empty value, whitespace (the field separator), an over-long string (a
# pasted sentence rather than a marker), or one already present.
marks_add() {  # $1 = marker, $2 = label (may be empty)
  case "$1" in
    '') printf 'marks_add: empty marker\n' >&2; return 1 ;;
    *[[:space:]]*) printf 'marks_add: a marker cannot contain whitespace\n' >&2; return 1 ;;
  esac
  if [ "${#1}" -gt 8 ]; then
    printf 'marks_add: marker is too long (%s characters); expected a single symbol\n' "${#1}" >&2
    return 1
  fi
  if marks_is_offered "$1"; then
    printf 'marks_add: %s is already in the set\n' "$1" >&2
    return 1
  fi
  marks_seed || return 1
  printf '%s\t%s\n' "$1" "$2" >> "$HERDR_MARKS_FILE"
}
