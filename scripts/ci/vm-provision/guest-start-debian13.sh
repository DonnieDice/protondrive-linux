#!/usr/bin/env bash
# scripts/ci/vm-provision/guest-start-debian13.sh
#
# Authorized host operation for issue #14 (scope item 2): start the debian13
# guest on the tower hypervisor so the toolchain provisioning/verify jobs
# can reach it. The tower inventory job (24251, pipeline 2138, 2026-09-27
# 19:02Z) proved every guest including debian13 is shut off, which is the
# single root cause of the "Host is unreachable" failures in pipeline 2129
# jobs 24128/23859.
#
# Transport: the runner-mounted /root/.ssh config (alias: tower) — the same
# read-only transport the successful inventory job 24251 used. This script
# performs exactly one authorized lifecycle action on exactly one guest:
#   - virsh start debian13
# and then records read-only evidence of the resulting state:
#   - virsh list --all, virsh dominfo debian13, ARP entry, SSH probe of
#     192.168.1.120 from the runner.
#
# No other guest is touched. No define/undefine/disk/network mutation.

set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
GUEST="debian13"
VM_IP="192.168.1.120"
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

echo "=== [guest-start] authorized operation: virsh start $GUEST ==="
if tower "sudo virsh start '$GUEST'"; then
  echo "START: issued virsh start for $GUEST"
else
  echo "NOTE: virsh start returned nonzero (guest may already be running) — recording state"
fi | tee "$OUT_DIR/start-output.txt"

# Wait for the guest to boot and acquire its IP: poll SSH reachability from
# the runner (the same path the provision/verify jobs use), bounded at ~5
# minutes; typical libvirt+Debian boot on this host is well under that.
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
