#!/usr/bin/env bash
# Stage 3/3: vmtest for arch on 192.168.1.128.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"
source "$HERE/../../lib/_test_common.sh"

VM_IP="192.168.1.128"
PKG_FAMILY="aur"

distro_checks() {
  local ip="$1"
  echo "--- arch specific checks ---"
  assert_on_vm "$ip" "pacman: package registered in local db" \
    "pacman -Q proton-drive"
  assert_on_vm "$ip" "pacman: correct architecture" \
    "pacman -Qi proton-drive 2>/dev/null | grep -i 'Architecture' | grep -qi x86_64"
  assert_on_vm "$ip" "webkit2gtk-4.1 runtime present (Arch native)" \
    "pacman -Q webkit2gtk-4.1 2>/dev/null | grep -q webkit2gtk"
}

test_run "arch" "$VM_IP" "$PKG_FAMILY"
