#!/usr/bin/env bats
# The terminal config names fonts. Nothing checked they exist, so a config that
# pointed at two uninstalled families went unnoticed until Japanese text started
# rendering as .notdef boxes -- the fallback covers most of it, so the failure is
# partial and easy to read as a stray glyph rather than a missing font.

load "helpers/common"

CONFIG="$REPO_DIR/terminal/ghostty/config"

# Families named by font-family and by the right-hand side of font-codepoint-map.
configured_families() {
  grep -E '^font-family|^font-codepoint-map' "$CONFIG" \
    | sed -E 's/^font-family[[:space:]]*=[[:space:]]*//; s/^font-codepoint-map.*=//' \
    | sed -E 's/[[:space:]]+$//' \
    | sort -u
}

@test "ghostty の config はフォントを宣言している" {
  count=$(configured_families | grep -c .) || count=0
  [ "$count" -ge 2 ]
}

# Declared in the Brewfile, not merely installed here: a font that exists only on
# this machine reproduces nothing on the next one.
# Cask names do not follow from family names by any rule ("FiraCode Nerd Font"
# is font-fira-code-nerd-font, "Monaspace Neon" is font-monaspace), so match on
# the distinctive word instead of trying to derive the name.
@test "config が指すフォントは Brewfile で宣言されている" {
  missing=0
  while IFS= read -r family; do
    [ -z "$family" ] && continue
    # First word, lowercased, hyphen-insensitive: Monaspace, HackGen, FiraCode.
    key=$(printf '%s' "$family" | awk '{print tolower($1)}')
    casks=$(grep -E "^cask 'font-" "$REPO_DIR/Brewfile" | tr -d "\-'")
    hits=$(printf '%s' "$casks" | grep -ci "$key") || hits=0
    if [ "$hits" -eq 0 ]; then
      echo "UNDECLARED: $family (no cask font-* matching '$key')"
      missing=$((missing + 1))
    fi
  done < <(configured_families)
  [ "$missing" -eq 0 ]
}
