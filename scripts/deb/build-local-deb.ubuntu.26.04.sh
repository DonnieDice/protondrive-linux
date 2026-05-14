#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
cd "$PROJECT_ROOT"

SKIP_WEBCLIENT=false
[[ "${1:-}" == "--skip-webclient" ]] && SKIP_WEBCLIENT=true

echo "=========================================="
echo "Proton Drive DEB Build — Ubuntu 26.04"
echo "=========================================="

if [ "$SKIP_WEBCLIENT" = false ]; then
    "$PROJECT_ROOT/scripts/build-webclients.sh"
else
    echo "Skipping WebClients build (--skip-webclient)"
    if [ ! -d "WebClients/applications/drive/dist" ]; then
        echo "ERROR: WebClients dist not found! Run without --skip-webclient first."
        exit 1
    fi
fi

PATCH_FILE="patches/deb/ubuntu.26.04.patch"
if [ ! -f "$PATCH_FILE" ]; then
    echo "ERROR: $PATCH_FILE not found!"
    exit 1
fi

PATCH_APPLIED=false
cleanup_patch() {
    if [ "$PATCH_APPLIED" = true ]; then
        git apply --reverse "$PATCH_FILE"
    fi
}
trap cleanup_patch EXIT

if git apply --reverse --check "$PATCH_FILE" 2>/dev/null; then
    echo "Patch already applied: $PATCH_FILE"
else
    git apply --check "$PATCH_FILE"
    git apply "$PATCH_FILE"
    PATCH_APPLIED=true
    echo "Applied $PATCH_FILE"
fi

VERSION=$(node -p "require('./package.json').version")
echo "Building version: $VERSION"
sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$VERSION\"/" src-tauri/tauri.conf.json
sed -i "0,/^version = \"[^\"]*\"/s//version = \"$VERSION\"/" src-tauri/Cargo.toml

export DISTRO_TYPE=deb
npm install
npx tauri build --bundles deb --verbose

DEB_DIR="src-tauri/target/release/bundle/deb"
ORIG_DEB="$(ls "$DEB_DIR"/*.deb 2>/dev/null | head -1)"
if [ -z "$ORIG_DEB" ]; then
    echo "ERROR: No DEB found!"
    exit 1
fi

target="proton-drive_${VERSION}_ubuntu26.04_amd64.deb"
if [ "$(basename "$ORIG_DEB")" != "$target" ]; then
    mv "$ORIG_DEB" "$DEB_DIR/$target"
fi

echo ""
echo "=========================================="
echo "Ubuntu 26.04 DEB Build Complete!"
echo "=========================================="
ls -lh "$DEB_DIR"/*.deb
