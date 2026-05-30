#!/usr/bin/env bash
# Deploy + smoke-test the alpine320 package on its VM (192.168.1.157).
# Distro-specific install quirks live in install_pkg() below — edit here, not
# in _common.sh. Called by .gitlab/workflows/verify/alpine-3.20.yml.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
source "$HERE/../_common.sh"

VM_IP="192.168.1.157"
PKG_GLOB="proton-drive_*_alpine320_amd64.apk.tar.gz"

# install_pkg <ip> <remote-package-path>
install_pkg() {
  run_on_vm "$1" "cd /tmp/pd-deploy && tar -xzf $2 -C / && command -v proton-drive"
}

deploy_run "alpine320" "$VM_IP" "$PKG_GLOB" install_pkg
