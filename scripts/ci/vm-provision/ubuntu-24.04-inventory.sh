#!/usr/bin/env bash
# scripts/ci/vm-provision/ubuntu-24.04-inventory.sh
#
# Read-only tower hypervisor inventory for issue #24 (Ubuntu 24.04 VM
# bootstrap, parent #7). Runs on the GitLab runner (on Tower), which has SSH
# access to the tower hypervisor via the runner-mounted /root/.ssh config
# (alias: tower). Strictly read-only:
#   - virsh list --all
#   - per-guest dumpxml summaries (name, disk, interface, agent channel)
#   - storage pools / volumes overview
#   - libvirt networks (br0 attachment facts)
#   - ARP/neighbor table + ping occupancy probe for VM_IP 192.168.1.219
#   - ISO media inventory for Ubuntu images
#
# Emits human logs + a machine-readable JSON record for acceptance evidence.
set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
VM_IP="${VM_IP:-192.168.1.219}"
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
  sudo virsh dumpxml "$d" | grep -E "<name>|<uuid>|<source file=|<source dev=|<source dir=|<interface|<mac |<source bridge=|<source network=|<target dev=|<state|<title|<channel|guest_agent" | head -25
done' | tee "$OUT_DIR/guest-summary.txt" || true

echo "=== [inventory] storage pools ==="
tower "sudo virsh pool-list --all; for p in \$(sudo virsh pool-list --name --all); do echo \"--- pool \$p ---\"; sudo virsh pool-dumpxml \"\$p\" | grep -E '<path>|<name>' | head -4; sudo virsh vol-list \"\$p\" 2>/dev/null | head -40; done" | tee "$OUT_DIR/pools.txt" || true

echo "=== [inventory] libvirt networks ==="
tower "sudo virsh net-list --all; for n in \$(sudo virsh net-list --name --all); do echo \"--- net \$n ---\"; sudo virsh net-dumpxml \"\$n\" | grep -E '<name>|bridge=|<ip |<range|<forward|<interface|<domain' | head -8; done" | tee "$OUT_DIR/networks.txt" || true

echo "=== [inventory] ubuntu2404-named guest detail ==="
tower 'for d in $(sudo virsh list --all --name); do
  case "$d" in *ubuntu*24.04*|*ubuntu2404*|*ubuntu-24.04*|*ubuntu24.04*) echo "===== $d ====="; sudo virsh dumpxml "$d";; esac
done' > "$OUT_DIR/ubuntu2404-guest-dumpxml.txt" || true
wc -l "$OUT_DIR/ubuntu2404-guest-dumpxml.txt"

echo "=== [inventory] ISO media inventory (Ubuntu images) ==="
tower "ls -la /mnt/user/isos/ 2>/dev/null | grep -i ubuntu || echo '(no ubuntu ISOs in /mnt/user/isos)'; ls -la /mnt/pool_one/isos/ 2>/dev/null | grep -i ubuntu || echo '(no ubuntu ISOs in /mnt/pool_one/isos)'; find /mnt/pool_one/isos /mnt/user/isos -maxdepth 2 -iname '*ubuntu*24*' -type f 2>/dev/null | head -20" | tee "$OUT_DIR/iso-inventory.txt" || true

echo "=== [inventory] $VM_IP occupancy probe (arp + ping, read-only) ==="
tower "ip neigh show | grep -i '$VM_IP' || echo 'no arp entry'; ping -c1 -W2 '$VM_IP' >/dev/null 2>&1 && echo 'PING: $VM_IP answers' || echo 'PING: $VM_IP silent'" | tee "$OUT_DIR/ip-occupancy.txt" || true

# Structured summary record
GUEST_COUNT=$(grep -cE '^ [0-9]+ +[a-zA-Z0-9._-]+ ' "$OUT_DIR/virsh-list.txt" 2>/dev/null || echo 0)
UBUNTU_NAMES=$(grep -iE 'ubuntu' "$OUT_DIR/virsh-list.txt" 2>/dev/null | awk '{print $2}' | tr '\n' ',' || echo "")
IP_ANSWERS=$(grep -c 'answers' "$OUT_DIR/ip-occupancy.txt" 2>/dev/null || echo 0)
UBUNTU_DUMXML_LINES=$(wc -l < "$OUT_DIR/ubuntu2404-guest-dumpxml.txt" 2>/dev/null || echo 0)

cat > "$OUT_DIR/inventory.json" <<JSON
{"hypervisor":"tower","checked_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","vm_ip":"$VM_IP","guest_count_hint":$GUEST_COUNT,"ubuntu_named_guests":"${UBUNTU_NAMES}","ubuntu2404_guest_dumxml_lines":$UBUNTU_DUMXML_LINES,"ip_answers_ping":$IP_ANSWERS,"ci_job":"${CI_JOB_ID:-0}","ci_pipeline":"${CI_PIPELINE_ID:-0}","ci_commit":"${CI_COMMIT_SHA:-local}"}
JSON

echo "=== inventory done ==="
exit 0
