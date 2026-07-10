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
