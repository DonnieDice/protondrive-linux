#!/usr/bin/env python3
"""Aggregate per-VM result records from all three pipeline stages into a deployment matrix.

Each stage emits one JSON file per distro under its results directory:
  transfer-results/<label>.json  — artifact found, VM reachable, SCP transfer
  install-results/<label>.json   — package manager install outcome
  test-results/<label>.json      — regression + GUI load test pass/fail

Records are merged by distro label into a single row per VM, producing:
  --md   deployment-matrix.md    human-readable matrix
  --junit verify-junit.xml       JUnit XML rendered in the GitLab MR widget
  --json deployment-matrix.json  machine-readable combined record

Exit code is non-zero if any VM's overall status is FAIL.

Usage:
  verify-matrix.py RESULTS_DIR [RESULTS_DIR ...] [--md FILE] [--junit FILE] [--json FILE]
"""
import argparse
import glob
import json
import os
import sys
import xml.sax.saxutils as xml


def load_all(dirs):
    """Load and merge per-stage result records by distro label."""
    by_distro = {}
    for d in dirs:
        if not os.path.isdir(d):
            print(f"warning: results dir not found: {d}", file=sys.stderr)
            continue
        for path in sorted(glob.glob(os.path.join(d, "*.json"))):
            try:
                r = json.load(open(path))
                label = r.get("distro", "?")
                if label not in by_distro:
                    by_distro[label] = {}
                by_distro[label].update(r)
            except Exception as e:  # noqa: BLE001
                print(f"warning: skipping {path}: {e}", file=sys.stderr)
    return sorted(by_distro.values(), key=lambda r: r.get("distro", ""))


def mark(v):
    return {"pass": "✅", "fail": "❌"}.get(str(v).lower() if v else "", v or "—")


def overall_status(r):
    """Derive overall PASS/FAIL from the merged record (any stage FAIL = overall FAIL)."""
    stages = [r.get("status")]
    for key in ("artifact_found", "reachable", "transferred", "installed"):
        if key in r and r[key] == "fail":
            return "FAIL"
    if r.get("tests_failed", 0):
        return "FAIL"
    return "PASS" if all(s == "PASS" for s in stages if s) else "FAIL"


def to_markdown(rows):
    out = ["# Proton Drive — VM Deployment / Verification Matrix", ""]
    if rows:
        out.append(f"_pipeline {rows[0].get('ci_pipeline','?')} · commit "
                   f"{rows[0].get('ci_commit','?')} · {rows[0].get('timestamp','')}_\n")
    out += [
        "| Distro | VM | Version | sha256 | Transfer | Install | Tests | Status |",
        "|---|---|---|---|:--:|:--:|:--:|:--:|",
    ]
    for r in rows:
        st = overall_status(r)
        xfer = mark("pass" if r.get("transferred") == "pass" else "fail") \
            if "transferred" in r else "—"
        tests_run = r.get("tests_run", "")
        tests_fail = r.get("tests_failed", "")
        tests_cell = (f"✅ {tests_run - tests_fail}/{tests_run}"
                      if tests_run and not tests_fail
                      else f"❌ {tests_run - tests_fail}/{tests_run}"
                      if tests_run else "—")
        out.append("| {d} | {ip} | {v} | `{sha}` | {xfer} | {ins} | {tests} | {st} |".format(
            d=r.get("distro", "?"), ip=r.get("vm_ip", "?"),
            v=r.get("version") or "—", sha=(r.get("sha256") or "")[:12] or "—",
            xfer=xfer,
            ins=mark(r.get("installed")),
            tests=tests_cell,
            st="✅ PASS" if st == "PASS" else "❌ FAIL"))
    passed = sum(1 for r in rows if overall_status(r) == "PASS")
    out += ["", f"**{passed}/{len(rows)} VMs verified.**"]
    return "\n".join(out) + "\n"


def to_junit(rows):
    fails = sum(1 for r in rows if overall_status(r) != "PASS")
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             f'<testsuite name="vm-deployment-verify" tests="{len(rows)}" failures="{fails}">']
    for r in rows:
        name = xml.quoteattr(f"verify {r.get('distro','?')} ({r.get('vm_ip','?')})")
        cls = xml.quoteattr("deployment.verify")
        lines.append(f'  <testcase classname={cls} name={name}>')
        if overall_status(r) != "PASS":
            steps = ", ".join(
                f"{k}={r.get(k)}" for k in
                ("artifact_found", "reachable", "transferred", "installed", "tests_failed")
                if k in r
            )
            lines.append(f'    <failure message={xml.quoteattr("verify failed: " + steps)}/>')
        lines.append("  </testcase>")
    lines.append("</testsuite>")
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("results_dirs", nargs="+",
                    help="One or more stage result directories (transfer-results/, install-results/, test-results/)")
    ap.add_argument("--md")
    ap.add_argument("--junit")
    ap.add_argument("--json")
    a = ap.parse_args()
    rows = load_all(a.results_dirs)
    if not rows:
        # No results yet (builds canceled or vmtest skipped) — write empty artifacts and exit 0
        # so the report job doesn't fail the pipeline when upstream was canceled.
        msg = "No VM result data yet (builds/vmtest may have been canceled or skipped)."
        print(f"WARNING: {msg}", file=sys.stderr)
        if a.md:
            open(a.md, "w").write(f"# Proton Drive VM Deployment Matrix\n\n_{msg}_\n")
        if a.junit:
            open(a.junit, "w").write(
                '<?xml version="1.0" encoding="UTF-8"?>'
                f'<testsuite name="vm-deployment-verify" tests="0" failures="0">'
                f'<properties><property name="note" value="{msg}"/></properties>'
                '</testsuite>\n')
        if a.json:
            json.dump([], open(a.json, "w"), indent=2)
        return 0
    if a.md:
        open(a.md, "w").write(to_markdown(rows))
    if a.junit:
        open(a.junit, "w").write(to_junit(rows))
    if a.json:
        json.dump(rows, open(a.json, "w"), indent=2)
    print(to_markdown(rows))
    return 0 if all(overall_status(r) == "PASS" for r in rows) else 1


if __name__ == "__main__":
    sys.exit(main())
