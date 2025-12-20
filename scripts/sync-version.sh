#!/bin/bash
# Sync version from package.json to all other version files

set -euo pipefail

VERSION=$(node -p "require('./package.json').version")
echo "Syncing version: $VERSION"

# Update tauri.conf.json
sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$VERSION\"/" src-tauri/tauri.conf.json
echo "  Updated src-tauri/tauri.conf.json"

# Update Cargo.toml (only the package version, not dependencies)
sed -i "0,/^version = \"[^\"]*\"/s//version = \"$VERSION\"/" src-tauri/Cargo.toml
echo "  Updated src-tauri/Cargo.toml"

# Update AUR PKGBUILD if it exists
if [ -f "aur/PKGBUILD" ]; then
    sed -i "s/^pkgver=.*/pkgver=$VERSION/" aur/PKGBUILD
    echo "  Updated aur/PKGBUILD"
fi

echo "Version sync complete: $VERSION"
