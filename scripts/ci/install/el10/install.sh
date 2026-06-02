#!/usr/bin/env bash
# Stage 2/3: install the el10 RPM on the VM.
# NOTE: EL10 requires EPEL + CRB repos to be enabled on the VM for webkit2gtk4.1
# and libayatana-appindicator-gtk3. Enable those repos once during VM provisioning,
# not here — this script only installs the package as an end user would.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"

VM_IP="192.168.1.123"
: "${REMOTE_PKG_PATH:?transfer stage did not provide REMOTE_PKG_PATH}"

install_pkg() {
  run_on_vm "$1" "dnf install -y $2 || rpm -i --force $2"
}

install_run "el10" "$VM_IP" "$REMOTE_PKG_PATH" install_pkg
