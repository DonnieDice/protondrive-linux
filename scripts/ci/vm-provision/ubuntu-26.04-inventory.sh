#!/usr/bin/env bash
# scripts/ci/vm-provision/ubuntu-26.04-inventory.sh
#
# Read-only tower hypervisor inventory for issue #20 (Ubuntu 26.04 VM
# bootstrap, parent #8). Runs on the GitLab runner (on Tower), which has SSH
# access to the tower hypervisor via the runner-mounted /root/.ssh config
# (alias: tower). Strictly read-only:
#   - virsh list --all
#   - per-guest dumpxml summaries (name, disk, interface, agent channel)
#   - full dumpxml for any ubuntu2604-named guest
#   - qemu-img info for the ubuntu2604 disk
#   - ISO media inventory for Ubuntu 26.04 images
#   - ARP/neighbor table + ping occupancy probe for VM_IP 192.168.1.168
#
# Emits human logs + a machine-readable JSON record for acceptance evidence.
set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
VM_IP="${VM_IP:-192.168.1.168}"
GUEST="${GUEST:-ubuntu-2604}"
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
  sudo virsh dumpxml "$d" | grep -E "<name>|<uuid>|<source file=|<source dev=|<source dir=|<interface|<mac |<source bridge=|<target dev=|<state|<title|<channel|guest_agent" | head -25
done' | tee "$OUT_DIR/guest-summary.txt" || true

echo "=== [inventory] ubuntu2604 guest detail (full dumpxml) ==="
tower "sudo virsh dumpxml '$GUEST' 2>/dev/null" > "$OUT_DIR/ubuntu2604-guest-dumpxml.txt" || true
wc -l "$OUT_DIR/ubuntu2604-guest-dumpxml.txt"

echo "=== [inventory] ubuntu2604 disk qemu-img info ==="
# The canonical disk path matches tests/robot/vars/vms.py and the sibling install jobs
DISK_PATH="/mnt/pool_two/domains/ubuntu-26.04/vdisk1.qcow2"
tower "sudo qemu-img info '$DISK_PATH' 2>/dev/null" | tee "$OUT_DIR/ubuntu2604-disk-info.txt" || echo "(qemu-img info failed - recording)"
tower "ls -la /mnt/pool_two/domains/ubuntu-26.0.4/ 2>/dev/null; ls -la /mnt/pool_two/domains/ubuntu-26.04/ 2>/dev/null; echo '---'; find /mnt/pool_one /mnt/pool_two /mnt/user -maxdepth 3 -iname '*ubuntu*26*' -type f 2>/dev/null" | tee "$OUT_DIR/ubuntu2604-disk-dir.txt" || true

echo "=== [inventory] ISO media inventory (Ubuntu 26.04 images) ==="
tower "ls -la /mnt/pool_one/isos/ 2>/dev/null | grep -iE 'ubuntu|26.04|noble' || echo '(no Ubuntu ISOs in /mnt/pool_one/isos)'; ls -la /mnt/user/isos/ 2>/dev/null | grep -iE 'ubuntu|26.04|noble' || echo '(no Ubuntu ISOs in /mnt/user/isos)'; find /mnt/pool_one /mnt/pool_two /mnt/user -maxdepth 3 -iname 'ubuntu*26*' -type f 2>/dev/null | head -20" | tee "$OUT_DIR/iso-inventory.txt" || true

echo "=== [inventory] libvirt networks ==="
tower "sudo virsh net-list --all; for n in \$(sudo virsh net-list --name --all); do echo \"--- net \$n ---\"; sudo virsh net-dumpxml \"\$n\" | grep -E '<name>|bridge=|<ip |<range' | head -8; done" | tee "$OUT_DIR/networks.txt" || true

echo "=== [inventory] $VM_IP occupancy probe (arp + ping, read-only) ==="
tower "ip neigh show | grep -i '$VM_IP' || echo 'no arp entry'; ping -c1 -W2 '$VM_IP' >/dev/null 2>&1 && echo 'PING: $VM_IP answers' || echo 'PING: $VM_IP silent'" | tee "$OUT_DIR/ip-occupancy.txt" || true

# Structured summary record
UBUNTU_DEFINED=$(grep -c '<name>ubuntu-26.04</name>\|<name>ubuntu2604</name>\|<name>ubuntu.26.04</name>' "$OUT_DIR/ubuntu2604-guest-dumpxml.txt" 2>/dev/null || echo 0)
GUEST_COUNT=$(grep -cE '^ [0-9]+ +[a-zA-Z0-9._-]+ ' "$OUT_DIR/virsh-list.txt" 2>/dev/null || echo 0)
IP_ANSWERS=$(grep -c 'answers' "$OUT_DIR/ip-occupancy.txt" 2>/dev/null || echo 0)
UBUNTU_NAMES=$(grep -iE 'ubuntu' "$OUT_DIR/virsh-list.txt" | awk '{print $2}' | tr '\n' ',' || echo "")

cat > "$OUT_DIR/inventory.json" <<JSON
{"hypervisor":"tower","checked_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","vm_ip":"$VM_IP","guest_count_hint":$GUEST_COUNT,"ubuntu2604_guest_defined":$UBUNTU_DEFINED,"ubuntu_named_guests":"${UBUNTU_NAMES}","ip_answers_ping":$IP_ANSWERS,"ci_job":"${CI_JOB_ID:-0}","ci_pipeline":"${CI_PIPELINE_ID:-0}","ci_commit":"${CI_COMMIT_SHA:-local}"}
JSON
cat "$OUT_DIR/inventory.json"

echo "=== inventory done ==="
exit 0
