#!/usr/bin/env bash
# Stage 3/3: vmtest for debian12 on 192.168.1.162.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"
source "$HERE/../../lib/_test_common.sh"

VM_IP="192.168.1.162"
PKG_FAMILY="deb"

distro_checks() {
  local ip="$1"
  echo "--- debian-12 specific checks ---"
  assert_on_vm "$ip" "dpkg: package is registered and status=ii" \
    "dpkg -l proton-drive 2>/dev/null | grep -q '^ii'"
  assert_on_vm "$ip" "dpkg: correct package architecture (amd64)" \
    "dpkg -l proton-drive 2>/dev/null | grep -q 'amd64\|all'"
  assert_on_vm "$ip" "copyright/license file present" \
    "ls /usr/share/doc/proton-drive/copyright 2>/dev/null | head -1"
}

test_run "debian12" "$VM_IP" "$PKG_FAMILY"
