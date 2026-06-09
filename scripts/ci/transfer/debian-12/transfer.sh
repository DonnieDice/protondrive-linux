#!/usr/bin/env bash
# Stage 1/3: locate the debian12 artifact and SCP it to the VM.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"

VM_IP="192.168.1.162"
PKG_GLOB="proton-drive_*_debian12_*.deb"

transfer_run "debian12" "$VM_IP" "$PKG_GLOB"
