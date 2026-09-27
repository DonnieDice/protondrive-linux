#!/usr/bin/env bash
# scripts/ci/vm-provision/el10-inventory.sh
#
# Read-only tower hypervisor inventory for issue #19 (EL10 / CentOS Stream 10
# VM bootstrap, parent #11). Runs on the GitLab runner (on Tower), which has
# SSH access to the tower hypervisor via the runner-mounted /root/.ssh config
# (alias: tower). Strictly read-only:
#   - virsh list --all
#   - per-guest dumpxml summaries (name, disk, interface, agent channel)
#   - full dumpxml for the el10 guest
#   - qemu-img info for the el10 disk
#   - ISO media inventory for CentOS Stream images
#   - ARP/neighbor table + ping occupancy probe for VM_IP 192.168.1.123
#
# Emits human logs + a machine-readable JSON record for acceptance evidence.
set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
VM_IP="${VM_IP:-192.168.1.123}"
OUT_DIR="${INVENTORY_OUT_DIR:-inventory-results}"
mkdir -p "$OUT_DIR"

VM_KNOWN_HOSTS="${CI_PROJECT_DIR:-.}/.vm-known-hosts"
: > "$VM_KNOWN_HOSTS"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$VM_KNOWN_HOSTS"

tower() { ssh $SSH_OPTS "$TOWER_HOST" "$@"; }

echo "=== [inventory] tower identity ==="
tower "hostname; whoami; date -u" | tee "$OUT_DIR/identity.txt" || { echo "FATAL: cannot reach tower"; exit 1; }

echo "=== [inventory] virsh list --all ==="
tower "sudo virsh list --all" | tee "$OUT_DIR/virsh-list.txt" || echo "(virsh list failed - recording)"

echo "=== [inventory] all guest dumpxml name/disk/interface summary ==="
tower 'for d in $(sudo virsh list --all --name); do
  echo "--- $d ---"
  sudo virsh dumpxml "$d" | grep -E "<name>|<uuid>|<source file=|<source dev=|<source dir=|<interface|<mac |<source bridge=|<target dev=|<state|<title" | head -25
done' | tee "$OUT_DIR/guest-summary.txt" || true

echo "=== [inventory] el10 guest detail (full dumpxml) ==="
tower 'sudo virsh dumpxml el10 2>/dev/null' > "$OUT_DIR/el10-guest-dumpxml.txt" || true
wc -l "$OUT_DIR/el10-guest-dumpxml.txt"

echo "=== [inventory] el10 disk qemu-img info ==="
tower "sudo qemu-img info /mnt/pool_two/domains/el10/vdisk1.qcow2 2>/dev/null" | tee "$OUT_DIR/el10-disk-info.txt" || echo "(qemu-img info failed - recording)"
tower "ls -la /mnt/pool_two/domains/el10/ 2>/dev/null" | tee "$OUT_DIR/el10-disk-dir.txt" || true

echo "=== [inventory] ISO media inventory (centos/stream images) ==="
tower "ls -la /mnt/pool_one/isos/ 2>/dev/null | grep -iE 'centos|stream' || echo '(no centos/stream ISOs in /mnt/pool_one/isos)'; find /mnt/pool_one/isos /mnt/user/isos -maxdepth 2 -iname '*centos*' -o -iname '*stream*' 2>/dev/null | head -10" | tee "$OUT_DIR/iso-inventory.txt" || true

echo "=== [inventory] libvirt networks ==="
tower "sudo virsh net-list --all; for n in \$(sudo virsh net-list --name --all); do echo \"--- net \$n ---\"; sudo virsh net-dumpxml \"\$n\" | grep -E '<name>|bridge=|<ip |<range' | head -8; done" | tee "$OUT_DIR/networks.txt" || true

echo "=== [inventory] $VM_IP occupancy probe (arp + ping, read-only) ==="
tower "ip neigh show | grep -i '$VM_IP' || echo 'no arp entry'; ping -c1 -W2 '$VM_IP' >/dev/null 2>&1 && echo 'PING: $VM_IP answers' || echo 'PING: $VM_IP silent'" | tee "$OUT_DIR/ip-occupancy.txt" || true

# Structured summary record
EL10_DEFINED=$(grep -c '<name>el10</name>' "$OUT_DIR/el10-guest-dumpxml.txt" 2>/dev/null || echo 0)
GUEST_COUNT=$(grep -cE '^ [0-9]+ +[a-zA-Z0-9._-]+ ' "$OUT_DIR/virsh-list.txt" 2>/dev/null || echo 0)
IP_ANSWERS=$(grep -c 'PING: .*answers' "$OUT_DIR/ip-occupancy.txt" 2>/dev/null || echo 0)

cat > "$OUT_DIR/inventory.json" <<JSON
{"hypervisor":"tower","checked_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","vm_ip":"$VM_IP","guest_count_hint":$GUEST_COUNT,"el10_defined":$EL10_DEFINED,"ip_answers_ping":$IP_ANSWERS,"ci_job":"${CI_JOB_ID:-0}","ci_pipeline":"${CI_PIPELINE_ID:-0}","ci_commit":"${CI_COMMIT_SHA:-local}"}
JSON
cat "$OUT_DIR/inventory.json"

echo "=== inventory done ==="
exit 0
