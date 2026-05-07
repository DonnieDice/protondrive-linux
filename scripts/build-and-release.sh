#!/bin/bash
set -e

echo "🏗️  Building Proton Drive Desktop..."

# Build web app
echo "📦 Building web app..."
cd WebClients/applications/drive
npm install
npm run build
cd ../../../

# Build Tauri
echo "🔨 Building Tauri app..."
npm run build

echo ""
echo "✅ Build complete!"
echo ""
echo "📁 Binaries location:"
echo "   src-tauri/target/release/bundle/"
echo ""
echo "To upload to GitHub Releases:"
echo "   1. Go to: https://github.com/DonnieDice/protondrive-linux/releases"
echo "   2. Click 'Edit'"
echo "   3. Drag and drop files from src-tauri/target/release/bundle/"
echo ""
echo "Or use gh CLI:"
echo "   gh release upload v$(node -p "require('./package.json').version") src-tauri/target/release/bundle/**/*"
