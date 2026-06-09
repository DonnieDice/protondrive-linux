#!/usr/bin/env python3
"""Apply an AI-generated Markdown update to a doc file or marked section."""

from __future__ import annotations

import argparse
import os
import sys
import tempfile


def read_stdin() -> str:
    content = sys.stdin.read()
    if not content.strip():
        raise SystemExit("refusing to apply empty doc update")
    return content.rstrip() + "\n"


def replace_section(original: str, section: str, replacement: str) -> str:
    begin = f"<!-- BEGIN SECTION: {section} -->"
    end = f"<!-- END SECTION: {section} -->"
    start = original.find(begin)
    stop = original.find(end)
    if start == -1 or stop == -1 or stop < start:
        raise SystemExit(f"section markers not found for {section!r}")

    inner_start = start + len(begin)
    return (
        original[:inner_start]
        + "\n"
        + replacement.rstrip()
        + "\n"
        + original[stop:]
    )


def atomic_write(path: str, content: str) -> None:
    directory = os.path.dirname(path) or "."
    fd, tmp_path = tempfile.mkstemp(prefix=".doc-update.", dir=directory, text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
            f.write(content)
        os.replace(tmp_path, path)
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--path", required=True)
    parser.add_argument("--section")
    parser.add_argument("--mode", choices=("section", "file"), default="section")
    args = parser.parse_args()

    if not (args.path.startswith("docs/") or args.path.startswith("README.md")):
        raise SystemExit(f"refusing to edit non-doc path: {args.path}")

    replacement = read_stdin()
    with open(args.path, "r", encoding="utf-8") as f:
        original = f.read()

    if args.mode == "file":
        updated = replacement
    else:
        if not args.section:
            raise SystemExit("section update requires --section")
        updated = replace_section(original, args.section, replacement)

    atomic_write(args.path, updated)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
