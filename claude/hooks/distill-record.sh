#!/bin/bash
# セッションの記録を distill へ残す。SessionEnd フックと、開いたままの
# セッションを拾う巡回（bin/distill-record-sweep）の両方から呼ばれる。
#
# 記録は会話が情報源なので、日次の cron では作れない（cron に会話は無い）。
# 引き金はセッションが閉じた瞬間と、transcript の更新が止まって一定時間
# たったときの 2 つ。何日も開いたままのセッションは後者でしか拾えない。
#
# hook は数秒で返さないと本体の終了を待たせるので、ここでは判定と抽出だけを
# 行い、実際の書き込みは detach した別プロセスに渡す。巡回から呼ぶときは
# DISTILL_RECORD_FOREGROUND=1 で書き込みまで待ち、書き込みを渡したら 10 で
# 抜ける。巡回は 1 件ずつ順に渡すので、同時に書かせない（用語.md を取り合う）。
#
# 判定を通らないセッションでは走らせない。1 往復の質問にまで記録を作ると、
# 一覧が薄い記録で埋まり、探せなくなる。
# 記録は外部サイトへ配信されるので、業務の組織（DISTILL_RECORD_DENY_OWNERS）の
# repo のセッションも、origin の owner で見て記録しない。
#
# どこまで記録したかは transcript のバイト位置で持つ（STATE_DIR/<session>）。
# 1 行に「記録した位置 判定した時点の会話の終わり」。2 回目以降はその位置より
# 後の会話だけを材料にし、既存の記録へ書き足させる。位置は会話の行の終わりで
# 測る。開いたままのセッションは会話が無くても管理用の行（mode, last-prompt
# など）を足し続けるので、ファイルの大きさでは「伸びたか」を判定できない。
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$HOOK_DIR/$(basename "${BASH_SOURCE[0]}")"
LOG_DIR="$HOME/.distill/logs"
TMP_DIR="$HOME/.distill/tmp"
STATE_DIR="$HOME/.distill/state/record"
LOG="$LOG_DIR/record.log"
VAULT="$HOME/develop/distill-vault"
EXTRACT="$HOOK_DIR/distill-transcript.py"
BLOCKLIST="${DISTILL_RECORD_BLOCKLIST:-$HOOK_DIR/distill-record.blocklist}"
DISTILL_HOME="$HOME/develop/other/distill-of-ai-process"
DISTILL_PY="${DISTILL_RECORD_PY:-$DISTILL_HOME/.venv/bin/python}"
DISTILL_BIN="$DISTILL_HOME/.venv/bin/distill"

# 実作業と見なす編集の下限。これ未満は記録しない。
MIN_EDITS="${DISTILL_RECORD_MIN_EDITS:-3}"

# 応答が返らないまま止まると、巡回が次の候補へ進めない。
TIMEOUT_BIN=""
command -v timeout >/dev/null && TIMEOUT_BIN="timeout -k 30 1800"
command -v gtimeout >/dev/null && TIMEOUT_BIN="gtimeout -k 30 1800"

mkdir -p "$LOG_DIR" "$TMP_DIR" "$STATE_DIR"
say() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"; }

# The organization part of a repository's remote (origin by default), for the
# deny check. Organizations rather than repository names, so new repositories
# are covered.
project_owner() {
  local url
  url=$(git -C "$1" remote get-url "${2:-origin}" 2>/dev/null) || return 0
  [ -n "$url" ] || return 0
  url="${url%/}"; url="${url%.git}"
  url="${url%/*}"
  printf '%s\n' "${url##*[/:]}"
}

# そのセッションの記録ファイルを出す。どのプロジェクトの下にあってもよい。
# 2 つ目以降の引数は find の条件（-newer など）。
records_of() {
  local sid="$1"
  shift
  find "$VAULT/プロジェクト" -mindepth 3 -maxdepth 3 -path '*/記録/*.md' "$@" \
    -exec grep -l "^session: ${sid}\$" {} + 2>/dev/null
}

