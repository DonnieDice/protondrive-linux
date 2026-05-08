#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

SKIP_WEBCLIENT=false
[[ "${1:-}" == "--skip-webclient" ]] && SKIP_WEBCLIENT=true

echo "=========================================="
echo "Proton Drive AppImage Build"
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

export DISTRO_TYPE=appimage
npm install
cargo build --manifest-path src-tauri/Cargo.toml --release

VERSION="$VERSION" bash -s << 'APPRUN_BUILD'
set -euo pipefail
VERSION=$(node -p "require('./package.json').version")
BINARY_PATH="src-tauri/target/release/proton-drive"
APPDIR="AppDir"

mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/scalable/apps"
mkdir -p "$APPDIR/usr/share/icons/hicolor/128x128/apps"
mkdir -p "$APPDIR/usr/share/icons/hicolor/32x32/apps"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"

cp "$BINARY_PATH" "$APPDIR/usr/bin/proton-drive"
chmod +x "$APPDIR/usr/bin/proton-drive"

cat > "$APPDIR/usr/share/applications/com.proton.drive.desktop" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Proton Drive
Comment=Secure cloud storage
Exec=proton-drive %U
Icon=com.proton.drive
Categories=Utility;Network;FileTransfer;
Keywords=proton;drive;cloud;storage;sync;
Terminal=false
StartupWMClass=proton-drive
StartupNotify=true
EOF

cp src-tauri/icons/proton-drive.svg "$APPDIR/usr/share/icons/hicolor/scalable/apps/com.proton.drive.svg"
cp src-tauri/icons/128x128.png "$APPDIR/usr/share/icons/hicolor/128x128/apps/com.proton.drive.png"
cp src-tauri/icons/32x32.png "$APPDIR/usr/share/icons/hicolor/32x32/apps/com.proton.drive.png"
cp src-tauri/icons/128x128@2x.png "$APPDIR/usr/share/icons/hicolor/256x256/apps/com.proton.drive.png"
cp "$APPDIR/usr/share/applications/com.proton.drive.desktop" "$APPDIR/com.proton.drive.desktop"
cp src-tauri/icons/proton-drive.svg "$APPDIR/com.proton.drive.svg"
ln -sf usr/share/icons/hicolor/128x128/apps/com.proton.drive.png "$APPDIR/.DirIcon"

cat > "$APPDIR/AppRun" << 'APPRUN'
#!/bin/bash
WEBKIT_DISABLE_DMABUF_RENDERER=1
WEBKIT_DISABLE_COMPOSITING_MODE=1
WEBKIT_FORCE_SANDBOX=0
GSK_RENDERER=cairo

if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        ubuntu|pop|linuxmint)
            export GDK_GL=software
            ;;
        *)
            export GDK_GL=disable
            export LIBGL_ALWAYS_SOFTWARE=1
            ;;
    esac
else
    export GDK_GL=disable
    export LIBGL_ALWAYS_SOFTWARE=1
fi

export WEBKIT_DISABLE_DMABUF_RENDERER
export WEBKIT_DISABLE_COMPOSITING_MODE
export WEBKIT_FORCE_SANDBOX
export GSK_RENDERER

HERE="$(dirname "$(readlink -f "${0}")")"
export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"
exec "${HERE}/usr/bin/proton-drive" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

wget -q "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage" -O appimagetool
chmod +x appimagetool
./appimagetool --appimage-extract
ARCH=x86_64 ./squashfs-root/AppRun "$APPDIR" "proton-drive_${VERSION}_amd64.AppImage"

mkdir -p src-tauri/target/release/bundle/appimage
mv "proton-drive_${VERSION}_amd64.AppImage" src-tauri/target/release/bundle/appimage/
APPRUN_BUILD

echo ""
echo "=========================================="
echo "AppImage Build Complete!"
echo "=========================================="
find src-tauri/target/release/bundle -name "*.AppImage" -exec ls -lh {} \;
