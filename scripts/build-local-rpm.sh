#!/bin/bash
# Local RPM build script
# Usage: ./scripts/build-local-rpm.sh <patch-name> [--skip-webclient]
# Example: ./scripts/build-local-rpm.sh fedora.42

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

PATCH_NAME="${1:?Usage: $0 <patch-name> [--skip-webclient]}"
shift
SKIP_WEBCLIENT=false
[[ "${1:-}" == "--skip-webclient" ]] && SKIP_WEBCLIENT=true

echo "=========================================="
echo "Proton Drive RPM Build"
echo "=========================================="

# Build WebClients if needed
if [ "$SKIP_WEBCLIENT" = false ]; then
  "$SCRIPT_DIR/build-webclients.sh"
else
  echo "Skipping WebClients build (--skip-webclient)"
  if [ ! -d "WebClients/applications/drive/dist" ]; then
    echo "ERROR: WebClients dist not found! Run without --skip-webclient first."
    exit 1
  fi
fi

# Sync version
VERSION=$(node -p "require('./package.json').version")
echo "Building version: $VERSION"
sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$VERSION\"/" src-tauri/tauri.conf.json
sed -i "0,/^version = \"[^\"]*\"/s//version = \"$VERSION\"/" src-tauri/Cargo.toml

# Apply distro patch
DISTRO_PATCH="$PROJECT_ROOT/patches/rpm/${PATCH_NAME}.patch"
if [ -f "$DISTRO_PATCH" ]; then
  echo "Applying patches/rpm/${PATCH_NAME}.patch..."
  git apply "$DISTRO_PATCH"
else
  echo "ERROR: $DISTRO_PATCH not found"
  exit 1
fi

# Install deps and build with DISTRO_TYPE env
export DISTRO_TYPE=rpm
npm install
npx tauri build --bundles rpm --verbose

echo ""
echo "=========================================="
echo "RPM Build Complete!"
echo "=========================================="
find src-tauri/target/release/bundle -name "*.rpm" -exec ls -lh {} \;
