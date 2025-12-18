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
node .yarn/releases/yarn-4.12.0.cjs workspace proton-drive build

# 4. Go back to root
cd ..

echo "✅ WebClients build complete"
