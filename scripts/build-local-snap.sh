#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

SKIP_WEBCLIENT=false
[[ "${1:-}" == "--skip-webclient" ]] && SKIP_WEBCLIENT=true

echo "=========================================="
echo "Proton Drive Snap Build"
echo "=========================================="

if ! command -v snapcraft &> /dev/null; then
    echo "snapcraft not installed. Install with: sudo snap install snapcraft --classic"
    exit 1
fi

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

export DISTRO_TYPE=snap
npm install
cd src-tauri && cargo build --release && cd ..
if [ ! -f "src-tauri/target/release/proton-drive" ]; then
    echo "Binary not found!"
    exit 1
fi

mkdir -p snap
cat > snap/snapcraft.yaml << EOF
name: proton-drive
version: "${VERSION}"
summary: Proton Drive Linux Desktop Client
description: |
  Fast, lightweight, and unofficial desktop GUI client for Proton Drive on Linux.
  Built with Tauri and Rust for a native-performance experience.
grade: stable
confinement: strict
base: core24
platforms:
  amd64:

apps:
  proton-drive:
    command: usr/bin/proton-drive-wrapper
    environment:
      WEBKIT_DISABLE_DMABUF_RENDERER: "1"
      WEBKIT_DISABLE_COMPOSITING_MODE: "1"
      GDK_GL: software
    desktop: usr/share/applications/com.proton.drive.desktop
    plugs:
    - home
    - network
    - network-bind
    - network-status
    - desktop
    - desktop-legacy
    - x11
    - wayland
    - opengl
    - audio-playback
    - browser-support
    - password-manager-service
    - dbus

plugs:
  dbus:
    interface: dbus
    bus: session
    name: com.proton.drive

parts:
  proton-drive:
    plugin: nil
    source: .
    override-build: |
      install -Dm755 src-tauri/target/release/proton-drive "\$SNAPCRAFT_PART_INSTALL/usr/bin/proton-drive"
      mkdir -p "\$SNAPCRAFT_PART_INSTALL/usr/bin"
      cat > "\$SNAPCRAFT_PART_INSTALL/usr/bin/proton-drive-wrapper" << 'WRAPPEREOF'
#!/bin/bash
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export GDK_GL=software
exec "\$SNAP/usr/bin/proton-drive" "\$@"
WRAPPEREOF
      chmod +x "\$SNAPCRAFT_PART_INSTALL/usr/bin/proton-drive-wrapper"
      mkdir -p "\$SNAPCRAFT_PART_INSTALL/usr/share/applications"
      cat > "\$SNAPCRAFT_PART_INSTALL/usr/share/applications/com.proton.drive.desktop" << 'DESKTOPEOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Proton Drive
Comment=Secure cloud storage
Exec=proton-drive-wrapper
Icon=com.proton.drive
Categories=Utility;
DESKTOPEOF
      mkdir -p "\$SNAPCRAFT_PART_INSTALL/usr/share/icons/hicolor/32x32/apps"
      mkdir -p "\$SNAPCRAFT_PART_INSTALL/usr/share/icons/hicolor/128x128/apps"
      mkdir -p "\$SNAPCRAFT_PART_INSTALL/usr/share/icons/hicolor/scalable/apps"
      cp src-tauri/icons/32x32.png "\$SNAPCRAFT_PART_INSTALL/usr/share/icons/hicolor/32x32/apps/com.proton.drive.png"
      cp src-tauri/icons/128x128.png "\$SNAPCRAFT_PART_INSTALL/usr/share/icons/hicolor/128x128/apps/com.proton.drive.png"
      cp src-tauri/icons/proton-drive.svg "\$SNAPCRAFT_PART_INSTALL/usr/share/icons/hicolor/scalable/apps/com.proton.drive.svg"
    stage-packages:
    - libssl3
    - libwebkit2gtk-4.1-0
    - libgtk-3-0
    - libayatana-appindicator3-1
    - librsvg2-2
    - libsoup-3.0-0
EOF

snapcraft --destructive-mode

echo ""
echo "=========================================="
echo "Snap Build Complete!"
echo "=========================================="
ls -la *.snap
echo "Install: sudo snap install --dangerous proton-drive_*.snap"
