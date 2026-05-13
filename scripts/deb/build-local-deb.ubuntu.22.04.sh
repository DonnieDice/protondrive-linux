#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
cd "$PROJECT_ROOT"

SKIP_WEBCLIENT=false
[[ "${1:-}" == "--skip-webclient" ]] && SKIP_WEBCLIENT=true

echo "=========================================="
echo "Proton Drive DEB Build — Ubuntu 22.04"
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

PATCH_FILE="patches/deb/ubuntu.22.04.patch"
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

echo ""
echo "=========================================="
echo "Bundling webkit2gtk-4.1 libs for Ubuntu 22.04"
echo "=========================================="

cd "$DEB_DIR"
rm -rf rebuild
mkdir -p rebuild && cd rebuild
dpkg-deb -R "../$(basename "$ORIG_DEB")" .

BUNDLED_DIR="usr/lib/proton-drive"
mkdir -p "$BUNDLED_DIR"

for lib in \
    /usr/lib/x86_64-linux-gnu/libwebkit2gtk-4.1.so.0 \
    /usr/lib/x86_64-linux-gnu/libwebkit2gtk-4.1.so.0.*.*.* \
    /usr/lib/x86_64-linux-gnu/libjavascriptcoregtk-4.1.so.0 \
    /usr/lib/x86_64-linux-gnu/libjavascriptcoregtk-4.1.so.0.*.*.* \
    /usr/lib/x86_64-linux-gnu/libsoup-3.0.so.0 \
    /usr/lib/x86_64-linux-gnu/libsoup-3.0.so.0.*.*.* \
    /usr/lib/x86_64-linux-gnu/libwebp.so.7 \
    /usr/lib/x86_64-linux-gnu/libenchant-2.so.2 \
    /usr/lib/x86_64-linux-gnu/libmanette-0.2.so.0 \
    /usr/lib/x86_64-linux-gnu/libWPEBackend-fdo-1.0.so.1 \
    /usr/lib/x86_64-linux-gnu/libwpe-1.0.so.1; do
    for f in $lib; do
        if [ -f "$f" ]; then
            cp -L "$f" "$BUNDLED_DIR/"
            echo "  Bundled: $(basename "$f")"
        fi
    done
done

for proc in WebKitNetworkProcess WebKitWebProcess WebKitGPUProcess; do
    if [ -f "/usr/lib/x86_64-linux-gnu/webkit2gtk-4.1/$proc" ]; then
        cp -L "/usr/lib/x86_64-linux-gnu/webkit2gtk-4.1/$proc" "$BUNDLED_DIR/"
        echo "  Bundled: $proc"
    fi
done

mv usr/bin/proton-drive usr/bin/proton-drive-bin
cat > usr/bin/proton-drive << 'WRAPPER'
#!/bin/bash
export LD_LIBRARY_PATH="/usr/lib/proton-drive${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export WEBKIT_EXEC_PATH="/usr/lib/proton-drive/WebKitWebProcess"
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
export GDK_GL=disable
export LIBGL_ALWAYS_SOFTWARE=1
export GSK_RENDERER=cairo
exec /usr/bin/proton-drive-bin "$@"
WRAPPER
chmod +x usr/bin/proton-drive

sed -i 's/libwebkit2gtk-4.1-0/libwebkit2gtk-4.0-37/g' DEBIAN/control

NEW_DEB="proton-drive_${VERSION}_ubuntu2204_bundled_amd64.deb"
dpkg-deb -b . "../$NEW_DEB"
cd ..
rm -rf rebuild

echo ""
echo "=========================================="
echo "Ubuntu 22.04 DEB Build Complete!"
echo "=========================================="
ls -lh "$PROJECT_ROOT/$DEB_DIR"/*.deb
