#!/usr/bin/env bash
# Stage 1/3: locate the alpine322 artifact and SCP it to the VM.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"

VM_IP="192.168.1.126"
PKG_GLOB="proton-drive_*_alpine322_amd64.apk.tar.gz"

transfer_run "alpine322" "$VM_IP" "$PKG_GLOB"
