#!/usr/bin/env bash
# Deploy + smoke-test the arch package on its VM (192.168.1.128).
# Distro-specific install quirks live in install_pkg() below — edit here, not
# in _common.sh. Called by .gitlab/workflows/verify/arch.yml.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
source "$HERE/../_common.sh"

VM_IP="192.168.1.128"
PKG_GLOB="*.pkg.tar.zst"

# install_pkg <ip> <remote-package-path>
install_pkg() {
  run_on_vm "$1" "pacman -U --noconfirm $2"
}

deploy_run "arch" "$VM_IP" "$PKG_GLOB" install_pkg
