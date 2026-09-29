#!/usr/bin/env bash
# scripts/ci/vm-provision/diag-vm-network.sh
#
# Read-only network diagnostics for issue #15: explain why debian12
# (192.168.1.162) and debian13 (192.168.1.120) are not SSH-reachable even
# though both domains show state=running (repair job 26734, pipeline 2297).
#
# Evidence collected (all read-only):
#   - virsh list --all (current power state)
#   - virsh domifaddr <guest> --source agent  (guest-agent IP report)
#   - virsh domifaddr <guest> --source arp    (host ARP table lookup)
#   - ip neigh show on the tower (MAC -> IP resolution for br0)
#   - dumpxml boot order + MAC + disk/cdrom layout
#   - guest-agent channel connection state
#
# No mutation of any guest, domain, or disk.

set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
OUT_DIR="${DIAG_OUT_DIR:-diag-results}"
mkdir -p "$OUT_DIR"

VM_KNOWN_HOSTS="${CI_PROJECT_DIR:-.}/.vm-known-hosts"
: > "$VM_KNOWN_HOSTS"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$VM_KNOWN_HOSTS"

tower() { ssh $SSH_OPTS "$TOWER_HOST" "$@"; }

echo "=== [diag] tower identity ==="
tower "hostname; whoami; date -u" | tee "$OUT_DIR/identity.txt" || { echo "FATAL: cannot reach tower"; exit 1; }

echo "=== [diag] guest power state ==="
tower "sudo virsh list --all" | tee "$OUT_DIR/virsh-list.txt"

for GUEST in debian12 debian13; do
  echo "=== [diag] $GUEST: domifaddr (agent + arp) ==="
  tower "sudo virsh domifaddr '$GUEST' --source agent 2>&1" | tee "$OUT_DIR/domifaddr-agent-$GUEST.txt"
  tower "sudo virsh domifaddr '$GUEST' --source arp 2>&1" | tee "$OUT_DIR/domifaddr-arp-$GUEST.txt"

  echo "=== [diag] $GUEST: boot order + MAC + disk layout ==="
  tower "sudo virsh dumpxml '$GUEST' | grep -E \"boot order=|<mac address=|<source file=|device='(disk|cdrom)'|state=\"\"connected\"\"\"" | tee "$OUT_DIR/layout-$GUEST.txt"

  echo "=== [diag] $GUEST: guest-agent channel state ==="
  tower "sudo virsh dumpxml '$GUEST' | grep -A1 'org.qemu.guest_agent'" | tee "$OUT_DIR/agent-channel-$GUEST.txt"
done

echo "=== [diag] tower ARP/neigh table (br0) ==="
tower "ip neigh show | grep -v FAILED" | tee "$OUT_DIR/ip-neigh.txt"

echo "=== [diag] MAC address cross-reference ==="
D12_MAC="$(tower "sudo virsh dumpxml debian12 | grep -o \"<mac address='[^']*'\" | cut -d\\' -f2")"
D13_MAC="$(tower "sudo virsh dumpxml debian13 | grep -o \"<mac address='[^']*'\" | cut -d\\' -f2")"
echo "debian12 mac: $D12_MAC" | tee "$OUT_DIR/macs.txt"
echo "debian13 mac: $D13_MAC" | tee -a "$OUT_DIR/macs.txt"
tower "ip neigh show | grep -i \"${D12_MAC:-none}\"" | tee "$OUT_DIR/neigh-debian12.txt" || true
tower "ip neigh show | grep -i \"${D13_MAC:-none}\"" | tee "$OUT_DIR/neigh-debian13.txt" || true

echo "=== [diag] done (read-only) ==="
