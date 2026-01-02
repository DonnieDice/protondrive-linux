#!/bin/bash
# Local Flatpak build script - mirrors GitHub workflow
# Usage: ./scripts/build-flatpak.sh [--skip-webclient]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

SKIP_WEBCLIENT=false
[[ "${1:-}" == "--skip-webclient" ]] && SKIP_WEBCLIENT=true

echo "=========================================="
echo "🔧 Proton Drive Flatpak Build"
echo "=========================================="

# Check dependencies
if ! command -v flatpak-builder &> /dev/null; then
    echo "❌ flatpak-builder not installed. Install with:"
    echo "   sudo pacman -S flatpak-builder"
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

# Step 5: Setup Flatpak runtime
echo "📋 Step 5: Setup Flatpak runtime..."
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user -y flathub org.gnome.Platform//47 org.gnome.Sdk//47 || true

# Step 6: Create wrapper script
echo "📋 Step 6: Create wrapper and desktop file..."
cat > proton-drive-wrapper.sh << 'EOF'
#!/bin/bash
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export WEBKIT_DISABLE_COMPOSITING_MODE=1
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

# Step 7: Create staging directory
echo "📋 Step 7: Create staging directory..."
rm -rf flatpak-staging
mkdir -p flatpak-staging/icons
cp src-tauri/target/release/proton-drive flatpak-staging/proton-drive-bin
cp proton-drive-wrapper.sh flatpak-staging/proton-drive
cp src-tauri/icons/32x32.png flatpak-staging/icons/
cp src-tauri/icons/128x128.png flatpak-staging/icons/
cp src-tauri/icons/128x128@2x.png flatpak-staging/icons/
cp src-tauri/icons/proton-drive.svg flatpak-staging/icons/
cp com.proton.drive.desktop flatpak-staging/

# Step 8: Create manifest
echo "📋 Step 8: Create Flatpak manifest..."
cat > com.proton.drive.yml << EOF
app-id: com.proton.drive
runtime: org.gnome.Platform
runtime-version: '47'
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

# Step 9: Build Flatpak
echo "📋 Step 9: Build Flatpak..."
rm -rf build-dir repo
flatpak-builder --user --force-clean --repo=repo build-dir com.proton.drive.yml

# Step 10: Create bundle
echo "📋 Step 10: Create Flatpak bundle..."
flatpak build-bundle repo "proton-drive_${VERSION}.flatpak" com.proton.drive

echo ""
echo "=========================================="
echo "✅ Flatpak Build Complete!"
echo "=========================================="
echo ""
echo "📦 Output: proton-drive_${VERSION}.flatpak"
echo ""
echo "🧪 Install and test:"
echo "   flatpak install --user proton-drive_${VERSION}.flatpak"
echo "   flatpak run com.proton.drive"
echo ""
