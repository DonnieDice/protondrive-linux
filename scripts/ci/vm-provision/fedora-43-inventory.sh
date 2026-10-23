#!/usr/bin/env bash
# scripts/ci/vm-provision/fedora-43-inventory.sh
#
# Read-only tower hypervisor inventory for issue #18 (Fedora 43 VM
# bootstrap, parent #12). Runs on the GitLab runner (on Tower), which has SSH
# access to the tower hypervisor via the runner-mounted /root/.ssh config
# (alias: tower). Strictly read-only:
#   - virsh list --all
#   - per-guest dumpxml summaries (name, disk, interface, agent channel)
#   - full dumpxml for any fedora-43-named guest (if any)
#   - qemu-img info for any fedora-43 disk found
#   - storage pools / volumes overview
#   - libvirt networks (br0 attachment facts)
#   - ARP/neighbor table + ping occupancy probe for VM_IP 192.168.1.183
#   - ISO media inventory for Fedora images
#
# Emits human logs + a machine-readable JSON record for acceptance evidence.
set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
VM_IP="${VM_IP:-192.168.1.183}"
OUT_DIR="${INVENTORY_OUT_DIR:-inventory-results}"
mkdir -p "$OUT_DIR"

VM_KNOWN_HOSTS="${CI_PROJECT_DIR:-.}/.vm-known-hosts"
: >"$VM_KNOWN_HOSTS"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$VM_KNOWN_HOSTS"

tower() { ssh $SSH_OPTS "$TOWER_HOST" "$@"; }

echo "=== [inventory] tower identity ==="
tower "hostname; whoami; date -u" | tee "$OUT_DIR/identity.txt" || {
  echo "FATAL: cannot reach tower"
  exit 1
}

echo "=== [inventory] virsh list --all ==="
tower "sudo virsh list --all" | tee "$OUT_DIR/virsh-list.txt" || echo "(virsh list failed - recording)"

echo "=== [inventory] all guest dumpxml name/disk/interface summary ==="
tower 'for d in $(sudo virsh list --all --name); do
  echo "--- $d ---"
  sudo virsh dumpxml "$d" | grep -E "<name>|<uuid>|<source file=|<source dev=|<source dir=|<interface|<mac |<source bridge=|<target dev=|<state|<title|<channel|guest_agent" | head -25
done' | tee "$OUT_DIR/guest-summary.txt" || true

echo "=== [inventory] fedora-43-named guest detail (full dumpxml) ==="
tower 'for d in $(sudo virsh list --all --name); do
  case "$d" in *fedora*|*fedora43*|*fedora-43*|*f43*) echo "===== $d ====="; sudo virsh dumpxml "$d";; esac
done' >"$OUT_DIR/fedora43-guest-dumpxml.txt" || true
wc -l "$OUT_DIR/fedora43-guest-dumpxml.txt" | tee "$OUT_DIR/fedora43-dumpxml-linecount.txt"

echo "=== [inventory] fedora-43 disk qemu-img info (if any guests found) ==="
tower 'for d in $(sudo virsh list --all --name); do
  case "$d" in *fedora*|*fedora43*|*fedora-43*|*f43*)
    echo "--- $d disks ---"
    sudo virsh dumpxml "$d" | grep -oE "<source file=.[^ >]*>" | sed "s/<source file=.//;s/.$//" | while read -r disk; do
      echo "disk: $disk"
      sudo qemu-img info "$disk" 2>/dev/null || echo "  (qemu-img info failed for $disk)"
    done
  ;; esac
done' | tee "$OUT_DIR/disk-info.txt" || true

echo "=== [inventory] storage pools ==="
tower 'sudo virsh pool-list --all; for p in $(sudo virsh pool-list --name --all); do echo "--- pool $p ---"; sudo virsh pool-dumpxml "$p" | grep -E "<path>|<name>" | head -4; sudo virsh vol-list "$p" 2>/dev/null | head -40; done' | tee "$OUT_DIR/pools.txt" || true

echo "=== [inventory] libvirt networks ==="
tower 'sudo virsh net-list --all; for n in $(sudo virsh net-list --name --all); do echo "--- net $n ---"; sudo virsh net-dumpxml "$n" | grep -E "<name>|bridge=|<ip |<range" | head -8; done' | tee "$OUT_DIR/networks.txt" || true

echo "=== [inventory] ISO media inventory (Fedora images) ==="
# Fedora ISOs typically live in /mnt/pool_one/isos/ on the tower (same pool
# as the CentOS Stream ISO used by the el10 inventory job).
tower "ls -la /mnt/pool_one/isos/ 2>/dev/null | grep -i -E 'fedora|F43|F42' || echo '(no Fedora ISOs in /mnt/pool_one/isos)'; ls -la /mnt/user/isos/ 2>/dev/null | grep -i -E 'fedora|F43|F42' || echo '(no Fedora ISOs in /mnt/user/isos)'; find /mnt/pool_one /mnt/pool_two /mnt/user -maxdepth 3 -iname 'Fedora*' -type f 2>/dev/null | head -20" | tee "$OUT_DIR/iso-inventory.txt" || true

echo "=== [inventory] $VM_IP occupancy probe (arp + ping, read-only) ==="
tower "ip neigh show | grep -i '$VM_IP' || echo 'no arp entry'; ping -c1 -W2 '$VM_IP' >/dev/null 2>&1 && echo 'PING: $VM_IP answers' || echo 'PING: $VM_IP silent'" | tee "$OUT_DIR/ip-occupancy.txt" || true

# Structured summary record
F43_NAMES=$(grep -iE 'fedora|fedora43|fedora-43|f43' "$OUT_DIR/virsh-list.txt" 2>/dev/null | awk '{print $2}' | tr '\n' ',')
GUEST_COUNT=$(grep -cE '^ [0-9]+ +[a-zA-Z0-9._-]+ ' "$OUT_DIR/virsh-list.txt" 2>/dev/null || echo 0)
IP_ANSWERS=$(grep -c "answers" "$OUT_DIR/ip-occupancy.txt" 2>/dev/null || echo 0)
DUMpxML_LINES=$(wc -l <"$OUT_DIR/fedora43-guest-dumpxml.txt" 2>/dev/null || echo 0)

cat >"$OUT_DIR/inventory.json" <<JSON
{"hypervisor":"tower","checked_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","vm_ip":"$VM_IP","guest_count_hint":$GUEST_COUNT,"fedora43_named_guests":"${F43_NAMES}","fedora43_dumpxml_lines":${DUMpxML_LINES:-0},"ip_answers_ping":$IP_ANSWERS,"ci_job":"${CI_JOB_ID:-0}","ci_pipeline":"${CI_PIPELINE_ID:-0}","ci_commit":"${CI_COMMIT_SHA:-local}"}
JSON
cat "$OUT_DIR/inventory.json"

echo "=== inventory done ==="
exit 0
