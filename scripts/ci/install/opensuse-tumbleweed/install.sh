#!/usr/bin/env bash
# Stage 2/3: install the opensuse-tumbleweed RPM on the VM.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"

VM_IP="192.168.1.245"
: "${REMOTE_PKG_PATH:?transfer stage did not provide REMOTE_PKG_PATH}"

install_pkg() {
  local ip="$1" pkg="$2"
  run_on_vm "$ip" "
    rpm -i --force '$pkg' \
    || zypper --non-interactive --no-gpg-checks install -y --allow-unsigned-rpm '$pkg'
  "
}

install_run "opensuse-tw" "$VM_IP" "$REMOTE_PKG_PATH" install_pkg
