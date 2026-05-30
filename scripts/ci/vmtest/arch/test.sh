#!/usr/bin/env bash
# Stage 3/3: regression checks + GUI load test for arch on 192.168.1.128.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"
source "$HERE/../../lib/_test_common.sh"

VM_IP="192.168.1.128"
PKG_FAMILY="aur"

test_run "arch" "$VM_IP" "$PKG_FAMILY"
