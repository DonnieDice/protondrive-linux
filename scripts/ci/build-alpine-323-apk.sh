#!/usr/bin/env bash
# build-alpine-323-apk.sh
# ========================
# Builds a Proton Drive APK (.apk.tar.gz) package for Alpine 3.23 (musl).
# Creates a clean git worktree, applies the alpine.3.23 patch, builds the
# Tauri binary, and packs it into a portable tar.gz archive suitable for
# installation on Alpine Linux via apk.
#
# Purpose:
#   Produces a redistributable Alpine Linux APK bundle for Proton Drive on
#   musl-based systems. Called by the GitLab CI pipeline to generate the
#   alpine:3.23 build artifact for release or testing.
#
# Usage:
#   scripts/ci/build-alpine-323-apk.sh
#   scripts/ci/build-alpine-323-apk.sh --help   # show usage then exit
#
# Inputs:
#   - files:  patches/apk/alpine.3.23.patch  (required — the Alpine-specific patch)
#   - env:    OUTPUT_DIR  (optional, default: /tmp/protondrive-alpine323-apk)
#             Determines where the final .apk.tar.gz artefact is written.
#
# Outputs:
#   - proton-drive_<version>_alpine323_amd64.apk.tar.gz
#     Written to OUTPUT_DIR (or the default if unset).
#
# Called by:
#   GitLab CI job 'build:apk:alpine-3.23' — stage: build
#   (line 192 of .gitlab-ci.yml)
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/ci/build-alpine-323-apk.sh

Build the Proton Drive APK package for Alpine 3.23 musl using the
alpine.3.23 patch.

Environment:
  OUTPUT_DIR  Optional destination directory for the APK artifact.
              Defaults to /tmp/protondrive-alpine323-apk
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
PATCH_FILE="$REPO_ROOT/patches/apk/alpine.3.23.patch"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/protondrive-alpine323-apk}"
WORK_ROOT="$(mktemp -d -t protondrive-alpine323-XXXXXX)"
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

echo "Applying Alpine 3.23 patch..."
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

ARTIFACT_NAME="proton-drive_${VERSION}_alpine323_amd64.apk.tar.gz"
tar -C "$APK_STAGING" -czf "$OUTPUT_DIR/$ARTIFACT_NAME" .

echo "Built APK: $OUTPUT_DIR/$ARTIFACT_NAME"
