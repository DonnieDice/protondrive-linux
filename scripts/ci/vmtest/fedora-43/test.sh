#!/usr/bin/env bash
# Stage 3/3: vmtest for fedora43 on 192.168.1.183.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"
source "$HERE/../../lib/_test_common.sh"

VM_IP="192.168.1.183"
PKG_FAMILY="rpm-dnf"

distro_checks() {
  local ip="$1"
  echo "--- fedora-43 specific checks ---"
  assert_on_vm "$ip" "rpm: package is registered" \
    "rpm -q proton-drive"
  assert_on_vm "$ip" "rpm: correct architecture (x86_64)" \
    "rpm -q --qf '%{ARCH}\n' proton-drive | grep -q x86_64"
  assert_on_vm "$ip" "webkit2gtk4.1 runtime present in Fedora repos" \
    "rpm -q webkit2gtk4.1 2>/dev/null | grep -v 'not installed' || dnf list installed webkit2gtk4.1 2>/dev/null | grep -q webkit"
}

test_run "fedora43" "$VM_IP" "$PKG_FAMILY"
