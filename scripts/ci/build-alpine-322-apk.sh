#!/usr/bin/env bash
# =============================================================================
# build-alpine-322-apk.sh
# =============================================================================
# Builds a Proton Drive APK (.apk.tar.gz) package targetting Alpine Linux 3.22
# (musl libc).  Creates a clean git worktree, applies the alpine.3.22 patch
# set, builds the Tauri binary, and packs it into a portable tar.gz archive
# ready for distribution or installation on Alpine 3.22.
#
# Usage
# -----
#   scripts/ci/build-alpine-322-apk.sh
#   scripts/ci/build-alpine-322-apk.sh -h | --help   # show help text
#
# The script is designed to run from the project root or the ci/ directory;
# SCRIPT_DIR auto-resolves relative paths internally.
#
# Environment (inputs)
# --------------------
#   OUTPUT_DIR      Destination directory for the final artifact.
#                   Default: /tmp/protondrive-alpine322-apk
#   HOME/.cargo/env Sourced if present (for Rust/Cargo toolchain).
#
# Required files
# --------------
#   patches/apk/alpine.3.22.patch   The Alpine 3.22 patches applied to the
#                                   worktree before building.
#
# Outputs
# -------
#   proton-drive_<VERSION>_alpine322_amd64.apk.tar.gz
#       Written to OUTPUT_DIR.  The archive contains an FHS-like layout:
#         usr/bin/proton-drive                         (stripped ELF)
#         usr/share/applications/proton-drive.desktop   (desktop entry)
#         usr/share/icons/hicolor/*/apps/proton-drive.* (icons)
#
# Steps (high-level)
# ------------------
#   1. Validate that the required patch file exists.
#   2. Create a temporary git worktree from HEAD.
#   3. Apply the alpine.3.22 patch to the worktree.
#   4. Build WebClients assets via scripts/build-webclients.sh.
#   5. Build the Tauri release binary (npm install → npx tauri build).
#   6. Stage binary, desktop file, and icons in an APK-like directory tree.
#   7. Tar/gzip the staging directory to OUTPUT_DIR.
#   8. Clean up the temporary worktree.
#
# Called by
# ---------
#   GitLab CI job:  build:apk:alpine-3.22  (stage: build)
#   GitHub Actions: build-apk-alpine-3.22  (ci.yml workflow)
#   See .gitlab-ci.yml line ~124 and .github/workflows/ci.yml.
#
# Exit codes
# ----------
#   0   Success — artifact produced.
#   1   Patch file not found.
# =============================================================================
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/ci/build-alpine-322-apk.sh

Build the Proton Drive APK package for Alpine 3.22 musl using the
alpine.3.22 patch.

Environment:
  OUTPUT_DIR  Optional destination directory for the APK artifact.
              Defaults to /tmp/protondrive-alpine322-apk
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
PATCH_FILE="$REPO_ROOT/patches/apk/alpine.3.22.patch"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/protondrive-alpine322-apk}"
WORK_ROOT="$(mktemp -d -t protondrive-alpine322-XXXXXX)"
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

echo "Applying Alpine 3.22 patch..."
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

ARTIFACT_NAME="proton-drive_${VERSION}_alpine322_amd64.apk.tar.gz"
tar -C "$APK_STAGING" -czf "$OUTPUT_DIR/$ARTIFACT_NAME" .

echo "Built APK: $OUTPUT_DIR/$ARTIFACT_NAME"
