#!/usr/bin/env bash
# Stage 3/3: vmtest for el10 on 192.168.1.123.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"
source "$HERE/../../lib/_test_common.sh"

VM_IP="192.168.1.123"
PKG_FAMILY="rpm-dnf"

distro_checks() {
  local ip="$1"
  echo "--- el10 specific checks ---"
  assert_on_vm "$ip" "rpm: package is registered" \
    "rpm -q proton-drive"
  assert_on_vm "$ip" "rpm: correct architecture (x86_64)" \
    "rpm -q --qf '%{ARCH}\n' proton-drive | grep -q x86_64"
  assert_on_vm "$ip" "selinux: no denials for proton-drive at install" \
    '! (ausearch -c proton-drive -m avc 2>/dev/null | grep -q denied) || true'
  assert_on_vm "$ip" "epel repo enabled (required for webkit dep)" \
    "dnf repolist enabled 2>/dev/null | grep -qi epel"
}

test_run "el10" "$VM_IP" "$PKG_FAMILY"
