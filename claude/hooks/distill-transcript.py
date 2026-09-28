#!/usr/bin/env python3
"""Turn a Claude Code transcript into a readable conversation digest.

Session records are written from the conversation, but a raw transcript is
JSONL that mixes tool calls, tool output and attachments, and reaches tens of
megabytes (57MB observed). Feeding that to a model is neither affordable nor
useful: the record needs what was asked and what was answered, not the bytes
that flowed through the tools.

Keeps user prompts and assistant prose. Drops tool_use, tool_result,
attachments, thinking and the bookkeeping entry types.

A session that stays open for days is recorded more than once, so the digest
can start part way in: --from-byte skips what an earlier record already
covered. --offset-after finds where that part ends when only the time of the
earlier record is known (a record written by hand inside the session).

An open session also keeps appending bookkeeping lines with no conversation,
so --last-activity reports when and where the conversation itself ends.

    distill-transcript.py <transcript.jsonl> <out.md> [--max-bytes N] [--from-byte N] [--to-byte N]
    distill-transcript.py --offset-after <epoch> <transcript.jsonl>
    distill-transcript.py --last-activity <transcript.jsonl>...
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path

# Entry types that carry conversation. Everything else is bookkeeping
# (mode, worktree-state, file-history-*, ai-title, queue-operation, ...).
_KEEP = {"user", "assistant"}

# Blocks the harness injects into user-role entries. They are not what the
# user typed, and one of them (a skill body) is large enough to fill the whole
# budget on its own.
_STRIP_TAGS = ("system-reminder", "local-command-caveat", "command-message",
               "command-name", "command-args", "local-command-stdout",
               "local-command-stderr", "task-notification")

# Chunks that start with these are harness payloads, not conversation.
_DROP_PREFIX = ("Base directory for this skill:", "Caveat: The messages below",
                "[Request interrupted", "<task-notification>",
                "Launching skill:")


def _text_blocks(content) -> list[str]:
    """Pull plain text out of a message body, whatever shape it has."""
    if isinstance(content, str):
        return [content]
    if not isinstance(content, list):
        return []
    out = []
    for b in content:
        if isinstance(b, str):
            out.append(b)
        elif isinstance(b, dict) and b.get("type") == "text":
            out.append(b.get("text") or "")
    return out


def _strip_tags(text: str) -> str:
    for tag in _STRIP_TAGS:
        text = re.sub(rf"<{tag}>.*?</{tag}>", "", text, flags=re.S)
        text = re.sub(rf"<{tag}>.*?$", "", text, flags=re.S)
    return text


def _clean(chunks: list[str]) -> str:
    kept = []
    for c in chunks:
        c = _strip_tags(c or "").strip()
        if not c or c.startswith(_DROP_PREFIX):
            continue
        kept.append(c)
    return "\n\n".join(kept).strip()


def _lines_from(f, start: int):
    """Yield (offset, text) for each whole line at or after byte `start`."""
    if start > 0:
        f.seek(start - 1)
        # 行の途中から読み始めない。半端な行は JSON として壊れている。
        if f.read(1) != b"\n":
            f.readline()
    pos = f.tell()
    for raw in iter(f.readline, b""):
        yield pos, raw.decode(errors="ignore")
        pos += len(raw)


def _epoch(stamp) -> float | None:
    if not isinstance(stamp, str):
        return None
    try:
        return datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def offset_after(path: Path, epoch: float) -> int:
    """Byte offset of the first line stamped later than `epoch`.

    Lines without a timestamp do not decide the boundary. When nothing is
    later, the whole file counts as covered and the file size is returned.
    """
    with path.open("rb") as f:
        for pos, line in _lines_from(f, 0):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            t = _epoch(d.get("timestamp")) if isinstance(d, dict) else None
            if t is not None and t > epoch:
                return pos
    return path.stat().st_size


# 最後の会話は末尾近くにある。まず末尾だけを読み、無ければ頭から読み直す。
_TAIL_BYTES = 1 << 20


def last_activity(path: Path) -> tuple[float, int]:
    """(time, end offset) of the last conversation entry.

    An open session keeps appending bookkeeping (mode, last-prompt, ...)
    without any conversation, so neither the file's mtime nor its size says
    when the work stopped. The end offset is where the conversation ends; the
    time is 0 when no conversation entry carries a timestamp.
    """
    size = path.stat().st_size
    starts = (size - _TAIL_BYTES, 0) if size > _TAIL_BYTES else (0,)
    with path.open("rb") as f:
        for start in starts:
            end, when = 0, 0.0
            for _, line in _lines_from(f, start):
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(d, dict) or d.get("type") not in _KEEP:
                    continue
                # 読んだ直後の位置がこの行の終わり。
                end = f.tell()
                when = _epoch(d.get("timestamp")) or when
            if end:
                return when, end
    return 0.0, 0


def digest(path: Path, start: int = 0, stop: int | None = None) -> list[tuple[str, str]]:
    """Return [(role, text)] in order. Unreadable lines are skipped.

    `stop` bounds the part to read; lines starting at or after it are left
    for the next record.
    """
    turns: list[tuple[str, str]] = []
    with path.open("rb") as f:
        for pos, line in _lines_from(f, start):
            if stop is not None and pos >= stop:
                break
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if not isinstance(d, dict):
                continue
            if d.get("type") not in _KEEP:
                continue
            msg = d.get("message") or {}
            text = _clean(_text_blocks(msg.get("content", d.get("content"))))
            if not text:
                continue
            role = "ユーザー" if d["type"] == "user" else "応答"
            # 連続する同じ役はまとめる。分けても読みの助けにならない。
            if turns and turns[-1][0] == role:
                turns[-1] = (role, turns[-1][1] + "\n\n" + text)
            else:
                turns.append((role, text))
    return turns


def render(turns: list[tuple[str, str]], max_bytes: int) -> str:
    body = "\n\n".join(f"## {role}\n\n{text}" for role, text in turns)
    raw = body.encode()
    if len(raw) <= max_bytes:
        return body
    # 収まらないときは末尾を優先して残す。記録は「最終的にどうなったか」を
    # 書くものなので、切るなら前を切る。
    head = int(max_bytes * 0.3)
    tail = max_bytes - head
    return (raw[:head].decode(errors="ignore")
            + "\n\n## （中略：長いため会話の中盤を省略しました）\n\n"
            + raw[-tail:].decode(errors="ignore"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("transcript", nargs="?")
    ap.add_argument("out", nargs="?")
    ap.add_argument("--max-bytes", type=int, default=120_000)
    ap.add_argument("--from-byte", type=int, default=0)
    ap.add_argument("--to-byte", type=int)
    ap.add_argument("--offset-after", type=float, metavar="EPOCH")
    ap.add_argument("--last-activity", nargs="+", metavar="TRANSCRIPT")
    args = ap.parse_args()
    if args.max_bytes <= 0:
        ap.error("--max-bytes は 1 以上")
    if args.from_byte < 0:
        ap.error("--from-byte は 0 以上")
    if args.to_byte is not None and args.to_byte < 0:
        ap.error("--to-byte は 0 以上")

    if args.last_activity:
        # 巡回は候補をまとめて 1 回で聞く。python の起動を候補ごとに払わない。
        # 1 行に「時刻 会話の終わり パス」。読めないものは飛ばす。
        for name in args.last_activity:
            try:
                when, end = last_activity(Path(name).expanduser())
            except OSError as e:
                print(f"読めない: {name}: {e}", file=sys.stderr)
                continue
            print(f"{int(when)}\t{end}\t{name}")
        return 0
    if args.transcript is None:
        ap.error("transcript が要る")

    src = Path(args.transcript).expanduser()
    if not src.is_file():
        print(f"transcript が無い: {src}", file=sys.stderr)
        return 1
    if args.offset_after is not None:
        print(offset_after(src, args.offset_after))
        return 0
    if args.out is None:
        ap.error("out が要る（--offset-after のときだけ省ける）")
    turns = digest(src, args.from_byte, args.to_byte)
    if not turns:
        print("会話が取れなかった", file=sys.stderr)
        return 2
    out = Path(args.out).expanduser()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(render(turns, args.max_bytes))
    users = sum(1 for r, _ in turns if r == "ユーザー")
    print(f"{out}: {users} 往復 / {out.stat().st_size} バイト")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
