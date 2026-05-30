#!/usr/bin/env bash
# Deploy + smoke-test the debian13 package on its VM (192.168.1.120).
# Distro-specific install quirks live in install_pkg() below — edit here, not
# in _common.sh. Called by .gitlab/workflows/verify/debian-13.yml.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
source "$HERE/../_common.sh"

VM_IP="192.168.1.120"
PKG_GLOB="proton-drive_*_debian13_*.deb"

# install_pkg <ip> <remote-package-path>
install_pkg() {
  run_on_vm "$1" "DEBIAN_FRONTEND=noninteractive apt-get update -qq || true; apt-get install -y -q $2 || { dpkg -i $2; apt-get -y -f install; }"
}

deploy_run "debian13" "$VM_IP" "$PKG_GLOB" install_pkg
