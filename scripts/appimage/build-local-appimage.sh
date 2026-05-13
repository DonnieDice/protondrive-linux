#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
cd "$PROJECT_ROOT"

SKIP_WEBCLIENT=false
APPIMAGE_TARGET="linux-baseline"

while [[ $# -gt 0 ]]; do
  case $1 in
    --appimage-target)
      APPIMAGE_TARGET="$2"
      shift 2
      ;;
    --skip-webclient)
      SKIP_WEBCLIENT=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--appimage-target <target>] [--skip-webclient]"
      echo "Default target: linux-baseline"
      exit 1
      ;;
  esac
done

echo "=========================================="
echo "Proton Drive AppImage Build"
echo "=========================================="
echo "AppImage target: ${APPIMAGE_TARGET}"

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

PATCH_FILE="patches/appimage/${APPIMAGE_TARGET}.patch"
if [ ! -f "$PATCH_FILE" ]; then
  echo "ERROR: Missing distro patch: $PATCH_FILE"
  exit 1
fi

if git apply --reverse --check "$PATCH_FILE" 2>/dev/null; then
  echo "Patch already applied: $PATCH_FILE"
else
  git apply --check "$PATCH_FILE"
  git apply "$PATCH_FILE"
  echo "Applied $PATCH_FILE"
fi

export DISTRO_TYPE=appimage
npm install
cargo build --manifest-path src-tauri/Cargo.toml --release

VERSION="$VERSION" APPIMAGE_TARGET="$APPIMAGE_TARGET" bash -s << 'APPRUN_BUILD'
set -euo pipefail
VERSION=$(node -p "require('./package.json').version")
APPIMAGE_TARGET="${APPIMAGE_TARGET}"
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
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
export GDK_GL=software
export GSK_RENDERER=cairo

HERE="$(dirname "$(readlink -f "${0}")")"
export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"
exec "${HERE}/usr/bin/proton-drive" "$@"
APPRUN

chmod +x "$APPDIR/AppRun"

wget -q "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage" -O appimagetool
chmod +x appimagetool
./appimagetool --appimage-extract
ARCH=x86_64 ./squashfs-root/AppRun "$APPDIR" "proton-drive_${VERSION}_${APPIMAGE_TARGET}_amd64.AppImage"

mkdir -p src-tauri/target/release/bundle/appimage
mv "proton-drive_${VERSION}_${APPIMAGE_TARGET}_amd64.AppImage" src-tauri/target/release/bundle/appimage/
APPRUN_BUILD

echo ""
echo "=========================================="
echo "AppImage Build Complete!"
echo "=========================================="
find src-tauri/target/release/bundle -name "*.AppImage" -exec ls -lh {} \;
