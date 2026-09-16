#!/usr/bin/env bats
# help_key が herdr の実際のキー割り当てから取り残されないようにする。
#
# help_key は手書きの一覧なので、config.toml にキーを足しても黙って古いまま
# になる。実際 Cmd+Opt+W と Cmd+Ctrl+M の 2 件が抜けていた。
#
# 突き合わせの根拠は config.toml 側の行末コメント（`key = "alt+f9"  # Cmd+Ctrl+M`）。
# herdr が解釈する chord 名は Cmd 表記と対応しないので、人間向けの対応表は
# このコメントしかない。

load "helpers/common"

setup() {
  CONF="$REPO_DIR/terminal/herdr/config.toml"
  HELP="$REPO_DIR/bin/help_key"
}

# config.toml のキー行から、行末コメントの Cmd 表記を拾う。
declared_keys() {
  grep -E '^\s*(key|previous_tab|next_tab|new_tab|close_workspace|previous_workspace|next_workspace)\s*=' "$CONF" |
    sed -n 's/.*#[[:space:]]*\(Cmd[^[:space:]]*\).*/\1/p'
}

# help_key の "Cmd+Opt+Up / Down" のような並記を個別のキーへ展開する。
listed_keys() {
  "$HELP" herdr | sed 's/\x1b\[[0-9;]*m//g' | python3 -c '
import re, sys
for line in sys.stdin:
    m = re.match(r"\s+(\S.*?)\s{2,}", line)
    if not m:
        continue
    combo = m.group(1)
    if " / " not in combo:
        print(combo)
        continue
    head, _, tail = combo.rpartition("+")
    for part in tail.split(" / "):
        print(f"{head}+{part}" if head else part)
'
}

@test "config.toml のキーはすべて help_key に載っている" {
  missing=0
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    if ! listed_keys | grep -qxF "$key"; then
      echo "help_key に無い: $key"
      missing=$((missing + 1))
    fi
  done < <(declared_keys)
  [ "$missing" -eq 0 ]
}

@test "突き合わせの材料が両側とも空でない" {
  # 上のテストは、どちらかが空でも「差分なし」で通ってしまう。
  n=$(declared_keys | grep -c .) || n=0
  [ "$n" -ge 6 ]
  m=$(listed_keys | grep -c .) || m=0
  [ "$m" -ge 6 ]
}

@test "help_key は引数なしで全セクションを出す" {
  run "$HELP"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep -qF 'herdr (inside Ghostty)'
}
