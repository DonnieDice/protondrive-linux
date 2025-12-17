#!/bin/bash
set -e

echo "🧪 Testing local build..."

# Clean
# rm -rf WebClients

# Clone
# echo "📥 Cloning WebClients..."
# git clone --depth=1 https://github.com/ProtonMail/WebClients.git WebClients

# Patch
echo "🔧 Patching..."
python3 fix_deps.py

# Build WebClients
echo "🔨 Building WebClients..."
cd WebClients
export NODE_OPTIONS="--max-old-space-size=8192"
node .yarn/releases/yarn-4.12.0.cjs install --network-timeout 600000
node .yarn/releases/yarn-4.12.0.cjs workspace proton-drive build
cd ..

# Build Tauri
echo "🔨 Building Tauri..."
npm install
npm run tauri build

# Success
echo "✅ Build test complete!"
echo "📦 Binaries in: src-tauri/target/release/bundle/"
find src-tauri/target/release/bundle -type f \( -name "*.AppImage" -o -name "*.deb" -o -name "*.rpm" -o -name "*.dmg" -o -name "*.msi" \)
