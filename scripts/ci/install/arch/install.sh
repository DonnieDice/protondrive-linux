#!/usr/bin/env bash
# Stage 2/3: install the arch package on the VM using pacman.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"

VM_IP="192.168.1.128"
: "${REMOTE_PKG_PATH:?transfer stage did not provide REMOTE_PKG_PATH}"

install_pkg() {
  run_on_vm "$1" "pacman -U --noconfirm $2"
}

install_run "arch" "$VM_IP" "$REMOTE_PKG_PATH" install_pkg
