#!/usr/bin/env bash
# Stage 3/3: vmtest for alpine320 on 192.168.1.157.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"
source "$HERE/../../lib/_test_common.sh"

VM_IP="192.168.1.157"
PKG_FAMILY="apk"

distro_checks() {
  local ip="$1"
  echo "--- alpine-3.20 specific checks ---"
  assert_on_vm "$ip" "binary uses musl libc (not glibc)" \
    'file /usr/bin/proton-drive | grep -qi "statically linked\|musl\|pie executable"'
  assert_on_vm "$ip" "no glibc dependency on musl system" \
    '! ldd /usr/bin/proton-drive 2>/dev/null | grep -qi "libgcc_s\|glibc"'
}

test_run "alpine320" "$VM_IP" "$PKG_FAMILY"
