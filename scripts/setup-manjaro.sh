#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "Proton Drive - Manjaro Build Dependencies"
echo "=========================================="
echo ""
echo "Installing required packages..."
echo ""

sudo pacman -S --noconfirm --needed \
    base-devel \
    libayatana-appindicator \
    webkit2gtk-4.1 \
    gtk3 \
    rustup \
    nodejs \
    npm \
    appimagetool \
    fuse2 \
    patchelf

echo ""
echo "Setting up Rust..."
if ! command -v cargo &> /dev/null; then
    rustup install stable
    rustup default stable
fi

echo ""
echo "=========================================="
echo "Dependencies installed!"
echo "=========================================="
echo ""
echo "Installed versions:"
echo "  makepkg:  $(which makepkg 2>/dev/null && makepkg --version 2>&1 | head -1 || echo 'not found')"
echo "  rustc:    $(rustc --version 2>/dev/null || echo 'not found')"
echo "  cargo:    $(cargo --version 2>/dev/null || echo 'not found')"
echo "  node:     $(node --version 2>/dev/null || echo 'not found')"
echo "  npm:      $(npm --version 2>/dev/null || echo 'not found')"
echo "  webkit2gtk: $(pacman -Q webkit2gtk-4.1 2>/dev/null || echo 'not found')"
echo "  gtk3:     $(pacman -Q gtk3 2>/dev/null || echo 'not found')"
echo "  libayatana: $(pacman -Q libayatana-appindicator 2>/dev/null || echo 'not found')"
