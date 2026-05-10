#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
cd "$PROJECT_ROOT"

SKIP_WEBCLIENT=false
DISTRO_PATCH="${1:-fedora.43}"

if [[ "${1:-}" == "--skip-webclient" ]]; then
  SKIP_WEBCLIENT=true
  DISTRO_PATCH=fedora.43
elif [[ "${2:-}" == "--skip-webclient" ]]; then
  SKIP_WEBCLIENT=true
fi

echo "=========================================="
echo "Proton Drive RPM Build"
echo "=========================================="
echo "Distro patch: ${DISTRO_PATCH}"

if [ "$SKIP_WEBCLIENT" = false ]; then
  "$PROJECT_ROOT/scripts/build-webclients.sh"
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

PATCH_FILE="patches/rpm/${DISTRO_PATCH}.patch"
if [ ! -f "$PATCH_FILE" ]; then
  echo "ERROR: Missing distro patch: $PATCH_FILE"
  exit 1
fi

if git apply --reverse --check "$PATCH_FILE" 2>/dev/null; then
  echo "Patch already applied: $PATCH_FILE"
else
  git apply --check "$PATCH_FILE"
  git apply "$PATCH_FILE"
  echo "Applied $PATCH_FILE"
fi

export DISTRO_TYPE=rpm
npm install
npx tauri build --bundles rpm --verbose

echo ""
echo "=========================================="
echo "RPM Build Complete!"
echo "=========================================="
find src-tauri/target/release/bundle -name "*.rpm" -exec ls -lh {} \;
