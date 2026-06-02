#!/usr/bin/env bash
# Stage 1/3: locate the alpine320 artifact and SCP it to the VM.
# Emits transfer-results/alpine320.{json,env} — env is picked up by the install stage.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"

VM_IP="192.168.1.157"
PKG_GLOB="proton-drive_*_alpine320_amd64.apk.tar.gz"

transfer_run "alpine320" "$VM_IP" "$PKG_GLOB"
