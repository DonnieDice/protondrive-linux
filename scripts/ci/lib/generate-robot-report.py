#!/usr/bin/env python3
"""Generate a Robot Framework HTML report from test-results/*.xml, or a placeholder.

Usage: generate-robot-report.py <results_dir> <output_dir>
"""
import glob, os, subprocess, sys

results_dir = sys.argv[1] if len(sys.argv) > 1 else "test-results"
output_dir  = sys.argv[2] if len(sys.argv) > 2 else "reports/robot"
os.makedirs(output_dir, exist_ok=True)

xmls = sorted(glob.glob(os.path.join(results_dir, "*.xml")))
if xmls:
    cmd = ["python3", "-m", "robot.rebot",
           "--outputdir", output_dir,
           "--output",  "output.xml",
           "--log",     "log.html",
           "--report",  "report.html",
           "--name",    "Proton Drive VM Tests"] + xmls
    result = subprocess.run(cmd, capture_output=True, text=True)
    print(result.stdout or result.stderr or "rebot complete")
    sys.exit(0 if result.returncode == 0 else 0)  # non-fatal

# Placeholder when no XML results exist yet
PLACEHOLDER = """<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>{title}</title>
<style>body{{font-family:sans-serif;background:#0d1117;color:#c9d1d9;padding:40px;max-width:800px;margin:auto}}
h1{{color:#58a6ff}} p{{color:#8b949e}}</style>
</head><body><h1>{title}</h1>
<p>{msg}</p>
<p>Add <code>PROTON_TEST_EMAIL</code> and <code>PROTON_TEST_PASSWORD</code>
CI variables to enable functional test execution on VMs.</p>
</body></html>"""

open(os.path.join(output_dir, "report.html"), "w").write(PLACEHOLDER.format(
    title="Robot Framework Report",
    msg="No output.xml from vmtest stage yet. Robot suites run on the VMs over SSH."
))
open(os.path.join(output_dir, "log.html"), "w").write(PLACEHOLDER.format(
    title="Robot Framework Log",
    msg="No test execution log yet."
))
print(f"Placeholder report written to {output_dir}/")
