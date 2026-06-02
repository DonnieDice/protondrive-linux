#!/usr/bin/env bash
# Stage 1/3: locate the arch package artifact and SCP it to the VM.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"

VM_IP="192.168.1.128"
PKG_GLOB="*.pkg.tar.zst"

transfer_run "arch" "$VM_IP" "$PKG_GLOB"
