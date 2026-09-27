#!/usr/bin/env bash
# Verify Rust toolchain + protondrive-linux release build on a VM test host.
# Usage: scripts/ci/vm-provision/verify-toolchain.sh <ip> <label>
# Transport: shared _vm_common.sh (VM_SSH_KEY CI variable, same as build-deps.sh).
# Evidence emitted on stdout: rustup show, rustc --version, cargo --version,
# binary presence + sha256 at src-tauri/target/release/proton-drive.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"

IP="${1:?usage: verify-toolchain.sh <ip> <label>}"
LABEL="${2:?usage: verify-toolchain.sh <ip> <label>}"

_pd_ssh_init

echo "=== Verifying Rust toolchain on $LABEL ($IP) ==="
run_on_vm "$IP" '
  set -euo pipefail
  export PATH="$HOME/.cargo/bin:$PATH"
  command -v rustup >/dev/null 2>&1 || { echo "FAIL: rustup not found on '"$LABEL"'"; exit 1; }
  rustup show
  rustc --version
  cargo --version
  [ -d /tmp/protondrive-linux/src-tauri/target/release ] || { echo "NOTE: no prior build tree on '"$LABEL"'"; exit 2; }
  BINARY=/tmp/protondrive-linux/src-tauri/target/release/proton-drive
  [ -f "$BINARY" ] || { echo "FAIL: binary not found at $BINARY"; exit 3; }
  sha256sum "$BINARY"
  "$BINARY" --version 2>/dev/null || echo "binary present; no --version flag"
' || { code=$?; [ "$code" = 2 ] || { echo "=== $LABEL toolchain verification INCOMPLETE (exit $code) ==="; exit "$code"; }; }
echo "=== $LABEL toolchain verification done ==="
