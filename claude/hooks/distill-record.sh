#!/bin/bash
# SessionEnd hook. セッションの記録を distill へ残す。
#
# 記録は会話が情報源なので、日次の cron では作れない（cron に会話は無い）。
# セッションが閉じる瞬間だけが唯一の引き金になる。
#
# hook は数秒で返さないと本体の終了を待たせるので、ここでは判定と抽出だけを
# 行い、実際の書き込みは detach した別プロセスに渡す。
#
# 判定を通らないセッションでは走らせない。1 往復の質問にまで記録を作ると、
# 一覧が薄い記録で埋まり、探せなくなる。
set -uo pipefail

LOG_DIR="$HOME/.distill/logs"
TMP_DIR="$HOME/.distill/tmp"
LOG="$LOG_DIR/record.log"
VAULT="$HOME/develop/obsidian/99_distill"
EXTRACT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/distill-transcript.py"

# 実作業と見なす編集の下限。これ未満は記録しない。
MIN_EDITS="${DISTILL_RECORD_MIN_EDITS:-3}"

mkdir -p "$LOG_DIR" "$TMP_DIR"
say() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"; }

payload=$(cat)
sid=$(printf '%s' "$payload" | /usr/bin/python3 -c 'import json,sys;print(json.load(sys.stdin).get("session_id") or "")' 2>/dev/null)
cwd=$(printf '%s' "$payload" | /usr/bin/python3 -c 'import json,sys;print(json.load(sys.stdin).get("cwd") or "")' 2>/dev/null)
tx=$(printf '%s' "$payload" | /usr/bin/python3 -c 'import json,sys;print(json.load(sys.stdin).get("transcript_path") or "")' 2>/dev/null)

[ -n "$sid" ] || exit 0
[ -n "$tx" ] && [ -f "$tx" ] || { say "$sid: transcript が無い。何もしない"; exit 0; }

# --- 判定 1: git リポジトリの中か（記録を紐付ける先が要る）---
repo_root=$(cd "${cwd:-.}" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
[ -n "$repo_root" ] || { say "$sid: git リポジトリ外。記録しない"; exit 0; }
repo=$(basename "$repo_root")

# --- 判定 2: 既に記録済みか（同じセッションを二重に書かない）---
if [ -d "$VAULT/プロジェクト/$repo/記録" ] &&
   grep -rql "^session: $sid$" "$VAULT/プロジェクト/$repo/記録" 2>/dev/null; then
  say "$sid: 既に記録がある（${repo}）。何もしない"
  exit 0
fi

# --- 判定 3: 実際に何かを変えたか ---
# 会話しかしていないセッションに記録を作ると、一覧が薄い記録で埋まる。
edits=$(grep -o '"name":"\(Edit\|Write\|NotebookEdit\)"' "$tx" 2>/dev/null | wc -l | tr -d ' ')
if [ "${edits:-0}" -lt "$MIN_EDITS" ]; then
  say "$sid: 編集 ${edits} 件 < ${MIN_EDITS}。記録しない（${repo}）"
  exit 0
fi

# --- 会話の抽出 ---
digest="$TMP_DIR/$sid.md"
extract_out=$(/usr/bin/python3 "$EXTRACT" "$tx" "$digest" 2>&1)
printf '%s\n' "$extract_out" >>"$LOG"
if [ ! -s "$digest" ]; then
  say "$sid: 会話を抽出できなかった。記録しない"
  exit 0
fi
# 「0 往復」はツール操作だけで発言が無いセッション。会話が無いものから
# 記録を書かせると、材料の無い作文になる。
turns=$(printf '%s' "$extract_out" | sed -n 's/.*: \([0-9][0-9]*\) 往復.*/\1/p' | head -1)
if [ "${turns:-0}" -lt 1 ]; then
  say "$sid: 会話が 0 往復。記録しない（${repo}）"
  rm -f "$digest"
  exit 0
fi

say "$sid: 記録を開始（$repo / 編集 ${edits} 件 / $(wc -c <"$digest" | tr -d ' ') バイト）"

# 引き金と判定だけを確かめたいとき用。書き込みを起こさずに抜ける。
if [ -n "${DISTILL_RECORD_DRY_RUN:-}" ]; then
  say "${sid}: dry-run。書き込みは起こさない"
  echo "dry-run: ${repo} / 編集 ${edits} 件"
  rm -f "$digest"
  exit 0
fi

# --- 書き込みは detach して渡す。hook は待たせない ---
nohup /bin/bash -c "
  cd '$repo_root' || exit 1
  claude -p \"/distill-project 保存先=このプロジェクト。無人実行です。\
この実行には会話がありません。会話の代わりに '$digest' を読み、それを情報源として\
セッション記録だけを書いてください（概要.md は触らないこと）。\
frontmatter の session には $sid をそのまま入れてください。\" >>'$LOG' 2>&1
  # 終了コードは信じない。支出上限などで API に拒否されても claude は 0 で
  # 抜けるため、成功と区別できない。記録が実在するかで判定する。
  if grep -rql \"^session: $sid\$\" '$VAULT/プロジェクト/$repo/記録' 2>/dev/null; then
    echo \"\$(date '+%Y-%m-%d %H:%M:%S') $sid: 記録を書いた\" >>'$LOG'
  else
    echo \"\$(date '+%Y-%m-%d %H:%M:%S') $sid: 記録が作られなかった（直前のログを見る）\" >>'$LOG'
  fi
  '$HOME/develop/other/distill-of-ai-process/.venv/bin/distill' build --out '$HOME/.distill/site' >>'$LOG' 2>&1
  rm -f '$digest'
" >/dev/null 2>&1 &

exit 0
