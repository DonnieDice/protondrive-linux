#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/ci/build-alpine-320-apk.sh

Build the Proton Drive APK package for Alpine 3.20 musl using the
alpine.3.20 patch.

Environment:
  OUTPUT_DIR  Optional destination directory for the APK artifact.
              Defaults to /tmp/protondrive-alpine320-apk
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
PATCH_FILE="$REPO_ROOT/patches/apk/alpine.3.20.patch"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/protondrive-alpine320-apk}"
WORK_ROOT="$(mktemp -d -t protondrive-alpine320-XXXXXX)"
WORK_TREE="$WORK_ROOT/protondrive-linux"

cleanup() {
  rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

if [ ! -f "$PATCH_FILE" ]; then
  echo "ERROR: missing patch file: $PATCH_FILE" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "Creating clean worktree..."
git -C "$REPO_ROOT" worktree add --detach "$WORK_TREE" HEAD >/dev/null

echo "Applying Alpine 3.20 patch..."
cd "$WORK_TREE"
git apply --check "$PATCH_FILE"
git apply "$PATCH_FILE"

echo "Building WebClients..."
scripts/build-webclients.sh

echo "Building binary..."
if [ -f "$HOME/.cargo/env" ]; then
  . "$HOME/.cargo/env"
fi
export PATH="$HOME/.cargo/bin:$PATH"
cargo --version
VERSION="$(node -p "require('./package.json').version")"
sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$VERSION\"/" src-tauri/tauri.conf.json
sed -i "0,/^version = \"[^\"]*\"/s//version = \"$VERSION\"/" src-tauri/Cargo.toml
npm install
npx tauri build --verbose

echo "Packaging APK..."
BINARY="src-tauri/target/release/proton-drive"
if [ ! -f "$BINARY" ]; then
  echo "ERROR: binary not found at $BINARY" >&2
  exit 1
fi

APK_STAGING="$WORK_ROOT/apk-staging"
mkdir -p "$APK_STAGING/usr/bin"
mkdir -p "$APK_STAGING/usr/share/applications"
mkdir -p "$APK_STAGING/usr/share/icons/hicolor/32x32/apps"
mkdir -p "$APK_STAGING/usr/share/icons/hicolor/128x128/apps"
mkdir -p "$APK_STAGING/usr/share/icons/hicolor/128x128@2/apps"
mkdir -p "$APK_STAGING/usr/share/icons/hicolor/scalable/apps"

cp "$BINARY" "$APK_STAGING/usr/bin/proton-drive"
strip "$APK_STAGING/usr/bin/proton-drive" 2>/dev/null || true
cp src-tauri/linux/proton-drive.desktop "$APK_STAGING/usr/share/applications/"
cp src-tauri/icons/32x32.png "$APK_STAGING/usr/share/icons/hicolor/32x32/apps/proton-drive.png"
cp src-tauri/icons/128x128.png "$APK_STAGING/usr/share/icons/hicolor/128x128/apps/proton-drive.png"
cp src-tauri/icons/128x128@2x.png "$APK_STAGING/usr/share/icons/hicolor/128x128@2/apps/proton-drive.png"
cp src-tauri/icons/proton-drive.svg "$APK_STAGING/usr/share/icons/hicolor/scalable/apps/proton-drive.svg"

ARTIFACT_NAME="proton-drive_${VERSION}_alpine320_amd64.apk.tar.gz"
tar -C "$APK_STAGING" -czf "$OUTPUT_DIR/$ARTIFACT_NAME" .

echo "Built APK: $OUTPUT_DIR/$ARTIFACT_NAME"
