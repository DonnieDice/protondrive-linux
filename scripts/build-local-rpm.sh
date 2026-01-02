#!/bin/bash
# Local RPM build script
# Usage: ./scripts/build-local-rpm.sh [--skip-webclient]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

SKIP_WEBCLIENT=false
[[ "${1:-}" == "--skip-webclient" ]] && SKIP_WEBCLIENT=true

echo "=========================================="
echo "Proton Drive RPM Build"
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

# Apply package-specific patches
PATCHES_DIR="$PROJECT_ROOT/patches/rpm"
if [ -d "$PATCHES_DIR" ] && ls "$PATCHES_DIR"/*.patch 1>/dev/null 2>&1; then
    echo "Applying RPM-specific patches..."
    for patch in "$PATCHES_DIR"/*.patch; do
        echo "  Applying $(basename "$patch")..."
        git apply "$patch" || echo "  Already applied or failed"
    done
fi

# Install deps and build
npm install
npx tauri build --bundles rpm --verbose

echo ""
echo "=========================================="
echo "RPM Build Complete!"
echo "=========================================="
find src-tauri/target/release/bundle -name "*.rpm" -exec ls -lh {} \;
