#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
cd "$PROJECT_ROOT"

SKIP_WEBCLIENT=false
[[ "${1:-}" == "--skip-webclient" ]] && SKIP_WEBCLIENT=true

echo "=========================================="
echo "Proton Drive Flatpak Build — GNOME 49"
echo "=========================================="

if ! command -v flatpak-builder &> /dev/null; then
    echo "flatpak-builder not installed. Install with: sudo apt install flatpak-builder"
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

PATCH_FILE="patches/flatpak/org.gnome.Platform.49.patch"
if [ -f "$PATCH_FILE" ]; then
    git apply "$PATCH_FILE"
    echo "Applied $PATCH_FILE"
else
    echo "ERROR: $PATCH_FILE not found!"
    exit 1
fi

VERSION=$(node -p "require('./package.json').version")
echo "Building version: $VERSION"
sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$VERSION\"/" src-tauri/tauri.conf.json
sed -i "0,/^version = \"[^\"]*\"/s//version = \"$VERSION\"/" src-tauri/Cargo.toml

export DISTRO_TYPE=flatpak
npm install
cd src-tauri && cargo build --release && cd ..
if [ ! -f "src-tauri/target/release/proton-drive" ]; then
    echo "Binary not found!"
    exit 1
fi

flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user -y flathub org.gnome.Platform//49 org.gnome.Sdk//49 || true

cat > proton-drive-wrapper.sh << 'EOF'
#!/bin/bash
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
export GDK_GL=software
export GSK_RENDERER=cairo
exec /app/bin/proton-drive-bin "$@"
EOF
chmod +x proton-drive-wrapper.sh

cat > com.proton.drive.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Proton Drive
Comment=Secure cloud storage
Exec=proton-drive
Icon=com.proton.drive
Categories=Network;FileTransfer;
EOF

rm -rf flatpak-staging
mkdir -p flatpak-staging/icons
cp src-tauri/target/release/proton-drive flatpak-staging/proton-drive-bin
cp proton-drive-wrapper.sh flatpak-staging/proton-drive
cp src-tauri/icons/32x32.png flatpak-staging/icons/
cp src-tauri/icons/128x128.png flatpak-staging/icons/
cp src-tauri/icons/128x128@2x.png flatpak-staging/icons/
cp src-tauri/icons/proton-drive.svg flatpak-staging/icons/
cp com.proton.drive.desktop flatpak-staging/

cat > com.proton.drive.yml << EOF
app-id: com.proton.drive
runtime: org.gnome.Platform
runtime-version: '49'
sdk: org.gnome.Sdk
command: proton-drive
finish-args:
- --share=network
- --share=ipc
- --socket=x11
- --socket=wayland
- --socket=pulseaudio
- --device=dri
- --filesystem=home
- --filesystem=xdg-download
- --talk-name=org.freedesktop.secrets
- --talk-name=org.freedesktop.Notifications
- --system-talk-name=org.freedesktop.NetworkManager
modules:
- name: proton-drive
  buildsystem: simple
  sources:
  - type: dir
    path: flatpak-staging
  build-commands:
  - install -Dm755 proton-drive-bin /app/bin/proton-drive-bin
  - install -Dm755 proton-drive /app/bin/proton-drive
  - install -Dm644 icons/32x32.png /app/share/icons/hicolor/32x32/apps/com.proton.drive.png
  - install -Dm644 icons/128x128.png /app/share/icons/hicolor/128x128/apps/com.proton.drive.png
  - install -Dm644 icons/128x128@2x.png /app/share/icons/hicolor/256x256/apps/com.proton.drive.png
  - install -Dm644 icons/proton-drive.svg /app/share/icons/hicolor/scalable/apps/com.proton.drive.svg
  - install -Dm644 com.proton.drive.desktop /app/share/applications/com.proton.drive.desktop
EOF

rm -rf build-dir repo
flatpak-builder --user --force-clean --repo=repo build-dir com.proton.drive.yml
flatpak build-bundle repo "proton-drive_${VERSION}_gnome49.flatpak" com.proton.drive

echo ""
echo "=========================================="
echo "Flatpak GNOME 49 Build Complete!"
echo "=========================================="
echo "Output: proton-drive_${VERSION}_gnome49.flatpak"
echo "Install: flatpak install --user proton-drive_${VERSION}_gnome49.flatpak"
