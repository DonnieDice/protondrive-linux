#!/usr/bin/env python3
"""Aggregate per-VM verify result records into a deployment tracking matrix.

Enterprise "remote tracking management": instead of a file share, the verify
stage records what version+sha of each package was deployed to which VM and the
outcome. This collects every verify-results/*.json (emitted by deploy_run) into:

  - a human-readable Markdown matrix   (--md   out.md)
  - a JUnit XML report                 (--junit out.xml)  -> rendered in the GitLab MR
  - a machine-readable combined JSON    (--json out.json)

Exit code is non-zero if any VM's status is FAIL (so the report job reflects it).

Usage:
  verify-matrix.py RESULTS_DIR [--md FILE] [--junit FILE] [--json FILE]
"""
import argparse
import glob
import json
import os
import sys
import xml.sax.saxutils as xml


def load(results_dir):
    rows = []
    for path in sorted(glob.glob(os.path.join(results_dir, "*.json"))):
        try:
            rows.append(json.load(open(path)))
        except Exception as e:  # noqa: BLE001
            print(f"warning: skipping {path}: {e}", file=sys.stderr)
    return rows


def mark(v):
    return {"pass": "✅", "fail": "❌"}.get(v, v or "—")


def to_markdown(rows):
    out = ["# Proton Drive — VM Deployment / Verification Matrix", ""]
    if rows:
        out.append(f"_pipeline {rows[0].get('ci_pipeline','?')} · commit "
                   f"{rows[0].get('ci_commit','?')} · {rows[0].get('timestamp','')}_\n")
    out += ["| Distro | VM | Version | sha256 | Found | Reachable | Installed | Smoke | Status |",
            "|---|---|---|---|:--:|:--:|:--:|:--:|:--:|"]
    for r in rows:
        out.append("| {distro} | {ip} | {ver} | `{sha}` | {a} | {re} | {ins} | {sm} | {st} |".format(
            distro=r.get("distro", "?"), ip=r.get("vm_ip", "?"),
            ver=r.get("version") or "—", sha=(r.get("sha256") or "")[:12] or "—",
            a=mark(r.get("artifact_found")), re=mark(r.get("reachable")),
            ins=mark(r.get("installed")), sm=mark(r.get("smoke")),
            st=("✅ PASS" if r.get("status") == "PASS" else "❌ FAIL")))
    passed = sum(1 for r in rows if r.get("status") == "PASS")
    out += ["", f"**{passed}/{len(rows)} VMs verified.**"]
    return "\n".join(out) + "\n"


def to_junit(rows):
    fails = sum(1 for r in rows if r.get("status") != "PASS")
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             f'<testsuite name="vm-deployment-verify" tests="{len(rows)}" failures="{fails}">']
    for r in rows:
        name = xml.quoteattr(f"verify {r.get('distro','?')} ({r.get('vm_ip','?')})")
        cls = xml.quoteattr("deployment.verify")
        lines.append(f'  <testcase classname={cls} name={name}>')
        if r.get("status") != "PASS":
            steps = ", ".join(f"{k}={r.get(k)}" for k in ("artifact_found", "reachable", "installed", "smoke"))
            lines.append(f'    <failure message={xml.quoteattr("verify failed: " + steps)}/>')
        lines.append("  </testcase>")
    lines.append("</testsuite>")
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("results_dir")
    ap.add_argument("--md")
    ap.add_argument("--junit")
    ap.add_argument("--json")
    a = ap.parse_args()
    rows = load(a.results_dir)
    if not rows:
        print("ERROR: no verify-results/*.json found", file=sys.stderr)
        return 2
    if a.md:
        open(a.md, "w").write(to_markdown(rows))
    if a.junit:
        open(a.junit, "w").write(to_junit(rows))
    if a.json:
        json.dump(rows, open(a.json, "w"), indent=2)
    print(to_markdown(rows))
    return 0 if all(r.get("status") == "PASS" for r in rows) else 1


if __name__ == "__main__":
    sys.exit(main())
