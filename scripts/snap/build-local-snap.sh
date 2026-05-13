#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
cd "$PROJECT_ROOT"

SNAP_TARGET="${1:-core24}"
SKIP_WEBCLIENT=false
if [[ "${1:-}" == "--skip-webclient" ]]; then
    SNAP_TARGET="core24"
    SKIP_WEBCLIENT=true
elif [[ "${2:-}" == "--skip-webclient" ]]; then
    SKIP_WEBCLIENT=true
fi

echo "=========================================="
echo "Proton Drive Snap Build"
echo "=========================================="
echo "Snap target: $SNAP_TARGET"

if ! command -v snapcraft &> /dev/null; then
    echo "snapcraft not installed. Install with: sudo snap install snapcraft --classic"
    exit 1
fi

if [ "$SKIP_WEBCLIENT" = false ]; then
    "$PROJECT_ROOT/scripts/build-webclients.sh"
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

PATCH_FILE="patches/snap/${SNAP_TARGET}.patch"
if [ ! -f "$PATCH_FILE" ]; then
    echo "ERROR: Missing snap patch: $PATCH_FILE"
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

export DISTRO_TYPE=snap
npm install
cd src-tauri && cargo build --release && cd ..
if [ ! -f "src-tauri/target/release/proton-drive" ]; then
    echo "Binary not found!"
    exit 1
fi

mkdir -p snap
sed "s/PLACEHOLDER/$VERSION/" packaging/snap/snapcraft.yaml > snap/snapcraft.yaml
if [ "$SNAP_TARGET" = "core26" ]; then
    sed -i \
        -e "s/base: core24/base: core26/" \
        -e "s/grade: stable/grade: devel/" \
        -e "/^base: core26/a\\build-base: core26" \
        snap/snapcraft.yaml
fi

snapcraft --destructive-mode
SNAP_FILE="$(ls proton-drive_*_amd64.snap 2>/dev/null | head -1)"
if [ -z "$SNAP_FILE" ]; then
    echo "ERROR: Snap package was not produced"
    exit 1
fi
mv "$SNAP_FILE" "proton-drive_${VERSION}_${SNAP_TARGET}_amd64.snap"

echo ""
echo "=========================================="
echo "Snap Build Complete!"
echo "=========================================="
find . -maxdepth 1 -name "proton-drive_*_${SNAP_TARGET}_amd64.snap" -exec ls -lh {} \;
echo "Install: sudo snap install --dangerous proton-drive_${VERSION}_${SNAP_TARGET}_amd64.snap"
