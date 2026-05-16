#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/ci/build-opensuse-tumbleweed-rpm.sh

Build the Proton Drive RPM in a temporary clean worktree using the
openSUSE Tumbleweed patch.

Environment:
  OUTPUT_DIR  Optional destination directory for the RPM artifact.
              Defaults to /tmp/protondrive-opensuse-tumbleweed-rpm
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
PATCH_FILE="$REPO_ROOT/patches/rpm/opensuse.tumbleweed.patch"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/protondrive-opensuse-tumbleweed-rpm}"
WORK_ROOT="$(mktemp -d -t protondrive-opensuse-tumbleweed-XXXXXX)"
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

echo "Applying openSUSE Tumbleweed patch..."
cd "$WORK_TREE"
git apply --check "$PATCH_FILE"
git apply "$PATCH_FILE"

echo "Building WebClients..."
scripts/build-webclients.sh

echo "Building RPM..."
if [ -f "$HOME/.cargo/env" ]; then
  . "$HOME/.cargo/env"
fi
export PATH="$HOME/.cargo/bin:$PATH"
if [ -n "${WEBKIT_OVERLAY:-}" ] && [ -d "$WEBKIT_OVERLAY/usr/lib64" ]; then
  WEBKIT_LINK_DIR="$WORK_ROOT/webkit-link-shim"
  mkdir -p "$WEBKIT_LINK_DIR"
  if [ -e /usr/lib64/libwebkit2gtk-4.1.so.0 ]; then
    ln -sf /usr/lib64/libwebkit2gtk-4.1.so.0 "$WEBKIT_LINK_DIR/libwebkit2gtk-4.1.so"
  fi
  if [ -e /usr/lib64/libjavascriptcoregtk-4.1.so.0 ]; then
    ln -sf /usr/lib64/libjavascriptcoregtk-4.1.so.0 "$WEBKIT_LINK_DIR/libjavascriptcoregtk-4.1.so"
  fi
  export LIBRARY_PATH="$WEBKIT_LINK_DIR:$WEBKIT_OVERLAY/usr/lib64:${LIBRARY_PATH:-}"
  if [ -n "${RUSTFLAGS:-}" ]; then
    export RUSTFLAGS="$RUSTFLAGS -L native=$WEBKIT_LINK_DIR -L native=$WEBKIT_OVERLAY/usr/lib64"
  else
    export RUSTFLAGS="-L native=$WEBKIT_LINK_DIR -L native=$WEBKIT_OVERLAY/usr/lib64"
  fi
fi
cargo --version
VERSION="$(node -p "require('./package.json').version")"
sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$VERSION\"/" src-tauri/tauri.conf.json
sed -i "0,/^version = \"[^\"]*\"/s//version = \"$VERSION\"/" src-tauri/Cargo.toml
npm install
npx tauri build --bundles rpm --verbose

echo "Normalizing RPM filename..."
cd src-tauri/target/release/bundle/rpm
shopt -s nullglob
for file in Proton\ Drive*.rpm; do
  mv "$file" "${file/Proton Drive/proton-drive}"
done

RPM_FILE="$(ls -1 "$PWD"/*.rpm 2>/dev/null | head -n 1 || true)"
if [ -z "$RPM_FILE" ]; then
  echo "ERROR: no RPM artifact was produced" >&2
  exit 1
fi

cp "$RPM_FILE" "$OUTPUT_DIR/"
echo "Built RPM: $OUTPUT_DIR/$(basename "$RPM_FILE")"
