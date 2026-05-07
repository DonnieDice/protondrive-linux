#!/bin/bash
set -euo pipefail

echo "Building WebClients from local directory..."

# 1. Patch dependencies
echo "🔧 Patching dependencies..."
python3 scripts/fix_deps.py

# 2. Apply patches to WebClients source
echo "🩹 Applying patches..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PATCHES_DIR="$REPO_ROOT/patches/common"
cd WebClients
if [ -d "$PATCHES_DIR" ]; then
    for patch in "$PATCHES_DIR"/*.patch; do
        if [ -f "$patch" ]; then
            echo "  Applying $(basename "$patch")..."
            # Check if already applied (reverse-apply test)
            if git apply --reverse --check "$patch" 2>/dev/null; then
                echo "  ⚠ Already applied - skipping"
            elif git apply --check "$patch" 2>/dev/null; then
                git apply "$patch"
                echo "  ✓ Applied"
            else
                echo "  ❌ Failed to apply - conflicts detected"
                exit 1
            fi
        fi
    done
fi

# 3. Install dependencies in WebClients
echo "📦 Installing WebClients dependencies..."
# Create empty yarn.lock to mark WebClients as separate project (prevents workspace detection issues)
: > yarn.lock
rm -rf .yarn/cache
YARN="node $(ls .yarn/releases/yarn-*.cjs | head -1)"
export NODE_OPTIONS="--max-old-space-size=4096"
$YARN install || $YARN install --network-timeout 300000

# 4. Build all three apps in parallel (saves ~4-6 minutes vs sequential)
echo "🔨 Building Drive, Account, and Verify apps in parallel..."
$YARN workspace proton-drive build:web 2>&1 | tee /tmp/drive-build.log &
DRIVE_PID=$!
$YARN workspace proton-account build:web 2>&1 | tee /tmp/account-build.log &
ACCOUNT_PID=$!
$YARN workspace proton-verify build:web 2>&1 | tee /tmp/verify-build.log &
VERIFY_PID=$!

wait $DRIVE_PID   && echo "✅ Drive build complete"   || { echo "❌ Drive build failed"; exit 1; }
wait $ACCOUNT_PID && echo "✅ Account build complete" || echo "⚠️  Account build failed (login may not work)"
wait $VERIFY_PID  && echo "✅ Verify build complete"  || echo "⚠️  Verify build failed (captcha optional)"

# 4d. Copy account app to drive dist and fix paths
echo "📦 Copying account app to drive dist..."
if [ -d "applications/account/dist" ]; then
  cp -r applications/account/dist applications/drive/dist/account
  echo "🔧 Fixing account app paths for nested deployment..."
  # Fix base href and asset paths in account app HTML files
  # CRITICAL: Remove integrity/crossorigin attributes that break after path changes
  find applications/drive/dist/account -name "*.html" -exec sed -i \
    -e 's|<base href="/">|<base href="/account/">|g' \
    -e 's|href="/assets/|href="/account/assets/|g' \
    -e 's|src="/assets/|src="/account/assets/|g' \
    -e 's|content="/assets/|content="/account/assets/|g' \
    -e 's| integrity="[^"]*"||g' \
    -e 's| crossorigin="anonymous"||g' {} \;
  # Fix asset paths in JavaScript files (runtime chunks reference other chunks)
  find applications/drive/dist/account -name "*.js" -exec sed -i \
    -e 's|"//assets/static/|"/account/assets/static/|g' \
    -e 's|"assets/static/|"/account/assets/static/|g' \
    -e 's|"/assets/static/|"/account/assets/static/|g' \
    -e 's|"//assets/|"/account/assets/|g' {} \;
  # Fix webpack publicPath in runtime.js — prevents lazy chunks (locales, date-fns, etc.)
  # from resolving to wrong absolute paths and failing to load after login
  find applications/drive/dist/account -name "runtime*.js" -exec sed -i \
    's/\.p="\/"/.p=""/g' {} \;
  # Strip webpack SRI hashes — WebKitGTK rejects script integrity on tauri:// protocol,
  # causing "Loading chunk X failed" even when HTTP 200. --no-sri at build time is primary
  # fix; this is the safety net in case build flag is missing.
  find applications/drive/dist/account -name "runtime*.js" -exec python3 -c "
import re, sys
for p in sys.argv[1:]:
    c = open(p).read()
    c = re.sub(r'\.sriHashes=\{[^}]*\}', '.sriHashes={}', c)
    open(p,'w').write(c)
" {} \;
  echo "✅ Account app copied and paths fixed"
fi

# 4e. Copy verify app to drive dist and fix paths
echo "📦 Copying verify app to drive dist..."
if [ -d "applications/verify/dist" ]; then
  cp -r applications/verify/dist applications/drive/dist/verify
  echo "🔧 Fixing verify app paths for nested deployment..."
  # Fix base href and asset paths in verify app HTML files
  # CRITICAL: Remove integrity/crossorigin attributes that break after path changes
  find applications/drive/dist/verify -name "*.html" -exec sed -i \
    -e 's|<base href="/">|<base href="/verify/">|g' \
    -e 's|href="/assets/|href="/verify/assets/|g' \
    -e 's|src="/assets/|src="/verify/assets/|g' \
    -e 's|content="/assets/|content="/verify/assets/|g' \
    -e 's| integrity="[^"]*"||g' \
    -e 's| crossorigin="anonymous"||g' {} \;
  # Fix asset paths in JavaScript files
  find applications/drive/dist/verify -name "*.js" -exec sed -i \
    -e 's|"//assets/static/|"/verify/assets/static/|g' \
    -e 's|"assets/static/|"/verify/assets/static/|g' \
    -e 's|"/assets/static/|"/verify/assets/static/|g' \
    -e 's|"//assets/|"/verify/assets/|g' {} \;
  find applications/drive/dist/verify -name "runtime*.js" -exec sed -i \
    's/\.p="\/"/.p=""/g' {} \;
  find applications/drive/dist/verify -name "runtime*.js" -exec python3 -c "
import re, sys
for p in sys.argv[1:]:
    c = open(p).read()
    c = re.sub(r'\.sriHashes=\{[^}]*\}', '.sriHashes={}', c)
    open(p,'w').write(c)
" {} \;
  echo "✅ Verify app copied and paths fixed"
fi

# Strip SRI from all dist files — drive, account, verify
# 1. Remove integrity/crossorigin from drive's own index.html (SRI hashes become invalid after
#    we modify runtime.js, so the browser rejects the modified file)
find applications/drive/dist -maxdepth 1 -name "*.html" -exec sed -i \
  -e 's| integrity="[^"]*"||g' \
  -e 's| crossorigin="anonymous"||g' {} \;
# 2. Strip sriHashes object and unconditional integrity assignment from all runtime.js files
#    (unconditional i.integrity=sriHashes[e] sets integrity="undefined" which browser rejects)
find applications/drive/dist -name "runtime*.js" -exec python3 -c "
import re, sys
for p in sys.argv[1:]:
    c = open(p).read()
    c = re.sub(r'\.sriHashes=\{[^}]*\}', '.sriHashes={}', c)
    c = re.sub(r'[a-z]\.integrity=[a-z]\.sriHashes\[[a-z]\],', '', c)
    open(p,'w').write(c)
" {} \;

# 5. Verify build output
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

# 5b. Verify account/verify app paths are correctly fixed
if [ -f "applications/drive/dist/account/index.html" ]; then
  echo "🔍 Verifying account app asset paths..."
  if grep -q 'src="/assets/' "applications/drive/dist/account/index.html"; then
    echo "❌ CRITICAL: Account app has unfixed asset paths!"
    echo "   Found: src=\"/assets/\" (should be src=\"/account/assets/\")"
    echo "   This will cause white screen in packaged apps!"
    exit 1
  fi
  if grep -q 'href="/assets/' "applications/drive/dist/account/index.html"; then
    echo "❌ CRITICAL: Account app has unfixed href paths!"
    exit 1
  fi
  if ! grep -q '<base href="/account/">' "applications/drive/dist/account/index.html"; then
    echo "❌ CRITICAL: Account app missing correct base href!"
    exit 1
  fi
  echo "✅ Account app paths verified"
fi

if [ -f "applications/drive/dist/verify/index.html" ]; then
  echo "🔍 Verifying verify app asset paths..."
  if grep -q 'src="/assets/' "applications/drive/dist/verify/index.html"; then
    echo "❌ CRITICAL: Verify app has unfixed asset paths!"
    exit 1
  fi
  echo "✅ Verify app paths verified"
fi

# 6. Go back to root
cd ..

echo "✅ WebClients build complete"