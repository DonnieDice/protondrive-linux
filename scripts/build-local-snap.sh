#!/bin/bash
# Local Snap build script - mirrors GitHub workflow
# Usage: ./scripts/build-snap.sh [--skip-webclient]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

SKIP_WEBCLIENT=false
[[ "${1:-}" == "--skip-webclient" ]] && SKIP_WEBCLIENT=true

echo "=========================================="
echo "📦 Proton Drive Snap Build"
echo "=========================================="

# Check dependencies
if ! command -v snapcraft &> /dev/null; then
    echo "❌ snapcraft not installed. Install with:"
    echo "   sudo snap install snapcraft --classic"
    exit 1
fi

# Step 1: Version sync
echo "📋 Step 1: Syncing version..."
VERSION=$(node -p "require('./package.json').version")
echo "Building version: $VERSION"
sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$VERSION\"/" src-tauri/tauri.conf.json
sed -i "0,/^version = \"[^\"]*\"/s//version = \"$VERSION\"/" src-tauri/Cargo.toml

# Step 2: Build WebClients (unless skipped)
if [ "$SKIP_WEBCLIENT" = false ]; then
    echo "📋 Step 2: Clone and build WebClients..."

    rm -rf WebClients 2>/dev/null || true
    git clone --depth=1 --single-branch --branch main \
        https://github.com/ProtonMail/WebClients.git WebClients

    python3 scripts/fix_deps.py
    : > WebClients/yarn.lock

    mv ./package.json ./package.json.bak 2>/dev/null || true
    mv ./yarn.lock ./yarn.lock.bak 2>/dev/null || true

    cd WebClients
    export NODE_OPTIONS="--max-old-space-size=8192"
    node .yarn/releases/yarn-4.12.0.cjs install --network-timeout 900000
    cd ..

    mv ./package.json.bak ./package.json 2>/dev/null || true
    mv ./yarn.lock.bak ./yarn.lock 2>/dev/null || true

    python3 scripts/create_stubs.py

    cd WebClients
    node .yarn/releases/yarn-4.12.0.cjs workspace proton-drive build:web
    node .yarn/releases/yarn-4.12.0.cjs workspace proton-account build:web || echo "Account build failed"
    node .yarn/releases/yarn-4.12.0.cjs workspace proton-verify build:web || echo "Verify build optional"

    # Copy and fix account app
    if [ -d "applications/account/dist" ]; then
        cp -r applications/account/dist applications/drive/dist/account
        find applications/drive/dist/account -name "*.html" -exec sed -i \
            -e 's|<base href="/">|<base href="/account/">|g' \
            -e 's|href="/assets/|href="/account/assets/|g' \
            -e 's|src="/assets/|src="/account/assets/|g' \
            -e 's|content="/assets/|content="/account/assets/|g' {} \;
        find applications/drive/dist/account -name "*.js" -exec sed -i \
            -e 's|"assets/static/|"/account/assets/static/|g' \
            -e 's|"/assets/static/|"/account/assets/static/|g' {} \;
        echo "✅ Account app copied and paths fixed"
    fi

    # Copy and fix verify app
    if [ -d "applications/verify/dist" ]; then
        cp -r applications/verify/dist applications/drive/dist/verify
        find applications/drive/dist/verify -name "*.html" -exec sed -i \
            -e 's|<base href="/">|<base href="/verify/">|g' \
            -e 's|href="/assets/|href="/verify/assets/|g' \
            -e 's|src="/assets/|src="/verify/assets/|g' \
            -e 's|content="/assets/|content="/verify/assets/|g' {} \;
        find applications/drive/dist/verify -name "*.js" -exec sed -i \
            -e 's|"assets/static/|"/verify/assets/static/|g' \
            -e 's|"/assets/static/|"/verify/assets/static/|g' {} \;
        echo "✅ Verify app copied and paths fixed"
    fi

    cd "$PROJECT_ROOT"
else
    echo "📋 Step 2: Skipping WebClients (--skip-webclient)"
fi

# Step 3: Verify paths
echo "📋 Step 3: Verify asset paths..."
DIST_PATH="WebClients/applications/drive/dist"
if [ -f "$DIST_PATH/account/index.html" ]; then
    if grep -q 'src="/assets/' "$DIST_PATH/account/index.html"; then
        echo "❌ CRITICAL: Account app has unfixed asset paths!"
        exit 1
    fi
    echo "✅ Account app paths verified"
fi

# Step 4: Build Tauri binary
echo "📋 Step 4: Build Tauri binary..."
npm install
cd src-tauri && cargo build --release && cd ..
if [ ! -f "src-tauri/target/release/proton-drive" ]; then
    echo "❌ Binary not found!"
    exit 1
fi
echo "✅ Binary built"

# Step 5: Create snap directory and snapcraft.yaml from template
echo "📋 Step 5: Create snapcraft.yaml from template..."
mkdir -p snap
sed "s/\${VERSION}/$VERSION/g" snap/snapcraft.yaml.template > snap/snapcraft.yaml
echo "Generated snapcraft.yaml with version $VERSION"

# For local builds, we use a simpler override-build that uses pre-built binary
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
      # Copy pre-built binary
      install -Dm755 src-tauri/target/release/proton-drive "\$SNAPCRAFT_PART_INSTALL/usr/bin/proton-drive"

      # Create wrapper script
      mkdir -p "\$SNAPCRAFT_PART_INSTALL/usr/bin"
      cat > "\$SNAPCRAFT_PART_INSTALL/usr/bin/proton-drive-wrapper" << 'WRAPPEREOF'
      #!/bin/bash
      export WEBKIT_DISABLE_DMABUF_RENDERER=1
      export WEBKIT_DISABLE_COMPOSITING_MODE=1
      exec "\$SNAP/usr/bin/proton-drive" "\$@"
      WRAPPEREOF
      chmod +x "\$SNAPCRAFT_PART_INSTALL/usr/bin/proton-drive-wrapper"

      # Desktop file
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

      # Icons
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

# Step 6: Build Snap
echo "📋 Step 6: Build Snap..."
snapcraft --destructive-mode

echo ""
echo "=========================================="
echo "✅ Snap Build Complete!"
echo "=========================================="
echo ""
echo "📦 Output:"
ls -la *.snap
echo ""
echo "🧪 Install and test:"
echo "   sudo snap install --dangerous proton-drive_*.snap"
echo "   snap run proton-drive"
echo ""
