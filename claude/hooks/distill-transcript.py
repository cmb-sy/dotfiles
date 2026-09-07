#!/usr/bin/env python3
"""Turn a Claude Code transcript into a readable conversation digest.

Session records are written from the conversation, but a raw transcript is
JSONL that mixes tool calls, tool output and attachments, and reaches tens of
megabytes (57MB observed). Feeding that to a model is neither affordable nor
useful: the record needs what was asked and what was answered, not the bytes
that flowed through the tools.

Keeps user prompts and assistant prose. Drops tool_use, tool_result,
attachments, thinking and the bookkeeping entry types.

    distill-transcript.py <transcript.jsonl> <out.md> [--max-bytes N]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
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


def digest(path: Path) -> list[tuple[str, str]]:
    """Return [(role, text)] in order. Unreadable lines are skipped."""
    turns: list[tuple[str, str]] = []
    with path.open(errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except ValueError:
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
    ap.add_argument("transcript")
    ap.add_argument("out")
    ap.add_argument("--max-bytes", type=int, default=120_000)
    args = ap.parse_args()

    src = Path(args.transcript).expanduser()
    if not src.is_file():
        print(f"transcript が無い: {src}", file=sys.stderr)
        return 1
    turns = digest(src)
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
