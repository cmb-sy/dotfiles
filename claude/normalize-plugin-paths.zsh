#!/bin/zsh
# installed_plugins.json の installPath を ~/.claude (symlink) 経由のパスから
# 各アカウント dir の実パスへ正規化する。
#
# 背景: Claude Code はプラグインの installPath を、セッション起動時の config dir
# パス（clp/clw 環境では ~/.claude symlink 経由のパス）のまま記録する。この状態で
# 別ターミナルの clp/clw が symlink を付け替えると、稼働中セッションのフック解決が
# もう一方のアカウントの plugins/cache を参照してしまい、
# "Plugin directory does not exist ... run /plugin to reinstall" を毎 Stop で吐く
# （実体は無傷なので再インストールは不要・誤診）。プラグインの新規インストール/
# 更新のたびに symlink パスが再記録されるため、symlink 切替経路 (_claude_account_link)
# から毎回この正規化を通して機械的に再発を防ぐ。
#
# 冪等・高速（変更が無ければ書き込まない）。JSON の破損を避けるため
# tmp ファイルへ書いてから rename する。
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
    sys.exit(0)  # 壊れた/読めないファイルには触らない

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
# Phase 2: プラグイン cache の相互互換リンク
#
# Phase 1 の installPath 正規化はファイル上の記録しか直せない。稼働中の
# セッションは起動時に ~/.claude (symlink) 経由で解決した絶対パスをメモリに
# 保持しており、別ターミナルの clp/clw が symlink を付け替えると、以後の
# フック解決がもう一方のアカウントの plugins/cache を指す。バージョン構成が
# アカウント間で違うと "Plugin directory does not exist" を毎 Stop で吐く。
#
# 対策: cache の {marketplace}/{plugin}/{version} を両アカウントで突き合わせ、
# 片方にしか無い version dir をもう片方へ symlink する。どちらへ flip しても
# 稼働中セッションのパスが実体へ解決される。冪等・追加のみ（実体には触らない）。
# 実体が消えて宙に浮いた相互リンクだけは掃除する（他の symlink には触らない）。
# ---------------------------------------------------------------------------
_priv_cache="${CLAUDE_ACCOUNT_PRIVATE_DIR:-$HOME/.claude-private}/plugins/cache"
_work_cache="${CLAUDE_ACCOUNT_WORK_DIR:-$HOME/.claude-work}/plugins/cache"

_prune_dangling_mirror() {
  local root="$1" other_root="$2" link target
  [ -d "$root" ] || return 0
  for link in "$root"/*/*/*(N@); do
    [ -e "$link" ] && continue          # 生きているリンクは残す
    target="$(readlink "$link")"
    case "$target" in
      "$other_root"/*) rm -f "$link" ;; # 自分たちが張った相互リンクのみ削除
    esac
  done
}

_mirror_missing_versions() {
  local src_root="$1" dst_root="$2" ver_dir rel dst
  [ -d "$src_root" ] || return 0
  for ver_dir in "$src_root"/*/*/*(N/); do
    [ -L "$ver_dir" ] && continue       # 相互リンク自体は複製元にしない
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
