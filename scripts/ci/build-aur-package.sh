#!/usr/bin/env bash
set -euo pipefail

AUR_TARGET="${1:-arch}"
VERSION="${2:-1.1.5}"
BINARY_PATH="${3:-src-tauri/target/release/proton-drive}"
WRAPPER_PATH="${4:-aur/proton-drive.wrapper}"
ICONS_DIR="${5:-src-tauri/icons}"
OUTPUT_DIR="/tmp/aur-output"

pkgdir_tmp=$(mktemp -d)

install -dm755 "${pkgdir_tmp}/usr/lib/proton-drive"
install -Dm755 "$BINARY_PATH" "${pkgdir_tmp}/usr/lib/proton-drive/proton-drive.bin"

install -Dm755 "$WRAPPER_PATH" "${pkgdir_tmp}/usr/bin/proton-drive"

DESKTOP_FILE="/tmp/com.proton.drive.desktop"
cat > "$DESKTOP_FILE" <<DESKTOP
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
DESKTOP
install -Dm644 "$DESKTOP_FILE" "${pkgdir_tmp}/usr/share/applications/com.proton.drive.desktop"

for size in 32x32 128x128 256x256; do
  case "$size" in
    32x32) ICON_FILE="${ICONS_DIR}/32x32.png" ;;
    128x128) ICON_FILE="${ICONS_DIR}/128x128.png" ;;
    256x256) ICON_FILE="${ICONS_DIR}/128x128@2x.png" ;;
  esac
  if [ -f "$ICON_FILE" ]; then
    install -Dm644 "$ICON_FILE" "${pkgdir_tmp}/usr/share/icons/hicolor/${size}/apps/com.proton.drive.png"
  fi
done

SVG_ICON="${ICONS_DIR}/proton-drive.svg"
if [ -f "$SVG_ICON" ]; then
  install -Dm644 "$SVG_ICON" "${pkgdir_tmp}/usr/share/icons/hicolor/scalable/apps/com.proton.drive.svg"
fi

PKG_NAME="proton-drive-bin"
PKG_FILE="${PKG_NAME}-${VERSION}-1-x86_64.pkg.tar.zst"

mkdir -p "$OUTPUT_DIR"
pushd "${pkgdir_tmp}"
ZSTD_CLEVEL=19 tar --zstd -cf "${OUTPUT_DIR}/${PKG_FILE}" *
popd

echo "Built: ${OUTPUT_DIR}/${PKG_FILE}"
