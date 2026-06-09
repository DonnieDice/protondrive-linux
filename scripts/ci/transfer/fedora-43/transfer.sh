#!/usr/bin/env bash
# Stage 1/3: locate the fedora43 RPM artifact and SCP it to the VM.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"

VM_IP="192.168.1.183"
PKG_GLOB="proton-drive-*.x86_64.rpm"

transfer_run "fedora43" "$VM_IP" "$PKG_GLOB"
