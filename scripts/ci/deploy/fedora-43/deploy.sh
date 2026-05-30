#!/usr/bin/env bash
# Deploy + smoke-test the fedora43 package on its VM (192.168.1.183).
# Distro-specific install quirks live in install_pkg() below — edit here, not
# in _common.sh. Called by .gitlab/workflows/verify/fedora-43.yml.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
source "$HERE/../_common.sh"

VM_IP="192.168.1.183"
PKG_GLOB="*.rpm"

# install_pkg <ip> <remote-package-path>
install_pkg() {
  run_on_vm "$1" "dnf install -y $2 || rpm -i --force $2"
}

deploy_run "fedora43" "$VM_IP" "$PKG_GLOB" install_pkg