# 書き込み本体。detach した先でも、巡回の前景でも同じものを走らせる。
write_record() {
  local sid="$1" repo_root="$2" repo="$3" digest="$4" continued="$5"
  local mark="${digest%.md}.start" note=""
  : >"$mark"
  if [ "$continued" = 1 ]; then
    note="このセッションには既に記録があります。digest には前回の記録より後の\
会話だけが入っています。既存の記録を土台にして、この続きを書き足してください。"
  fi
  local prompt="/distill-project 保存先=このプロジェクト。無人実行です。\
この実行には会話がありません。会話の代わりに '${digest}' を読み、それを情報源として\
セッション記録だけを書いてください（概要.md は触らないこと）。\
frontmatter の session には ${sid} をそのまま入れてください。${note}"
  cd "$repo_root" || { say "${sid}: ${repo_root} に入れない。記録しない"; return 1; }
  $TIMEOUT_BIN claude -p "$prompt" \
    --add-dir "$VAULT" "$TMP_DIR" </dev/null >>"$LOG" 2>&1
  # 終了コードは信じない。支出上限などで API に拒否されても claude は 0 で
  # 抜けるため、成功と区別できない。記録が書き換わったかで判定する。
  # 続きを書き足すときは記録が既にあるので、有無ではなく更新を見る。
  # 置き場所はスキルが決める（worktree 名ではなく元のプロジェクトに寄せる）
  # ので、プロジェクトを決め打ちせずに全体から探す。
  if records_of "$sid" -newer "$mark" | grep -q .; then
    say "${sid}: 記録を書いた"
  else
    say "${sid}: 記録が作られなかった（直前のログを見る）"
  fi
  [ -x "$DISTILL_BIN" ] && "$DISTILL_BIN" build --out "$HOME/.distill/site" >>"$LOG" 2>&1
  rm -f "$digest" "$mark"
  return 0
}

# ブロックリストのアカウントを実パスで 1 行ずつ出す。リストが通常の
# ファイルとして読めない、または絶対パスにならない行があれば失敗を返す
# （呼び出し側はすべてブロックする）。書き損じた 1 行を黙って捨てると、
# そのアカウントが素通しになる。先頭の BOM はエディタが付けることがある。
# 有効な行が 1 つも無いリストも失敗にする。誤って空にしただけで素通しになる。
blocked_accounts() {
  [ -f "$BLOCKLIST" ] && [ -r "$BLOCKLIST" ] || return 1
  local line bom found=0
  bom=$(printf '\357\273\277')
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"$bom"}"
    line="${line%%#*}"
    line="${line%"${line##*[![:space:]]}"}"
    line="${line#"${line%%[![:space:]]*}"}"
    [ -n "$line" ] || continue
    # 書かれた「~/」という文字を探す。シェルに展開させない。
    # shellcheck disable=SC2088
    case "$line" in "~/"*) line="$HOME/${line#"~/"}" ;; esac
    case "$line" in /*) ;; *) return 1 ;; esac
    (cd "$line" 2>/dev/null && pwd -P) || printf '%s\n' "$line"
    found=1
  done <"$BLOCKLIST" || return 1
  [ "$found" = 1 ]
}

# そのディレクトリがブロックしたアカウントの中か。実パスで比べる。
# ブロックリストを読めないときは、どこであってもブロック扱いにする。
dir_blocked() {
  local accounts dir acct
  accounts=$(blocked_accounts) || return 0
  dir=$(cd "$1" 2>/dev/null && pwd -P) || dir="$1"
  while IFS= read -r acct; do
    [ -n "$acct" ] || continue
    case "$dir/" in "$acct"/*) return 0 ;; esac
  done <<EOF
$accounts
EOF
  return 1
}

# そのセッションがブロックしたアカウントのものか。transcript は開かない。
# 置き場所・CLAUDE_CONFIG_DIR・同じ session の transcript がブロック先にあるか
# のどれかで当たる。~/.claude はアカウントを切り替えるたびに指す先が変わる
# symlink なので、置き場所だけでは途中で切り替えたセッションを見誤る。
session_blocked() {
  local sid="$1" tx="$2" accounts acct f
  accounts=$(blocked_accounts) || return 0
  dir_blocked "$(dirname "$tx")" && return 0
  [ -n "${CLAUDE_CONFIG_DIR:-}" ] && dir_blocked "$CLAUDE_CONFIG_DIR" && return 0
  while IFS= read -r acct; do
    [ -n "$acct" ] || continue
    for f in "$acct"/projects/*/"$sid".jsonl; do
      [ -e "$f" ] && return 0
    done
  done <<EOF
$accounts
EOF
  return 1
}

if [ "${1:-}" = "--write" ]; then
  shift
  write_record "$@"
  exit $?
