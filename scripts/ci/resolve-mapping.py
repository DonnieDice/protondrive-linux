#!/usr/bin/env python3
"""Resolve changed repository paths to documentation audit targets."""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import sys
from pathlib import PurePosixPath

import yaml


def norm_path(path: str) -> str:
    return str(PurePosixPath(path.replace("\\", "/"))).lstrip("./")


def path_matches(entry: dict, changed_path: str) -> bool:
    if "source" in entry:
        return norm_path(entry["source"]) == changed_path
    if "glob" in entry:
        return fnmatch.fnmatch(changed_path, norm_path(entry["glob"]))
    return False


def clean_doc_target(target: dict) -> dict:
    allowed = ("path", "section", "critical", "update_mode", "rustdoc")
    cleaned = {key: target[key] for key in allowed if key in target}
    cleaned.setdefault("critical", False)
    cleaned.setdefault("update_mode", "section")
    return cleaned


def resolve(mapping: dict, changed_files: list[str]) -> dict[str, list[dict]]:
    result: dict[str, list[dict]] = {}
    entries = mapping.get("mapping", [])

    for changed_path in changed_files:
        targets: list[dict] = []
        for entry in entries:
            if not path_matches(entry, changed_path):
                continue

            if entry.get("self_update"):
                targets.append(
                    {
                        "path": changed_path,
                        "section": None,
                        "critical": False,
                        "update_mode": "file",
                    }
                )

            for target in entry.get("docs", []) or []:
                targets.append(clean_doc_target(target))

        if targets:
            deduped: list[dict] = []
            seen: set[tuple] = set()
            for target in targets:
                key = (
                    target.get("path"),
                    target.get("section"),
                    target.get("critical", False),
                    target.get("update_mode", "section"),
                )
                if key in seen:
                    continue
                seen.add(key)
                deduped.append(target)
            result[changed_path] = deduped

    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mapping", required=True)
    parser.add_argument("--changed", required=True)
    args = parser.parse_args()

    with open(args.mapping, "r", encoding="utf-8") as f:
        mapping = yaml.safe_load(f) or {}

    with open(args.changed, "r", encoding="utf-8") as f:
        changed_files = [norm_path(line.strip()) for line in f if line.strip()]

    resolved = resolve(mapping, changed_files)
    os.makedirs("docs", exist_ok=True)
    json.dump(resolved, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
