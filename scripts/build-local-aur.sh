#!/bin/bash
# Local AUR PKGBUILD test script
# Usage: ./scripts/build-local-aur.sh
# Tests the PKGBUILD by running makepkg in a clean environment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

echo "=========================================="
echo "Proton Drive AUR PKGBUILD Test"
echo "=========================================="

# Check dependencies
if ! command -v makepkg &> /dev/null; then
    echo "ERROR: makepkg not found. This script requires Arch Linux or Manjaro."
    exit 1
fi

# Create temp build dir
BUILD_DIR=$(mktemp -d)
echo "Build directory: $BUILD_DIR"

# Copy PKGBUILD
cp aur/PKGBUILD "$BUILD_DIR/"

# Apply AUR-specific patches if any
PATCHES_DIR="$PROJECT_ROOT/patches/aur"
if [ -d "$PATCHES_DIR" ] && ls "$PATCHES_DIR"/*.patch 1>/dev/null 2>&1; then
    echo "Applying AUR-specific patches..."
    for patch in "$PATCHES_DIR"/*.patch; do
        echo "  Applying $(basename "$patch")..."
        cp "$patch" "$BUILD_DIR/"
    done
fi

cd "$BUILD_DIR"

echo ""
echo "Running makepkg..."
makepkg -sf --noconfirm

echo ""
echo "=========================================="
echo "AUR Build Complete!"
echo "=========================================="
ls -lh *.pkg.tar.zst 2>/dev/null || ls -lh *.pkg.tar.xz 2>/dev/null || echo "No package found"

echo ""
echo "To install: sudo pacman -U $BUILD_DIR/*.pkg.tar.zst"
echo "Build dir: $BUILD_DIR"
