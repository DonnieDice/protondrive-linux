#!/usr/bin/env bash
# Stage 2/3: install the alpine322 apk tarball on the VM.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"

VM_IP="192.168.1.126"
: "${REMOTE_PKG_PATH:?transfer stage did not provide REMOTE_PKG_PATH}"

install_pkg() {
  run_on_vm "$1" "cd /tmp/pd-deploy && tar -xzf $2 -C / && command -v proton-drive"
}

install_run "alpine322" "$VM_IP" "$REMOTE_PKG_PATH" install_pkg
