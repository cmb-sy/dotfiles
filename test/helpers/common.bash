# test/helpers/common.bash — shared bats helpers.
# bash 3.2 note: assertions in .bats files must be `grep -qF` pipes
# (positive) or `grep -c` count compares (negative); mid-line [[ ]] and
# trailing `! cmd` pass silently.

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export REPO_DIR

# /private/tmp, not $TMPDIR: the destructive-command hook's /var rule
# matches macOS's /var/folders TMPDIR at the tool level.
make_tmpdir() {
  TEST_TMPDIR="$(mktemp -d /private/tmp/dotfiles-test.XXXXXX)"
  export TEST_TMPDIR
}

# Throwaway git repo with one commit; prints its path. Callers rm -rf it.
make_tmp_git_repo() {
  local dir
  dir="$(mktemp -d /private/tmp/dotfiles-test.XXXXXX)"
  git -C "$dir" init -q -b main
  git -C "$dir" -c user.email="test@example.com" -c user.name="test" \
    commit -q --allow-empty -m "init"
  echo "$dir"
}

# Lets inline `python3 -c` in a .bats file do `import wcag`.
PYTHONPATH="$REPO_DIR/test/helpers${PYTHONPATH:+:$PYTHONPATH}"
export PYTHONPATH

# wcag_ratio "#rrggbb" "#rrggbb" -> prints contrast ratio (2 decimals).
# Shell entry point for the math in helpers/wcag.py.
wcag_ratio() {
  python3 -c 'import sys, wcag; print(round(wcag.ratio(sys.argv[1], sys.argv[2]), 2))' "$1" "$2"
}
