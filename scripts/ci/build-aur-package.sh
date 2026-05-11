#!/usr/bin/env bash
set -euo pipefail

AUR_TARGET="${1:-arch}"
VERSION="${2:-1.2.0}"
BINARY_PATH="${3:-src-tauri/target/release/proton-drive}"
WRAPPER_PATH="${4:-aur/proton-drive.wrapper}"
ICONS_DIR="${5:-src-tauri/icons}"
REPO_ROOT="${6:-.}"
OUTPUT_DIR="/tmp/aur-output"

mkdir -p "$OUTPUT_DIR"
chmod 777 "$OUTPUT_DIR"

WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

SRC_DIR="${WORK_DIR}/src"
mkdir -p "$SRC_DIR"
cp "$BINARY_PATH" "${SRC_DIR}/proton-drive"
chmod 755 "${SRC_DIR}/proton-drive"
cp "$WRAPPER_PATH" "${SRC_DIR}/proton-drive.wrapper"
chmod 755 "${SRC_DIR}/proton-drive.wrapper"

cat > "${SRC_DIR}/com.proton.drive.desktop" <<DESKTOP
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

if [ -d "$ICONS_DIR" ]; then
  for size in 32x32 128x128 256x256; do
    case "$size" in
      32x32) ICON_FILE="${ICONS_DIR}/32x32.png" ;;
      128x128) ICON_FILE="${ICONS_DIR}/128x128.png" ;;
      256x256) ICON_FILE="${ICONS_DIR}/128x128@2x.png" ;;
    esac
    if [ -f "$ICON_FILE" ]; then
      cp "$ICON_FILE" "${SRC_DIR}/icon-${size}.png"
    fi
  done
  if [ -f "${ICONS_DIR}/proton-drive.svg" ]; then
    cp "${ICONS_DIR}/proton-drive.svg" "${SRC_DIR}/proton-drive.svg"
  fi
fi

cat > "${WORK_DIR}/PKGBUILD" <<PKGBUILD
pkgname=proton-drive-bin
pkgver=${VERSION}
pkgrel=1
pkgdesc="Unofficial Linux desktop client for Proton Drive, built with Tauri"
arch=('x86_64')
url="https://github.com/DonnieDice/protondrive-linux"
license=('AGPL-3.0-only')
depends=('webkit2gtk-4.1' 'gtk3' 'libayatana-appindicator')
provides=('proton-drive')
conflicts=('proton-drive')
options=('!strip')
source=("proton-drive" "proton-drive.wrapper" "com.proton.drive.desktop")
sha256sums=('SKIP' 'SKIP' 'SKIP')

package() {
  install -dm755 "\${pkgdir}/usr/lib/proton-drive"
  install -Dm755 "\${srcdir}/proton-drive" "\${pkgdir}/usr/lib/proton-drive/proton-drive.bin"
  install -Dm755 "\${srcdir}/proton-drive.wrapper" "\${pkgdir}/usr/bin/proton-drive"
  install -Dm644 "\${srcdir}/com.proton.drive.desktop" "\${pkgdir}/usr/share/applications/com.proton.drive.desktop"

  for size in 32x32 128x128 256x256; do
    if [ -f "\${srcdir}/icon-\${size}.png" ]; then
      install -Dm644 "\${srcdir}/icon-\${size}.png" "\${pkgdir}/usr/share/icons/hicolor/\${size}/apps/com.proton.drive.png"
    fi
  done

  if [ -f "\${srcdir}/proton-drive.svg" ]; then
    install -Dm644 "\${srcdir}/proton-drive.svg" "\${pkgdir}/usr/share/icons/hicolor/scalable/apps/com.proton.drive.svg"
  fi
}
PKGBUILD

BUILD_DIR="${WORK_DIR}/build"
mkdir -p "$BUILD_DIR"

ln -sf "${SRC_DIR}/proton-drive" "${BUILD_DIR}/proton-drive"
ln -sf "${SRC_DIR}/proton-drive.wrapper" "${BUILD_DIR}/proton-drive.wrapper"
ln -sf "${SRC_DIR}/com.proton.drive.desktop" "${BUILD_DIR}/com.proton.drive.desktop"

if [ -f "${SRC_DIR}/icon-32x32.png" ]; then ln -sf "${SRC_DIR}/icon-32x32.png" "${BUILD_DIR}/icon-32x32.png"; fi
if [ -f "${SRC_DIR}/icon-128x128.png" ]; then ln -sf "${SRC_DIR}/icon-128x128.png" "${BUILD_DIR}/icon-128x128.png"; fi
if [ -f "${SRC_DIR}/icon-256x256.png" ]; then ln -sf "${SRC_DIR}/icon-256x256.png" "${BUILD_DIR}/icon-256x256.png"; fi
if [ -f "${SRC_DIR}/proton-drive.svg" ]; then ln -sf "${SRC_DIR}/proton-drive.svg" "${BUILD_DIR}/proton-drive.svg"; fi

cp "${WORK_DIR}/PKGBUILD" "${BUILD_DIR}/PKGBUILD"

useradd -m builder 2>/dev/null || true
chown -R builder:builder "$WORK_DIR"

cd "$BUILD_DIR"

BUILDDIR="${WORK_DIR}/makepkg-builddir" \
  PKGDEST="$OUTPUT_DIR" \
  SRCDEST="${WORK_DIR}/makepkg-srcdest" \
  SRCPKGDEST="${WORK_DIR}/makepkg-srcpkgdest" \
  su builder -c "makepkg --nodeps --skipinteg --noconfirm -f"

PKG_FILE=$(ls "${OUTPUT_DIR}"/*.pkg.tar.zst 2>/dev/null | head -1)
if [ -n "$PKG_FILE" ]; then
  echo "Built: ${PKG_FILE}"
  ls -la "${PKG_FILE}"
else
  echo "ERROR: No .pkg.tar.zst found in ${OUTPUT_DIR}"
  exit 1
fi
