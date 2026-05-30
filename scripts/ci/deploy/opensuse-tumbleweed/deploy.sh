#!/usr/bin/env bash
# Deploy + smoke-test the opensuse-tw package on its VM (192.168.1.245).
# Distro-specific install quirks live in install_pkg() below — edit here, not
# in _common.sh. Called by .gitlab/workflows/verify/opensuse-tumbleweed.yml.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
source "$HERE/../_common.sh"

VM_IP="192.168.1.245"
PKG_GLOB="*.rpm"

# install_pkg <ip> <remote-package-path>
install_pkg() {
  run_on_vm "$1" "zypper --non-interactive install --allow-unsigned-rpm $2 || rpm -i --force $2"
}

deploy_run "opensuse-tw" "$VM_IP" "$PKG_GLOB" install_pkg
