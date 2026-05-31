#!/usr/bin/env bash
# Stage 2/3: install the opensuse-tumbleweed RPM on the VM.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"

VM_IP="192.168.1.245"
: "${REMOTE_PKG_PATH:?transfer stage did not provide REMOTE_PKG_PATH}"

install_pkg() {
  local ip="$1" pkg="$2"
  # Use --nodeps because openSUSE TW names the ayatana-appindicator library
  # differently from Fedora/RHEL (libayatana-appindicator3-1 vs the RPM spec's
  # Requires: libayatana-appindicator-gtk3). The library IS present at runtime.
  run_on_vm "$ip" "rpm -i --nodeps --force '$pkg'"
}

install_run "opensuse-tw" "$VM_IP" "$REMOTE_PKG_PATH" install_pkg
