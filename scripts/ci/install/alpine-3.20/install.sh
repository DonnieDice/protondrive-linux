#!/usr/bin/env bash
# Stage 2/3: install the alpine320 apk tarball on the VM.
# REMOTE_PKG_PATH is injected via the transfer stage dotenv artifact.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/_vm_common.sh"

VM_IP="192.168.1.157"
: "${REMOTE_PKG_PATH:?transfer stage did not provide REMOTE_PKG_PATH}"

install_pkg() {
  run_on_vm "$1" "cd /tmp/pd-deploy && tar -xzf $2 -C / && command -v proton-drive"
}

install_run "alpine320" "$VM_IP" "$REMOTE_PKG_PATH" install_pkg
