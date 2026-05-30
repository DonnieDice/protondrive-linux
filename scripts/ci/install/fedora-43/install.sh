#!/usr/bin/env bash
# Stage 2/3: install the fedora43 RPM on the VM.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"

VM_IP="192.168.1.183"
: "${REMOTE_PKG_PATH:?transfer stage did not provide REMOTE_PKG_PATH}"

install_pkg() {
  run_on_vm "$1" "dnf install -y $2 || rpm -i --force $2"
}

install_run "fedora43" "$VM_IP" "$REMOTE_PKG_PATH" install_pkg
