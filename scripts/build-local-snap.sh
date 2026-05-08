#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/snap/build-local-snap.sh" "$@"
    - libgtk-3-0
    - libayatana-appindicator3-1
    - librsvg2-2
    - libsoup-3.0-0
EOF

snapcraft --destructive-mode

echo ""
echo "=========================================="
echo "Snap Build Complete!"
echo "=========================================="
ls -la *.snap
echo "Install: sudo snap install --dangerous proton-drive_*.snap"
