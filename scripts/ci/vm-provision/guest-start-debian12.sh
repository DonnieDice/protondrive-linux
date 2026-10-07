#!/usr/bin/env bash
# scripts/ci/vm-provision/guest-start-debian12.sh
#
# Authorized host operation for issue #15 (scope item 2): start the debian12
# guest on the tower hypervisor so the #15 evidence jobs (vm:ssh:reachability,
# vm:install:pkg:debian12, vm:pytest:debian12, vm:login:debian12) can reach it.
# The tower inventory job (25523, pipeline 2258, 2026-09-28 08:16Z) proved every
# guest including debian12 is shut off, which is the single root cause of the
# "Host is unreachable" failures in jobs 26037/26084 (pipeline 2272).
#
# Transport: the runner-mounted /root/.ssh config (alias: tower) — the same
# transport the successful inventory job 25523 used. This script performs
# exactly one authorized lifecycle action on exactly one guest:
#   - virsh start debian12
# and then records read-only evidence of the resulting state:
#   - virsh list --all, virsh dominfo debian12, ARP entry, SSH probe of
#     192.168.1.162 from the runner.
#
# No other guest is touched (debian13 is owned by #14; coordination note
# 12271 was posted there before this job ran). No define/undefine mutation.
# Before starting, the script verifies (read-only) that the domain's backing
# disk exists so a broken domain definition fails fast with clear evidence
# instead of a mysterious boot failure.

set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
GUEST="debian12"
VM_IP="192.168.1.162"
OUT_DIR="${GUEST_START_OUT_DIR:-guest-start-results}"
mkdir -p "$OUT_DIR"

VM_KNOWN_HOSTS="${CI_PROJECT_DIR:-.}/.vm-known-hosts"
: > "$VM_KNOWN_HOSTS"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$VM_KNOWN_HOSTS"

tower() { ssh $SSH_OPTS "$TOWER_HOST" "$@"; }
vm() { ssh $SSH_OPTS "$VM_IP" "$@" 2>/dev/null; }

echo "=== [guest-start] tower identity ==="
tower "hostname; whoami; date -u" | tee "$OUT_DIR/identity.txt" || { echo "FATAL: cannot reach tower"; exit 1; }

echo "=== [guest-start] pre-start state (read-only) ==="
tower "sudo virsh list --all" | tee "$OUT_DIR/virsh-list-before.txt"

echo "=== [guest-start] backing disk existence (read-only) ==="
DISK_PATH="$(tower "sudo virsh dumpxml '$GUEST' | grep -o \"source file='[^']*'\" | head -1 | cut -d\\' -f2")"
echo "domain disk path: ${DISK_PATH:-<none found>}" | tee "$OUT_DIR/disk-path.txt"
if [ -n "${DISK_PATH:-}" ]; then
  tower "sudo ls -la '$DISK_PATH'" | tee "$OUT_DIR/disk-exists.txt" || {
    echo "FATAL: backing disk $DISK_PATH missing on tower; not attempting start (domain definition likely broken, as observed for debian13 on #14)"
    exit 3
  }
  tower "sudo qemu-img info '$DISK_PATH' | head -6" | tee "$OUT_DIR/disk-info.txt" || true
fi

echo "=== [guest-start] authorized operation: virsh start $GUEST ==="
if tower "sudo virsh start '$GUEST'"; then
  echo "START: issued virsh start for $GUEST"
else
  echo "NOTE: virsh start returned nonzero (guest may already be running) — recording state"
fi | tee "$OUT_DIR/start-output.txt"

# Wait for the guest to boot and acquire its IP: poll SSH reachability from
# the runner (the same path the evidence jobs use), bounded at ~5 minutes.
echo "=== [guest-start] waiting for $GUEST ($VM_IP) to answer SSH ==="
UP=0
for i in $(seq 1 30); do
  if vm "true" 2>/dev/null; then
    UP=1
    echo "SSH: $VM_IP reachable after attempt $i"
    break
  fi
  sleep 10
done
echo "ssh_reachable_after_polls=$UP" | tee "$OUT_DIR/ssh-probe.txt"
[ "$UP" = "1" ] || { echo "WARN: $VM_IP did not answer SSH within 300s — recording state for diagnosis"; }

echo "=== [guest-start] post-start state (read-only evidence) ==="
tower "sudo virsh list --all; echo ---; sudo virsh dominfo '$GUEST'" | tee "$OUT_DIR/virsh-dominfo-after.txt"
tower "ip neigh show | grep -i '$VM_IP' || echo 'no arp entry yet'" | tee "$OUT_DIR/arp-after.txt"

cat > "$OUT_DIR/guest-start.json" <<JSON
{"hypervisor":"tower","guest":"$GUEST","vm_ip":"$VM_IP","operation":"virsh start","ssh_reachable":$UP,"checked_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","ci_job":"${CI_JOB_ID:-0}","ci_pipeline":"${CI_PIPELINE_ID:-0}","ci_commit":"${CI_COMMIT_SHA:-local}"}
JSON
cat "$OUT_DIR/guest-start.json"

if [ "$UP" = "1" ]; then
  echo "=== GUEST STARTED AND REACHABLE ==="
  exit 0
else
  echo "=== GUEST START ISSUED BUT NOT YET SSH-REACHABLE ==="
  exit 2
fi
