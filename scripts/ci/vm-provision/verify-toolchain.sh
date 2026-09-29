#!/usr/bin/env bash
# Verify Rust toolchain + protondrive-linux release build on a VM test host.
# Usage: scripts/ci/vm-provision/verify-toolchain.sh <ip> <label>
# Transport: shared _vm_common.sh (VM_SSH_KEY CI variable, else the
# runner-mounted /root/.ssh config — same contract as build-deps.sh).
# Evidence emitted on stdout: rustup show, rustc --version, cargo --version,
# binary presence + sha256 at src-tauri/target/release/proton-drive.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../lib/_vm_common.sh"

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
  for d in /tmp/protondrive-linux /tmp/pd-deploy/protondrive-linux; do
    [ -d "$d/src-tauri/target/release" ] || continue
    BINARY="$d/src-tauri/target/release/proton-drive"
    if [ -f "$BINARY" ]; then
      echo "BINARY_PATH=$BINARY"
      sha256sum "$BINARY"
      "$BINARY" --version 2>/dev/null || echo "binary present; no --version flag"
      exit 0
    fi
  done
  echo "NOTE: no prior build tree or binary found on '"$LABEL"'"
  exit 2
' || {
  code=$?
  [ "$code" = 2 ] || {
    echo "=== $LABEL toolchain verification INCOMPLETE (exit $code) ==="
    exit "$code"
  }
}
echo "=== $LABEL toolchain verification done ==="
