#!/usr/bin/env python3
"""Build a full-text search index of all project documentation.

Scans all .md files in the repo, extracts headings + text content,
and writes a search-index.json file usable for client-side search.
"""

import json
import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUTPUT = REPO / "docs" / "search-index.json"

# Files to skip (CI policy docs, etc. are included; skip binary/files that aren't docs)
SKIP_PATTERNS = [
    re.compile(r"/node_modules/"),
    re.compile(r"/target/"),
    re.compile(r"/\.git/"),
]

def should_skip(path):
    for pat in SKIP_PATTERNS:
        if pat.search(str(path)):
            return True
    return False


def extract_entries(filepath):
    """Parse a markdown file and return search entries."""
    rel = filepath.relative_to(REPO)
    text = filepath.read_text(encoding="utf-8", errors="replace")
    lines = text.split("\n")

    entries = []
    current_section = "(top)"
    content_buf = []
    content_start = 1

    def flush():
        if content_buf:
            body = " ".join(content_buf).strip()
            if len(body) > 15:
                entries.append({
                    "file": str(rel),
                    "section": current_section,
                    "snippet": body[:200],
                    "line": content_start,
                })

    for i, line in enumerate(lines):
        # Check for headings
        heading_match = re.match(r"^(#{1,6})\s+(.+)$", line)
        if heading_match:
            flush()
            current_section = heading_match.group(2).strip()
            content_buf = []
            content_start = i + 1
            continue

        # Skip code blocks and horizontal rules
        if line.strip().startswith("```"):
            flush()
            content_buf = []
            content_start = i + 1
            continue

        stripped = line.strip()
        if stripped and not stripped.startswith("---"):
            content_buf.append(stripped)

    flush()
    return entries


def build():
    md_files = sorted(REPO.rglob("*.md"))

    all_entries = []
    seen_files = set()

    for fpath in md_files:
        if should_skip(fpath):
            continue
        seen_files.add(str(fpath.relative_to(REPO)))
        entries = extract_entries(fpath)
        all_entries.extend(entries)

    # Build a flat text index for full-text search
    word_index = {}
    for entry in all_entries:
        words = re.findall(r"[a-zA-Z][a-zA-Z0-9_-]{2,}", entry["snippet"])
        words = set(w.lower() for w in words)
        for w in words:
            word_index.setdefault(w, []).append({
                "f": entry["file"],
                "s": entry["section"],
                "l": entry["line"],
            })

    index = {
        "generated_at":    __import__("datetime").datetime.now(__import__("datetime").timezone.utc).isoformat().replace("+00:00", "Z"),
        "total_files": len(seen_files),
        "total_entries": len(all_entries),
        "files": sorted(seen_files),
        "entries": all_entries,
        "word_index": word_index,
        "notes": {
            "rustdoc": "NOT_AVAILABLE — cargo not installed on this host. Rebuild index from a host with Rust toolchain to include rustdoc output.",
        }
    }

    OUTPUT.write_text(json.dumps(index, indent=2, ensure_ascii=False), encoding="utf-8")
    return index


if __name__ == "__main__":
    idx = build()
    print(f"Indexed {idx['total_files']} files → {idx['total_entries']} entries → {OUTPUT}")
    print(f"Word index: {len(idx['word_index'])} unique terms")
    print(f"Files indexed:")
    for f in idx["files"]:
        print(f"  {f}")
