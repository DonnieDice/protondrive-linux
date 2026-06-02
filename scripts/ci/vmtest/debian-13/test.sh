#!/usr/bin/env bash
# Stage 3/3: vmtest for debian13 on 192.168.1.120.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"
source "$HERE/../../lib/_test_common.sh"

VM_IP="192.168.1.120"
PKG_FAMILY="deb"

distro_checks() {
  local ip="$1"
  echo "--- debian-13 specific checks ---"
  assert_on_vm "$ip" "dpkg: package is registered and status=ii" \
    "dpkg -l proton-drive 2>/dev/null | grep -q '^ii'"
  assert_on_vm "$ip" "dpkg: correct package architecture (amd64)" \
    "dpkg -l proton-drive 2>/dev/null | grep -q 'amd64\|all'"
  assert_on_vm "$ip" "libwebkit2gtk-4.1 available on debian13" \
    "dpkg -l libwebkit2gtk-4.1-0 2>/dev/null | grep -q '^ii'"
}

test_run "debian13" "$VM_IP" "$PKG_FAMILY"
