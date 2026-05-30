#!/usr/bin/env bash
# Stage 3/3: vmtest for opensuse-tw on 192.168.1.245.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"
source "$HERE/../../lib/_test_common.sh"

VM_IP="192.168.1.245"
PKG_FAMILY="rpm-zypper"

distro_checks() {
  local ip="$1"
  echo "--- opensuse-tumbleweed specific checks ---"
  assert_on_vm "$ip" "rpm: package is registered" \
    "rpm -q proton-drive"
  assert_on_vm "$ip" "zypper: package shows as installed" \
    "zypper search --installed-only -x proton-drive 2>/dev/null | grep -q proton-drive || rpm -q proton-drive"
  assert_on_vm "$ip" "libwebkit2gtk-4_1 runtime present on openSUSE" \
    "rpm -q libwebkit2gtk-4_1-0 2>/dev/null | grep -v 'not installed'"
}

test_run "opensuse-tw" "$VM_IP" "$PKG_FAMILY"
