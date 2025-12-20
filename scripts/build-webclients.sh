#!/bin/bash
set -euo pipefail

echo "Building WebClients from local directory..."

# 1. Patch dependencies
echo "🔧 Patching dependencies..."
python3 scripts/fix_deps.py

# 2. Install dependencies in WebClients
echo "📦 Installing WebClients dependencies..."
cd WebClients
rm -f yarn.lock
rm -rf .yarn/cache
export NODE_OPTIONS="--max-old-space-size=8192"
node .yarn/releases/yarn-4.12.0.cjs install || node .yarn/releases/yarn-4.12.0.cjs install --network-timeout 300000

# 3. Build proton-drive
echo "🔨 Building Proton Drive web app..."
node .yarn/releases/yarn-4.12.0.cjs workspace proton-drive build:web

# 4. Verify build output
echo "🔍 Verifying build output..."
if [ ! -d "applications/drive/dist" ]; then
  echo "❌ CRITICAL: dist directory not found!"
  exit 1
fi

if [ ! -f "applications/drive/dist/index.html" ]; then
  echo "❌ CRITICAL: index.html not found in dist!"
  echo "Contents of dist:"
  ls -la applications/drive/dist/ || echo "Cannot list dist directory"
  exit 1
fi

echo "✅ Build verification passed"
echo "📦 Dist contents:"
ls -lah applications/drive/dist/

# Count files
FILE_COUNT=$(find applications/drive/dist -type f | wc -l)
echo "📊 Total files in dist: $FILE_COUNT"

if [ "$FILE_COUNT" -lt 5 ]; then
  echo "⚠️  WARNING: Very few files in dist directory!"
fi

# 5. Go back to root
cd ..

echo "✅ WebClients build complete"