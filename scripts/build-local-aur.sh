#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

SKIP_WEBCLIENT=false
AUR_TARGET=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --aur-target)
            AUR_TARGET="$2"
            shift 2
            ;;
        --skip-webclient)
            SKIP_WEBCLIENT=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 --aur-target <target> [--skip-webclient]"
            echo "Targets: arch, manjaro, endeavour, garuda"
            exit 1
            ;;
    esac
done

if [ -z "$AUR_TARGET" ]; then
    echo "ERROR: --aur-target is required"
    echo "Targets: arch, manjaro, endeavour, garuda"
    exit 1
fi

echo "=========================================="
echo "Proton Drive AUR Build"
echo "=========================================="
echo "AUR target: ${AUR_TARGET}"

if ! command -v makepkg &> /dev/null; then
    echo "ERROR: makepkg not found. This script requires Arch Linux or Manjaro."
    exit 1
fi

BUILD_DIR=$(mktemp -d)
echo "Build directory: $BUILD_DIR"

cp aur/PKGBUILD "$BUILD_DIR/"

WRAPPER_FILE="$PROJECT_ROOT/patches/aur/${AUR_TARGET}.wrapper"
if [ -f "$WRAPPER_FILE" ]; then
    echo "Including ${AUR_TARGET} wrapper script..."
    cp "$WRAPPER_FILE" "$BUILD_DIR/proton-drive.wrapper"
fi

PATCHES_DIR="$PROJECT_ROOT/patches/aur"
if [ -d "$PATCHES_DIR" ] && ls "$PATCHES_DIR"/*.patch 1>/dev/null 2>&1; then
    echo "Copying AUR patches..."
    for patch in "$PATCHES_DIR"/*.patch; do
        echo "  $(basename "$patch")"
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
