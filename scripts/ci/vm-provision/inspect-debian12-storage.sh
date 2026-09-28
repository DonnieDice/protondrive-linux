#!/usr/bin/env bash
# scripts/ci/vm-provision/inspect-debian12-storage.sh
#
# Read-only inspection for issue #15: locate the real debian12 backing disk on
# the tower. The domain definition points at /mnt/pool_two/domains/debian12/
# vdisk1.qcow2 which does not exist (guest-start job 26216 fail-fast evidence);
# issue #14 proved the analogous debian13 disk actually lives under
# /mnt/user/domains/debian13/vdisk1.qcow2. This script ONLY reads: it lists
# candidate storage locations and qemu-img info for any debian12 disk found.
# No mutation of any kind.

set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
OUT_DIR="${INSPECT_OUT_DIR:-inspect-results}"
mkdir -p "$OUT_DIR"

VM_KNOWN_HOSTS="${CI_PROJECT_DIR:-.}/.vm-known-hosts"
: > "$VM_KNOWN_HOSTS"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$VM_KNOWN_HOSTS"

tower() { ssh $SSH_OPTS "$TOWER_HOST" "$@"; }

echo "=== [inspect] tower identity ==="
tower "hostname; whoami; date -u" | tee "$OUT_DIR/identity.txt" || { echo "FATAL: cannot reach tower"; exit 1; }

echo "=== [inspect] domain definition (read-only) ==="
tower "sudo virsh dumpxml debian12" | tee "$OUT_DIR/debian12-dumpxml.txt" >/dev/null
tower "sudo virsh dumpxml debian12 | grep -A2 '<disk'" | tee "$OUT_DIR/debian12-disk-xml.txt"

echo "=== [inspect] candidate storage locations (read-only) ==="
tower "ls -la /mnt/user/domains/ 2>/dev/null; echo ---; ls -la /mnt/user/domains/debian12/ 2>/dev/null; echo ---; ls -la /mnt/pool_two/domains/debian12/ 2>/dev/null; echo ---; ls -la /mnt/pool_one/domains/debian12/ 2>/dev/null" | tee "$OUT_DIR/storage-listing.txt"

echo "=== [inspect] find qcow2 images named for debian12 (read-only) ==="
tower "find /mnt/user/domains /mnt/pool_one/domains /mnt/pool_two/domains -maxdepth 3 -name '*debian12*' 2>/dev/null" | tee "$OUT_DIR/find-debian12.txt"
tower "find /mnt/user/domains /mnt/pool_one/domains /mnt/pool_two/domains -maxdepth 3 -name 'vdisk*.qcow2' 2>/dev/null" | tee "$OUT_DIR/find-vdisks.txt"

echo "=== [inspect] qemu-img info for any discovered debian12 disk ==="
DISK="$(tower "find /mnt/user/domains/debian12 -maxdepth 2 -name 'vdisk1.qcow2' 2>/dev/null | head -1")"
if [ -n "$DISK" ]; then
  tower "sudo qemu-img info '$DISK'" | tee "$OUT_DIR/qemu-img-info.txt"
  echo "DISK_FOUND=$DISK" | tee "$OUT_DIR/disk-found.txt"
else
  echo "DISK_FOUND=none" | tee "$OUT_DIR/disk-found.txt"
fi

echo "=== [inspect] done (read-only) ==="
