#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

SKIP_WEBCLIENT=false
[[ "${1:-}" == "--skip-webclient" ]] && SKIP_WEBCLIENT=true

echo "=========================================="
echo "Proton Drive DEB Build"
echo "=========================================="

if [ "$SKIP_WEBCLIENT" = false ]; then
    "$SCRIPT_DIR/build-webclients.sh"
else
    echo "Skipping WebClients build (--skip-webclient)"
    if [ ! -d "WebClients/applications/drive/dist" ]; then
        echo "ERROR: WebClients dist not found! Run without --skip-webclient first."
        exit 1
    fi
fi

VERSION=$(node -p "require('./package.json').version")
echo "Building version: $VERSION"
sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$VERSION\"/" src-tauri/tauri.conf.json
sed -i "0,/^version = \"[^\"]*\"/s//version = \"$VERSION\"/" src-tauri/Cargo.toml

export DISTRO_TYPE=deb
npm install
npx tauri build --bundles deb --verbose

echo ""
echo "=========================================="
echo "DEB Build Complete!"
echo "=========================================="
find src-tauri/target/release/bundle -name "*.deb" -exec ls -lh {} \;
