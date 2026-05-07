#!/bin/bash
# Local DEB build script
# Usage: ./scripts/build-local-deb.sh [--skip-webclient]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

SKIP_WEBCLIENT=false
[[ "${1:-}" == "--skip-webclient" ]] && SKIP_WEBCLIENT=true

echo "=========================================="
echo "Proton Drive DEB Build"
echo "=========================================="

# Build WebClients if needed
if [ "$SKIP_WEBCLIENT" = false ]; then
    "$SCRIPT_DIR/build-webclients.sh"
else
    echo "Skipping WebClients build (--skip-webclient)"
    if [ ! -d "WebClients/applications/drive/dist" ]; then
        echo "ERROR: WebClients dist not found! Run without --skip-webclient first."
        exit 1
    fi
fi

# Sync version
VERSION=$(node -p "require('./package.json').version")
echo "Building version: $VERSION"
sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$VERSION\"/" src-tauri/tauri.conf.json
sed -i "0,/^version = \"[^\"]*\"/s//version = \"$VERSION\"/" src-tauri/Cargo.toml

# Detect distro for package-specific patch selection
detect_distro_id() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "${ID}"
    else
        echo "unknown"
    fi
}
DISTRO_ID=$(detect_distro_id)
echo "Detected distro: $DISTRO_ID"

# Apply package-specific distro patch (named <distro>.patch)
DISTRO_PATCH="$PROJECT_ROOT/patches/deb/${DISTRO_ID}.patch"
if [ -f "$DISTRO_PATCH" ]; then
    echo "Applying DEB/${DISTRO_ID} distro patch..."
    git apply "$DISTRO_PATCH" || echo " Already applied or failed"
else
    echo "No DEB/${DISTRO_ID}.patch found — building with base code only"
fi

# Install deps and build with DISTRO_TYPE env
export DISTRO_TYPE=deb
npm install
npx tauri build --bundles deb --verbose

echo ""
echo "=========================================="
echo "DEB Build Complete!"
echo "=========================================="
find src-tauri/target/release/bundle -name "*.deb" -exec ls -lh {} \;
