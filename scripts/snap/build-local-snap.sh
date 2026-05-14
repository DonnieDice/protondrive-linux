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

SNAPCRAFT_ARGS=(pack --destructive-mode)

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

BUILD_CONTEXT="$(mktemp -d "$PROJECT_ROOT/.snap-build.XXXXXX")"
cleanup_build_context() {
    rm -rf "$BUILD_CONTEXT"
}
trap 'cleanup_patch; cleanup_build_context' EXIT

mkdir -p "$BUILD_CONTEXT/packaging/snap"
mkdir -p "$BUILD_CONTEXT/src-tauri/target/release"
mkdir -p "$BUILD_CONTEXT/src-tauri/icons"
cp packaging/snap/proton-drive-wrapper.sh "$BUILD_CONTEXT/packaging/snap/"
cp packaging/snap/com.proton.drive.desktop "$BUILD_CONTEXT/packaging/snap/"
cp src-tauri/target/release/proton-drive "$BUILD_CONTEXT/src-tauri/target/release/"
cp src-tauri/icons/32x32.png "$BUILD_CONTEXT/src-tauri/icons/"
cp src-tauri/icons/128x128.png "$BUILD_CONTEXT/src-tauri/icons/"
cp src-tauri/icons/proton-drive.svg "$BUILD_CONTEXT/src-tauri/icons/"
sed "s/PLACEHOLDER/$VERSION/" packaging/snap/snapcraft.yaml > "$BUILD_CONTEXT/snapcraft.yaml"
if [ "$SNAP_TARGET" = "core26" ]; then
    sed -i \
        -e "s/base: core24/base: core26/" \
        -e "s/grade: stable/grade: devel/" \
        -e "/^base: core26/a\\build-base: devel" \
        "$BUILD_CONTEXT/snapcraft.yaml"
elif [ "$SNAP_TARGET" != "core24" ]; then
    echo "ERROR: Unsupported snap target: $SNAP_TARGET"
    exit 1
fi

if [ "$SNAP_TARGET" = "core26" ]; then
    if ! snap list core26 >/dev/null 2>&1; then
        echo "core26 base snap is not installed; install it with: sudo snap install core26 --channel=latest/stable"
    fi
elif [ "$SNAP_TARGET" != "core24" ]; then
    echo "ERROR: Unsupported snap target: $SNAP_TARGET"
    exit 1
fi

SNAPCRAFT_STATUS=0
(
    cd "$BUILD_CONTEXT"
    snapcraft "${SNAPCRAFT_ARGS[@]}" --output "$PROJECT_ROOT"
) || SNAPCRAFT_STATUS=$?

if [ "$SNAPCRAFT_STATUS" -ne 0 ] && [ "$SNAPCRAFT_STATUS" -ne 2 ]; then
    find "$HOME/.local/state/snapcraft/log" -maxdepth 1 -type f -name 'snapcraft-*.log' -print -exec tail -n 200 {} \; || true
    exit "$SNAPCRAFT_STATUS"
fi
SNAP_FILE="$(find "$PROJECT_ROOT" "$BUILD_CONTEXT" -maxdepth 1 -type f \( -name '*.snap' -o -name 'protondrive-linux-repo' \) | head -1)"
if [ -z "$SNAP_FILE" ]; then
    echo "ERROR: Snap package was not produced"
    exit 1
fi
mv "$SNAP_FILE" "$PROJECT_ROOT/proton-drive_${VERSION}_${SNAP_TARGET}_amd64.snap"

echo ""
echo "=========================================="
echo "Snap Build Complete!"
echo "=========================================="
find . -maxdepth 1 -name "proton-drive_*_${SNAP_TARGET}_amd64.snap" -exec ls -lh {} \;
echo "Install: sudo snap install --dangerous proton-drive_${VERSION}_${SNAP_TARGET}_amd64.snap"
