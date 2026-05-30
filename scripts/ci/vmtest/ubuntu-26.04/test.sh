#!/usr/bin/env bash
# Stage 3/3: regression checks + GUI load test for ubuntu26.04 on 192.168.1.168.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"
source "$HERE/../../lib/_test_common.sh"

VM_IP="192.168.1.168"
PKG_FAMILY="deb"

test_run "ubuntu26.04" "$VM_IP" "$PKG_FAMILY"