fi
# 巡回がアカウントを走査する前に聞く。通してよいときだけ 3 を返す。
# 1 は bash が異常終了したときにも返るので、「通す」の意味に使わない。
if [ "${1:-}" = "--is-blocked-dir" ]; then
  dir_blocked "${2:?ディレクトリが要る}" && exit 0
  exit 3
fi

case "$MIN_EDITS" in
  '' | *[!0-9]*) say "DISTILL_RECORD_MIN_EDITS が数でない（${MIN_EDITS}）。何もしない"; exit 0 ;;
esac

payload=$(cat)
# 1 回の python で 3 つとも取る。巡回は候補ごとにここを通る。
fields=$(printf '%s' "$payload" | /usr/bin/python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    d = {}
if not isinstance(d, dict):
    d = {}
for k in ("session_id", "transcript_path", "cwd"):
    print(str(d.get(k) or "").replace("\n", " "))
' 2>/dev/null)
sid=$(printf '%s\n' "$fields" | sed -n 1p)
tx=$(printf '%s\n' "$fields" | sed -n 2p)
cwd=$(printf '%s\n' "$fields" | sed -n 3p)

[ -n "$sid" ] || exit 0
# 状態ファイルの名前に使う。パスとして解釈される文字は通さない。
case "$sid" in
  *[!A-Za-z0-9_-]*) say "session_id の形が想定外。何もしない"; exit 0 ;;
esac

# --- 判定 0: 記録に使わないアカウントか ---
# ブロックしたアカウントのセッションは、transcript を開く前に返す。状態も
# ロックも作らない。ログにも session を残さない。ブロックリスト自体が
# 使えないときは、どのセッションも記録しない。
if ! blocked_accounts >/dev/null; then
  say "ブロックリストを読めない、空、または絶対パスにならない行がある（${BLOCKLIST}）。何も記録しない"
  exit 0
fi
if session_blocked "$sid" "$tx"; then
  say "記録に使わないアカウントのセッション。何もしない"
  exit 0
fi

[ -n "$tx" ] && [ -f "$tx" ] || { say "${sid}: transcript が無い。何もしない"; exit 0; }

# --- 同じ transcript を同時に判定しない（SessionEnd と巡回が重なる）---
# 強制終了で残ったロックは 30 分で見限る。SessionEnd の hook は時間切れで殺される。
lock="$STATE_DIR/${sid}.lock"
# 中にファイルが入っていても消す。rmdir で消せないロックが残ると、その
# セッションは黙って記録されなくなる。
if [ -n "$(find "$lock" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then
  rm -rf "$lock" && say "${sid}: 取り残されたロックを外した"
fi
mkdir "$lock" 2>/dev/null || exit 0
trap 'rmdir "$lock" 2>/dev/null' EXIT

state="$STATE_DIR/${sid}"
upto=""
read -r _ upto _ < <(/usr/bin/python3 "$EXTRACT" --last-activity "$tx" 2>/dev/null)
case "$upto" in '' | *[!0-9]*) say "${sid}: 会話の終わりを割り出せない。何もしない"; exit 0 ;; esac
recorded="" seen=""
[ -f "$state" ] && read -r recorded seen <"$state"
case "$recorded" in '' | *[!0-9]*) recorded="" ;; esac
case "$seen" in '' | *[!0-9]*) seen="" ;; esac
# 桁あふれする値は壊れている。比較で落ちて、そのセッションが止まり続ける。
[ "${#recorded}" -le 15 ] || recorded=""
[ "${#seen}" -le 15 ] || seen=""

# 前回判定したときから会話が伸びていなければ、判定も前回と同じになる。
# 巡回は候補を毎回すべて渡してくるので、ここで黙って返す。
[ "$seen" = "$upto" ] && exit 0

# 判定を終えたら、どこまで見たかを残す。記録した位置は書き込みを渡すとき
# だけ進める。位置が未確定なら「-」を置き、次回も既存の記録から割り出す。
remember() {
  [ -n "${DISTILL_RECORD_DRY_RUN:-}" ] && return 0
  printf '%s %s\n' "${1:--}" "$upto" >"$state"
}

