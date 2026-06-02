#!/usr/bin/env bash
# Stage 1/3: locate the debian13 artifact and SCP it to the VM.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"

VM_IP="192.168.1.120"
PKG_GLOB="proton-drive_*_debian13_*.deb"

transfer_run "debian13" "$VM_IP" "$PKG_GLOB"
