#!/bin/zsh
# Normalize plugin installPath in installed_plugins.json from the ~/.claude
# symlink path to each account dir's real path.
#
# Claude Code records installPath using the config-dir path seen at session
# start (the ~/.claude symlink under clp/clw). When another terminal flips the
# symlink, live sessions resolve hooks against the other account's plugins and
# emit "Plugin directory does not exist ... run /plugin to reinstall" on every
# Stop. Reinstalling is a misdiagnosis — the files are intact. Installs and
# updates re-record the symlink path, so _claude_account_link reruns this on
# every switch. Idempotent (no write when unchanged); writes to a tmp file
# then renames to avoid corrupting the JSON.
set -u

for account_dir in "${CLAUDE_ACCOUNT_PRIVATE_DIR:-$HOME/.claude-private}" \
                   "${CLAUDE_ACCOUNT_WORK_DIR:-$HOME/.claude-work}"; do
  json="${account_dir}/plugins/installed_plugins.json"
  [ -f "$json" ] || continue
  ACCOUNT_DIR="$account_dir" JSON_PATH="$json" python3 - <<'PYEOF'
import json, os, sys

path = os.environ["JSON_PATH"]
real_prefix = os.environ["ACCOUNT_DIR"] + "/plugins/"
symlink_prefix = os.path.join(os.environ["HOME"], ".claude", "plugins") + "/"

try:
    with open(path) as f:
        data = json.load(f)
except (json.JSONDecodeError, OSError):
    sys.exit(0)  # leave corrupt/unreadable files alone

changed = False
for entries in data.get("plugins", {}).values():
    for e in entries:
        p = e.get("installPath", "")
        if p.startswith(symlink_prefix):
            e["installPath"] = real_prefix + p[len(symlink_prefix):]
            changed = True

if changed:
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    os.replace(tmp, path)
PYEOF
done

# ---------------------------------------------------------------------------
# Phase 2: cross-account compatibility links for the plugin cache.
#
# Phase 1 only fixes the on-disk record. A live session keeps the absolute
# path it resolved through ~/.claude at startup, so after a symlink flip it
# reads the other account's plugins/cache and fails when version dirs differ.
# Fix: mirror each cache {marketplace}/{plugin}/{version} dir that exists in
# only one account into the other as a symlink, so either flip direction still
# resolves to a real dir. Idempotent, additive only (never touches real dirs);
# prunes only dangling mirror links we created (other symlinks untouched).
# ---------------------------------------------------------------------------
_priv_cache="${CLAUDE_ACCOUNT_PRIVATE_DIR:-$HOME/.claude-private}/plugins/cache"
_work_cache="${CLAUDE_ACCOUNT_WORK_DIR:-$HOME/.claude-work}/plugins/cache"

_prune_dangling_mirror() {
  local root="$1" other_root="$2" link target
  [ -d "$root" ] || return 0
  for link in "$root"/*/*/*(N@); do
    [ -e "$link" ] && continue          # keep links that still resolve
    target="$(readlink "$link")"
    case "$target" in
      "$other_root"/*) rm -f "$link" ;; # remove only mirror links we created
    esac
  done
}

_mirror_missing_versions() {
  local src_root="$1" dst_root="$2" ver_dir rel dst
  [ -d "$src_root" ] || return 0
  for ver_dir in "$src_root"/*/*/*(N/); do
    [ -L "$ver_dir" ] && continue       # never mirror a mirror link itself
    rel="${ver_dir#$src_root/}"
    dst="$dst_root/$rel"
    if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
      mkdir -p "${dst:h}"
      ln -s "$ver_dir" "$dst"
    fi
  done
}

_prune_dangling_mirror "$_priv_cache" "$_work_cache"
_prune_dangling_mirror "$_work_cache" "$_priv_cache"
_mirror_missing_versions "$_work_cache" "$_priv_cache"
_mirror_missing_versions "$_priv_cache" "$_work_cache"