# --- 判定 1: 人が対話したセッションか ---
# 対話の入口（ターミナルの cli、claude-desktop などのアプリ）だけを通す。
# SDK からの無人実行（sdk-cli / sdk-py / sdk-ts）は記録しない。記録を書く実行
# そのものも sdk-cli に当たり、通すと「記録を書いたセッションの記録」を書きに
# 行く。知らない入口は通さずに名前をログへ残す。通すと、無人の実行 1 回ごとに
# LLM を起こして薄い記録を公開することになる。入口の無い古い transcript は対話。
entry=$(head -c 1000000 "$tx" | grep -m1 -o '"entrypoint":"[^"]*"' | sed 's/.*:"//; s/"$//')
case "$entry" in
  '' | cli | claude-*) ;;
  *)
    say "${sid}: 対話ではないセッション（${entry}）。記録しない"
    remember "$recorded"
    exit 0
    ;;
esac

# --- 判定 2: git リポジトリの中か（記録を紐付ける先が要る）---
# 巡回は cwd を知らないので、transcript に残る最後の cwd を使う。
# 会話中にいたすべての場所は判定 2b でも使う。
tx_cwds=$(grep -o '"cwd":"[^"]*"' "$tx" | sed 's/^"cwd":"//; s/"$//')
if [ -z "$cwd" ]; then
  cwd=$(printf '%s\n' "$tx_cwds" | tail -1)
fi
# 分からないときに今の場所で代用すると、巡回を起こした別のセッションの
# リポジトリに紐付いてしまう。
if [ -z "$cwd" ]; then
  say "${sid}: 作業ディレクトリが分からない。記録しない"
  remember "$recorded"
  exit 0
