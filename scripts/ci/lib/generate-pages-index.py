#!/usr/bin/env python3
"""Build the GitLab Pages index.html that links all CI reports.

Usage: generate-pages-index.py <matrix_json> <output_html>
"""
import datetime, json, os, sys

matrix_path  = sys.argv[1] if len(sys.argv) > 1 else "reports/deployment-matrix.json"
output_path  = sys.argv[2] if len(sys.argv) > 2 else "public/index.html"
os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)

try:
    matrix = json.load(open(matrix_path))
except Exception:
    matrix = []

passed  = sum(1 for r in matrix if r.get("status") == "PASS")
total   = len(matrix)
color   = "#238636" if passed == total and total > 0 else "#d29922" if passed > 0 else "#da3633"
badge   = f'<span style="color:{color};font-weight:bold">{passed}/{total} VMs passing</span>'
ts      = datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")
pipeline = os.environ.get("CI_PIPELINE_ID", "?")
commit   = os.environ.get("CI_COMMIT_SHORT_SHA", "?")

rows = ""
for r in matrix:
    st   = "pass" if r.get("status") == "PASS" else "fail"
    icon = "OK" if st == "pass" else "FAIL"
    rows += (f"<tr class='{st}'>"
             f"<td>{r.get('distro','?')}</td><td>{r.get('vm_ip','?')}</td>"
             f"<td>{r.get('version') or '-'}</td>"
             f"<td>{'OK' if r.get('transferred')=='pass' else '-'}</td>"
             f"<td>{'OK' if r.get('installed')=='pass' else '-'}</td>"
             f"<td>{r.get('tests_run','-')}</td>"
             f"<td><b>{icon}</b></td></tr>")

html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8">
<title>Proton Drive CI Reports</title>
<style>
  body{{font-family:sans-serif;background:#0d1117;color:#c9d1d9;max-width:1100px;margin:40px auto;padding:0 20px}}
  h1{{color:#58a6ff}} h2{{color:#8b949e;font-size:14px}}
  a{{color:#58a6ff;text-decoration:none}} a:hover{{text-decoration:underline}}
  .cards{{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:16px;margin:24px 0}}
  .card{{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:20px}}
  .card h3{{margin:0 0 6px;font-size:16px;color:#e6edf3}}
  .card p{{margin:0;font-size:13px;color:#8b949e}}
  table{{width:100%;border-collapse:collapse;margin-top:24px;font-size:13px}}
  th{{background:#161b22;padding:8px 12px;text-align:left;color:#8b949e;border-bottom:1px solid #30363d}}
  td{{padding:8px 12px;border-bottom:1px solid #21262d}}
  tr.pass td:last-child{{color:#238636}} tr.fail td:last-child{{color:#da3633}}
</style></head>
<body>
<h1>Proton Drive - CI Report Dashboard</h1>
<h2>Pipeline #{pipeline} | Commit {commit} | {ts}</h2>
<p style="font-size:18px">{badge}</p>
<div class="cards">
  <div class="card">
    <h3><a href="robot/report.html">Robot Framework</a></h3>
    <p>Acceptance tests: install, UI smoke, sidebar regression</p>
    <p><a href="robot/log.html">Detailed log</a></p>
  </div>
  <div class="card">
    <h3><a href="pytest/report.html">pytest Unit Tests</a></h3>
    <p>VM matrix validation, bash helper tests</p>
  </div>
  <div class="card">
    <h3><a href="screenshots/index.html">UI Screenshots</a></h3>
    <p>Compositor test evidence, FAIL screenshots highlighted</p>
  </div>
  <div class="card">
    <h3><a href="deployment-matrix.md">Deployment Matrix</a></h3>
    <p>Raw markdown + JSON. Also in MR Tests tab as JUnit.</p>
  </div>
</div>
<table>
  <tr><th>Distro</th><th>VM IP</th><th>Version</th><th>Transfer</th><th>Install</th><th>Tests</th><th>Status</th></tr>
  {rows if rows else "<tr><td colspan='7'>No results yet.</td></tr>"}
</table>
</body></html>"""

open(output_path, "w").write(html)
print(f"index.html written to {output_path} ({passed}/{total} passing)")
