#!/usr/bin/env python3
"""Build an HTML screenshot gallery from compositor test PNG files.

Usage: generate-screenshot-gallery.py <screenshots_src_dir> <output_dir>
"""
import datetime, glob, os, shutil, sys

src_dir    = sys.argv[1] if len(sys.argv) > 1 else "verify-results/ui-screenshots"
output_dir = sys.argv[2] if len(sys.argv) > 2 else "reports/screenshots"
os.makedirs(output_dir, exist_ok=True)

shots = sorted(glob.glob(os.path.join(src_dir, "**", "*.png"), recursive=True))
pipeline = os.environ.get("CI_PIPELINE_ID", "?")
commit   = os.environ.get("CI_COMMIT_SHORT_SHA", "?")
ts       = datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")

cards = []
for src in shots:
    parts  = src.replace("\\", "/").split("/")
    distro = parts[2] if len(parts) > 2 else "unknown"
    label  = os.path.basename(src).replace(".png", "")
    dst    = os.path.join(output_dir, f"{distro}_{label}.png")
    shutil.copy2(src, dst)
    cls = "fail" if "FAIL" in label.upper() else "pass"
    cards.append(
        f"<div class='card {cls}'>"
        f"<img src='{distro}_{label}.png' alt='{label}'>"
        f"<p>{distro} / {label}</p></div>"
    )

html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8">
<title>UI Screenshots - Proton Drive CI</title>
<style>
  body{{font-family:sans-serif;background:#0d1117;color:#c9d1d9;padding:20px}}
  h1{{color:#58a6ff}} h2{{color:#8b949e;font-size:13px}}
  .grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:16px}}
  .card{{background:#161b22;border-radius:8px;padding:12px}}
  .card img{{width:100%;border-radius:4px}}
  .card p{{font-size:12px;margin:6px 0 0;color:#8b949e}}
  .pass{{border-left:3px solid #238636}} .fail{{border-left:3px solid #da3633}}
</style></head>
<body>
<h1>Proton Drive - UI Compositor Test Screenshots</h1>
<h2>Pipeline #{pipeline} | {commit} | {ts} | {len(shots)} screenshots</h2>
<p>Red border = FAIL screenshot (regression evidence). Green = PASS.</p>
<div class="grid">{"".join(cards) if cards else "<p>No screenshots captured yet.</p>"}</div>
</body></html>"""

open(os.path.join(output_dir, "index.html"), "w").write(html)
print(f"Gallery written: {len(shots)} screenshots -> {output_dir}/index.html")