fi
repo_root=$(cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$repo_root" ]; then
  say "${sid}: git リポジトリ外。記録しない"
  remember "$recorded"
  exit 0
fi

# --- 判定 2b: 記録してよい組織の repo か ---
# 記録は vault に入り、vault は外部サイトへ配信される。業務の自由文は
# 伏せ字化で落ちないので、組織単位で入口を閉じる。owner の表記は clone の
# 仕方で揺れるので、大文字小文字を無視して比べる。fork は upstream も見る。
# 最後の repo だけでなく、会話中にいたすべての repo を見る。途中で業務の
# repo にいた会話も本文に残る。見るのは cwd の欄だけで、本文は読まない。
# 指定は read -a で分ける。for で展開すると * がファイル名に化ける。
read -ra deny_list <<<"$(printf '%s' "${DISTILL_RECORD_DENY_OWNERS:-Resily}" | tr '[:upper:]' '[:lower:]')"
repo_denied() {
  local remote o d
  for remote in origin upstream; do
    o=$(project_owner "$1" "$remote" | tr '[:upper:]' '[:lower:]')
    [ -n "$o" ] || continue
    for d in ${deny_list[@]+"${deny_list[@]}"}; do
      [ "$o" = "$d" ] && return 0
    done
  done
  return 1
}
# 辿れない cwd（消した worktree、エスケープを含むパス）は owner を確かめられない
# ので記録しない。一時領域だけは日常的に消えるので見送る。
while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  if [ ! -d "$dir" ] || ! (cd "$dir" 2>/dev/null); then
    case "$dir" in
      /private/tmp/* | /tmp/* | /var/folders/* | /private/var/folders/*) continue ;;
    esac
    say "${sid}: 作業ディレクトリを辿れない。記録しない"
    remember "$recorded"
    exit 0
  fi
  root=$(cd "$dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || continue
  if [ -n "$root" ] && repo_denied "$root"; then
    say "${sid}: 記録しない組織の repo。記録しない"
    remember "$recorded"
    exit 0
  fi
done < <({
  printf '%s\n' "$repo_root"
  printf '%s\n' "$tx_cwds"
} | sort -u)
# 書き先のプロジェクト名。スキルと同じ規則で決める（名前を付け直したプロジェクトや
# worktree を、元のプロジェクトに寄せる）。取れなければリポジトリの名前。
repo=$(/bin/bash "$HOOK_DIR/../../bin/distill-repo-name" "$repo_root" 2>/dev/null)
[ -n "$repo" ] || repo=$(basename "$repo_root")

# --- 判定 3: 前回の記録より後に会話があるか ---
existing=$(records_of "$sid" | head -1)
if [ -z "$recorded" ]; then
  recorded=0
  if [ -n "$existing" ]; then
    # 位置の記録が無いのに記録がある = セッション内で手で書いた記録。
    # 記録の更新時刻より後の会話だけを見る。割り出せなければ全部書いた扱い。
    recorded=$(/usr/bin/python3 "$EXTRACT" --offset-after "$(stat -f %m "$existing")" "$tx" 2>/dev/null)
    case "$recorded" in '' | *[!0-9]*) recorded="$upto" ;; esac
    say "${sid}: 既に記録がある（${repo}）。その後の会話だけを見る"
  fi
fi
if [ "$recorded" -ge "$upto" ]; then
  say "${sid}: 前回の記録より後の会話が無い（${repo}）"
  remember "$recorded"
  exit 0
fi
continued=0
[ -n "$existing" ] && continued=1

# --- 判定 4: 実際に何かを変えたか ---
# 会話しかしていない区間に記録を作ると、一覧が薄い記録で埋まる。届かない
# 区間は捨てずに持ち越し、次の区間と合わせて数える。
# 区間は測った会話の終わりまで。後から足された分は次の区間で数える。
edits=$(head -c "$upto" "$tx" 2>/dev/null | tail -c +"$((recorded + 1))" |
  grep -o '"name":"\(Edit\|Write\|NotebookEdit\)"' | wc -l | tr -d ' ')
if [ "${edits:-0}" -lt "$MIN_EDITS" ]; then
  say "${sid}: 編集 ${edits} 件 < ${MIN_EDITS}。記録しない（${repo}）"
  remember "$recorded"
  exit 0
fi

# --- 判定 5: 除外.md に載っていないか ---
# 書いても表示されず、purge で消える。判定は distill 本体に任せる（自前で
# 読むと解釈が食い違う）。distill を読めないときは記録を続ける。
if [ -x "$DISTILL_PY" ]; then
  "$DISTILL_PY" - "$VAULT" "$repo" >/dev/null 2>&1 <<'PY'
import sys
from distill.vault.exclude import load
sys.exit(0 if load(sys.argv[1]).has_project(sys.argv[2]) else 3)
PY
  case $? in
    0)
      say "${sid}: 除外.md に載っている。記録しない（${repo}）"
      remember "$recorded"
      exit 0
      ;;
    3) ;;
    *) say "${sid}: 除外.md を判定できなかった。記録は続ける" ;;
  esac
fi

# --- 会話の抽出 ---
# 名前に位置を入れる。先に渡した書き込みがまだ digest を読んでいても潰さない。
digest="$TMP_DIR/${sid}-${recorded}.md"
rm -f "$digest"
extract_out=$(/usr/bin/python3 "$EXTRACT" "$tx" "$digest" --from-byte "$recorded" --to-byte "$upto" 2>&1)
printf '%s\n' "$extract_out" >>"$LOG"
if [ ! -s "$digest" ]; then
  say "${sid}: 会話を抽出できなかった。記録しない"
  remember "$recorded"
  exit 0
fi
# 「0 往復」はツール操作だけで発言が無い区間。会話が無いものから記録を
# 書かせると、材料の無い作文になる。
turns=$(printf '%s' "$extract_out" | sed -n 's/.*: \([0-9][0-9]*\) 往復.*/\1/p' | head -1)
if [ "${turns:-0}" -lt 1 ]; then
  say "${sid}: 会話が 0 往復。記録しない（${repo}）"
  rm -f "$digest"
  remember "$recorded"
  exit 0
fi

say "${sid}: 記録を開始（${repo} / 編集 ${edits} 件 / $(wc -c <"$digest" | tr -d ' ') バイト）"

# 引き金と判定だけを確かめたいとき用。書き込みも状態の更新も起こさずに抜ける。
if [ -n "${DISTILL_RECORD_DRY_RUN:-}" ]; then
  say "${sid}: dry-run。書き込みは起こさない"
  echo "dry-run: ${repo} / 編集 ${edits} 件"
  rm -f "$digest"
  exit 0
fi

# 渡した時点で記録した位置を進める。失敗しても同じ区間を書かせ直さない
# （1 区間 1 回まで）。支出上限で断られ続けるときに、巡回のたびに LLM を
# 起こさないため。
remember "$upto"
if [ -n "${DISTILL_RECORD_FOREGROUND:-}" ]; then
  write_record "$sid" "$repo_root" "$repo" "$digest" "$continued"
  exit 10
fi
nohup /bin/bash "$SELF" --write "$sid" "$repo_root" "$repo" "$digest" "$continued" \
  >/dev/null 2>&1 &
exit 0
