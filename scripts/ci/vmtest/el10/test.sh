#!/usr/bin/env bash
# Stage 3/3: regression checks + GUI load test for el10 on 192.168.1.123.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"
source "$HERE/../../lib/_test_common.sh"

VM_IP="192.168.1.123"
PKG_FAMILY="rpm-dnf"

test_run "el10" "$VM_IP" "$PKG_FAMILY"
