#!/usr/bin/env bash
# scripts/ci/vm-provision/opensuse-tumbleweed-inspect-iso.sh
# Read-only inspection of the openSUSE Tumbleweed ISO layout on tower.
# Answers: kernel/initrd paths + boot params for a headless serial install.
set -uo pipefail
TOWER_HOST="${TOWER_HOST:-tower}"
VM_KNOWN_HOSTS="${CI_PROJECT_DIR:-.}/.vm-known-hosts"
: > "$VM_KNOWN_HOSTS"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$VM_KNOWN_HOSTS"
tower() { ssh $SSH_OPTS "$TOWER_HOST" "$@"; }
ISO="${ISO_PATH:-/mnt/pool_one/isos/openSUSE-Tumbleweed-GNOME-Live-x86_64-Current.iso}"
OUT_DIR="${ISO_OUT_DIR:-iso-inspect}"
mkdir -p "$OUT_DIR"
echo "=== ISO file ==="
tower "ls -la '$ISO'; file '$ISO'" | tee "$OUT_DIR/iso-head.txt" || true
echo "=== ISO top-level (bsdtar) ==="
tower "bsdtar -tf '$ISO' 2>/dev/null | head -60" | tee "$OUT_DIR/iso-listing.txt" || true
echo "=== boot/* ==="
tower "bsdtar -tf '$ISO' 2>/dev/null | grep -E '^boot/' | head -40" | tee -a "$OUT_DIR/iso-listing.txt" || true
exit 0
