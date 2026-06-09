#!/usr/bin/env bash
# Verify version consistency across all four canonical sources.
# Requires: jq, grep, sed, awk.
# Called by: GitLab CI test:version-consistency and `just versions`.
set -euo pipefail

PKG=$(jq -r .version package.json)
LOCK=$(jq -r .version package-lock.json)
CONF=$(jq -r .version src-tauri/tauri.conf.json)
CARGO=$(grep -m1 '^version' src-tauri/Cargo.toml | sed 's/.*"\(.*\)".*/\1/')
CARGO_LOCK=$(awk '/name = "proton-drive"/ { found=1; next } found && /^version = / { gsub(/"/, "", $3); print $3; exit }' src-tauri/Cargo.lock)

echo "package.json=$PKG  package-lock.json=$LOCK  tauri.conf.json=$CONF  Cargo.toml=$CARGO  Cargo.lock=$CARGO_LOCK"

if [ "$PKG" = "$LOCK" ] && [ "$PKG" = "$CONF" ] && [ "$PKG" = "$CARGO" ] && [ "$PKG" = "$CARGO_LOCK" ]; then
    echo "OK: all versions match ($PKG)"
else
    echo "ERROR: version mismatch — bump all four files to the same version before tagging."
    exit 1
fi
