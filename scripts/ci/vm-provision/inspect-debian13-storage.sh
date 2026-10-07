#!/usr/bin/env bash
# scripts/ci/vm-provision/inspect-debian13-storage.sh
#
# Read-only storage inspection for issue #14: diagnose why
# `virsh start debian13` failed with
#   "Path '/mnt/pool_two/domains/debian13/vdisk1.qcow2' is not accessible:
#    No such file or directory"
# (job 24760, pipeline 2180, 2026-09-28 07:55Z).
#
# Everything in this script is read-only: ls, find, df, mount inspection,
# virsh domblklist/dumpxml queries, ip neigh. No file is created, moved,
# or written on the tower; no guest is started, defined, or modified.
#
# Transport: the runner-mounted /root/.ssh config (alias: tower) — the
# same transport the successful inventory job 24251 and guest-start job
# 24760 used.

set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
OUT_DIR="${INSPECT_OUT_DIR:-inspect-results}"
mkdir -p "$OUT_DIR"

VM_KNOWN_HOSTS="${CI_PROJECT_DIR:-.}/.vm-known-hosts"
: > "$VM_KNOWN_HOSTS"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$VM_KNOWN_HOSTS"

tower() { ssh $SSH_OPTS "$TOWER_HOST" "$@"; }

run() {
  local name="$1"; shift
  echo "=== [inspect] $name ==="
  tower "$@" 2>&1 | tee "$OUT_DIR/$name.txt"
  echo
}

run identity "hostname; whoami; date -u"

# Is pool_two mounted at all? (Unraid pool stopped => path gone for all disks)
run pool-mount-state "df -h /mnt/pool_one /mnt/pool_two /mnt/user 2>&1; echo ---; mount | grep -E 'pool_one|pool_two|mnt/user' || echo 'no matching mounts in mount table'; echo ---; ls -ld /mnt/pool_one /mnt/pool_two 2>&1"

# What actually exists under pool_two?
run pool-two-tree "ls -la /mnt/pool_two/ 2>&1; echo ---; ls -la /mnt/pool_two/domains/ 2>&1; echo ---; ls -la /mnt/pool_two/domains/debian13/ 2>&1; echo ---; ls -la /mnt/pool_two/domains/debian12/ 2>&1"

# What exists under pool_one (ISO media)?
run pool-one-tree "ls -la /mnt/pool_one/ 2>&1; echo ---; ls -la /mnt/pool_one/isos/ 2>&1 | sed -n '1,50p'"

# Unraid user-share view: the standard Unraid VM share is /mnt/user/domains.
run user-share-view "ls -la /mnt/user/ 2>&1 | sed -n '1,40p'; echo ---; ls -la /mnt/user/domains/ 2>&1 | sed -n '1,40p'; echo ---; ls -la /mnt/user/domains/debian13/ 2>&1 2>&1"

# Search every qcow2/vdisk reachable under /mnt (bounded depth, read-only)
run qcow-search "find /mnt -maxdepth 5 \( -name '*.qcow2' -o -name 'vdisk*.img' \) -print 2>/dev/null | sort | head -80"
run debian-file-search "find /mnt -maxdepth 5 -iname '*debian13*' -print 2>/dev/null | head -40; echo ---; find /mnt -maxdepth 5 -iname '*debian12*' -print 2>/dev/null | head -40"

# Exact block-device mapping the domains expect (read-only query)
run domblk-debian13 "sudo virsh domblklist debian13 2>&1; echo ---; sudo virsh domblklist debian12 2>&1"

# Debian 13 install media presence (domain XML boots this ISO as hda)
run debian-iso-presence "ls -la /mnt/pool_one/isos/debian-live-13.5.0-amd64-gnome.iso /mnt/user/isos/debian-live-13.5.0-amd64-gnome.iso 2>&1"

# Occupancy of the debian13/debian12 addresses (are these IPs in use elsewhere?)
run arp-occupancy "ip neigh show 2>&1 | grep -E '192.168.1.120|192.168.1.162' || echo 'no arp entries for .120/.162'"

echo "=== [inspect] summary JSON ==="
cat > "$OUT_DIR/inspection.json" <<JSON
{"hypervisor":"tower","purpose":"debian13 missing-disk diagnosis (issue #14)","ci_job":"${CI_JOB_ID:-0}","ci_pipeline":"${CI_PIPELINE_ID:-0}","ci_commit":"${CI_COMMIT_SHA:-local}","checked_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","mutation":"none (read-only)"}
JSON
cat "$OUT_DIR/inspection.json"
echo "=== inspection done (read-only) ==="
