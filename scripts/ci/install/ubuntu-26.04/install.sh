#!/usr/bin/env bash
# Stage 2/3: install the ubuntu26.04 .deb package on the VM.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"

VM_IP="192.168.1.168"
: "${REMOTE_PKG_PATH:?transfer stage did not provide REMOTE_PKG_PATH}"

install_pkg() {
  run_on_vm "$1" "DEBIAN_FRONTEND=noninteractive apt-get update -qq || true
    apt-get install -y -q $2 || { dpkg -i $2; apt-get -y -f install; }"
}

install_run "ubuntu26.04" "$VM_IP" "$REMOTE_PKG_PATH" install_pkg
