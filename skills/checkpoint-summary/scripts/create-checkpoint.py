#!/usr/bin/env python3

from __future__ import annotations

import argparse
import datetime as dt
import secrets
import subprocess
from pathlib import Path
import re
import sys


def slugify(text: str) -> str:
    normalized = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return normalized[:48] or "checkpoint"


def current_branch() -> str:
    try:
        result = subprocess.run(
            ["git", "branch", "--show-current"],
            check=True,
            capture_output=True,
            text=True,
        )
    except Exception:
        return ""
    return result.stdout.strip()


def build_template(topic: str, created_at: str, branch: str, cwd: Path) -> str:
    branch_line = branch or "<unknown>"
    return f"""# Checkpoint Summary

- Topic: {topic}
- Created: {created_at}
- Branch: {branch_line}
- Cwd: {cwd}

## Goal

- TODO

## Current State

- TODO

## Decisions

- TODO

## Files

- TODO

## Commands

- TODO

## Open Questions

- TODO

## Next Steps

- TODO
"""


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("topic", help="brief session topic for filename + summary")
    parser.add_argument(
        "--output-dir",
        default=".tmp/checkpoints",
        help="checkpoint directory relative to current working directory",
    )
    args = parser.parse_args(argv)

    now = dt.datetime.now(dt.timezone.utc)
    timestamp = now.strftime("%Y%m%d-%H%M%SZ")
    unique_id = secrets.token_hex(4)
    topic_slug = slugify(args.topic)

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    checkpoint_path = output_dir / f"{timestamp}-{unique_id}-{topic_slug}.md"
    template = build_template(
        topic=args.topic,
        created_at=now.isoformat(),
        branch=current_branch(),
        cwd=Path.cwd(),
    )
    checkpoint_path.write_text(template)
    print(checkpoint_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
