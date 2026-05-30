#!/usr/bin/env bash
# Stage 1/3: locate the ubuntu24.04 artifact and SCP it to the VM.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"

VM_IP="192.168.1.219"
PKG_GLOB="proton-drive_*_ubuntu24.04_*.deb"

transfer_run "ubuntu24.04" "$VM_IP" "$PKG_GLOB"
