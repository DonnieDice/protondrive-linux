#!/usr/bin/env bash
# scripts/ci/vm-provision/arch-inventory.sh
#
# Read-only tower hypervisor inventory for issue #23 (Arch VM br0 migration,
# parent #10) on the tower hypervisor(192.168.1.31). Runs on the GitLab runner
# (tags: [android]), which reaches tower via the runner-mounted /root/.ssh config
# (alias: tower). Strictly read-only:
#   - virsh list --all
#   - per-guest dumpxml summaries (name, disk, interface, agent channel)
#   - full dumpxml for the arch guest
#   - ARP/neighbor table + ping occupancy probe for VM_IP 192.168.1.128
#   - libvirt network listing (br0, default/NAT)
#
# No mutation of any guest, domain, disk, or host service.
#
# Preconditions: the runner-mounted /root/.ssh provides the `tower` alias with
# the workforce key authorized for root on the hypervisor (verified by sibling
# inventory jobs 22933, 30239 and the dispatcher's gate-policy note 7599 on #23).
set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
GUEST="${GUEST:-arch}"
VM_IP="${VM_IP:-192.168.1.128}"
TOWER_IP="${TOWER_IP:-192.168.1.31}"
OUT_DIR="${INVENTORY_OUT_DIR:-inventory-results}"
mkdir -p "$OUT_DIR"

VM_KNOWN_HOSTS="${CI_PROJECT_DIR:-.}/.vm-known-hosts"
: > "$VM_KNOWN_HOSTS"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$VM_KNOWN_HOSTS"

tower() { ssh $SSH_OPTS "$TOWER_HOST" "$@"; }
log() { echo "[inventory] $*"; }

echo "=== [inventory] tower identity ==="
tower "hostname; whoami; date -u" | tee "$OUT_DIR/identity.txt" || { echo "FATAL: cannot reach tower"; exit 1; }

echo "=== [inventory] virsh list --all ==="
tower "sudo virsh list --all" | tee "$OUT_DIR/virsh-list.txt" || echo "(virsh list failed - recording)"

echo "=== [inventory] all guest dumpxml name/disk/interface summary ==="
tower 'for d in $(sudo virsh list --all --name); do
  echo "--- $d ---"
  sudo virsh dumpxml "$d" | grep -E "<name>|<uuid>|<source file=|<source dev=|<source dir=|<interface|<mac |<source bridge=|<source network=|<target dev=|<state|<title|<channel" | head -25
done' | tee "$OUT_DIR/guest-summary.txt" || true

echo "=== [inventory] arch guest detail (full dumpxml) ==="
tower 'sudo virsh dumpxml arch 2>/dev/null' > "$OUT_DIR/arch-guest-dumpxml.txt" || true
wc -l "$OUT_DIR/arch-guest-dumpxml.txt"

echo "=== [inventory] arch disk qemu-img info ==="
# Try common domain locations for the arch guest disk
ARCH_DISK_PATHS=(
  "/mnt/pool_two/domains/arch/vdisk1.qcow2"
  "/mnt/pool_two/domains/arch/arch.qcow2"
  "/mnt/user/domains/arch/vdisk1.qcow2"
  "/mnt/user/domains/arch/arch.qcow2"
  "/var/lib/libvirt/images/arch.qcow2"
  "/var/lib/libvirt/images/arch/vdisk1.qcow2"
)
DISK_FOUND=""
for p in "${ARCH_DISK_PATHS[@]}"; do
  if tower "test -s '$p'" 2>/dev/null; then
    DISK_FOUND="$p"
    break
  fi
done
if [ -n "$DISK_FOUND" ]; then
  tower "sudo qemu-img info '$DISK_FOUND'" | tee "$OUT_DIR/arch-disk-info.txt" || echo "(qemu-img info failed - recording)"
  tower "ls -la '$(dirname "$DISK_FOUND")/'" | tee "$OUT_DIR/arch-disk-dir.txt" || true
  echo "DISK_PATH=$DISK_FOUND" | tee -a "$OUT_DIR/arch-disk-info.txt"
else
  echo "arch disk not found at any known path" | tee "$OUT_DIR/arch-disk-info.txt"
  # Search broadly for arch-related disk files
  tower "find /mnt/pool_one /mnt/pool_two /mnt/user /var/lib/libvirt -maxdepth 4 -iname '*arch*' -name '*.qcow2' 2>/dev/null; true" | tee "$OUT_DIR/arch-disk-dir.txt" || true
fi

echo "=== [inventory] libvirt networks ==="
tower "sudo virsh net-list --all; for n in \$(sudo virsh net-list --name --all); do echo \"--- net \$n ---\"; sudo virsh net-dumpxml \"\$n\" | grep -E '<name>|bridge=|domain|<ip |<range' | head -8; done" | tee "$OUT_DIR/networks.txt" || true

echo "=== [inventory] $VM_IP occupancy probe (arp + ping, read-only) ==="
tower "ip neigh show | grep -i '$VM_IP' || echo 'no arp entry'; ping -c1 -W2 '$VM_IP' >/dev/null 2>&1 && echo 'PING: $VM_IP answers' || echo 'PING: $VM_IP silent'" | tee "$OUT_DIR/ip-occupancy.txt" || true

echo "=== [inventory] SSH probe (read-only, expected to fail pre-migration) ==="
tower "ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes '$VM_IP' 'uname -a' 2>&1 || echo 'SSH_PROBE: arch VM not yet SSH-reachable'" | tee "$OUT_DIR/ssh-probe.txt" || true

# Structured summary record
ARCH_DEFINED=$(grep -c '<name>arch</name>' "$OUT_DIR/arch-guest-dumpxml.txt" 2>/dev/null || echo 0)
GUEST_COUNT=$(grep -cE '^ [0-9]+ +[a-zA-Z0-9._-]+ ' "$OUT_DIR/virsh-list.txt" 2>/dev/null || echo 0)
IP_ANSWERS=$(grep -c 'PING: .*answers' "$OUT_DIR/ip-occupancy.txt" 2>/dev/null || echo 0)
ARCH_ON_BR0=$(grep -c 'source bridge=.br0' "$OUT_DIR/arch-guest-dumpxml.txt" 2>/dev/null || echo 0)
ARCH_ON_DEFAULT=$(grep -c 'source network=.default' "$OUT_DIR/arch-guest-dumpxml.txt" 2>/dev/null || echo 0)

cat > "$OUT_DIR/inventory.json" <<JSON
{"hypervisor":"tower","guest":"$GUEST","vm_ip":"$VM_IP","checked_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","guest_count_hint":$GUEST_COUNT,"arch_defined":$ARCH_DEFINED,"arch_on_br0":$ARCH_ON_BR0,"arch_on_default_nat":$ARCH_ON_DEFAULT,"ip_answers_ping":$IP_ANSWERS,"ci_job":"${CI_JOB_ID:-0}","ci_pipeline":"${CI_PIPELINE_ID:-0}","ci_commit":"${CI_COMMIT_SHA:-local}"}
JSON
cat "$OUT_DIR/inventory.json"

echo "=== inventory done ==="
exit 0
