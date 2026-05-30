#!/usr/bin/env bash
# Stage 3/3: regression checks + GUI load test for alpine322 on 192.168.1.126.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"
source "$HERE/../../lib/_test_common.sh"

VM_IP="192.168.1.126"
PKG_FAMILY="apk"

test_run "alpine322" "$VM_IP" "$PKG_FAMILY"
