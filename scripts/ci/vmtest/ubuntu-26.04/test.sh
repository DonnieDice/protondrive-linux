#!/usr/bin/env bash
# Stage 3/3: vmtest for ubuntu26.04 on 192.168.1.168.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"
source "$HERE/../../lib/_test_common.sh"

VM_IP="192.168.1.168"
PKG_FAMILY="deb"

distro_checks() {
  local ip="$1"
  echo "--- ubuntu-26.04 specific checks ---"
  assert_on_vm "$ip" "dpkg: package is registered and status=ii" \
    "dpkg -l proton-drive 2>/dev/null | grep -q '^ii'"
  assert_on_vm "$ip" "apt-get shows package installed" \
    "apt-cache policy proton-drive 2>/dev/null | grep -q Installed"
}

test_run "ubuntu26.04" "$VM_IP" "$PKG_FAMILY"
