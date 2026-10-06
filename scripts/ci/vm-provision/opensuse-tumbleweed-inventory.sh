#!/usr/bin/env bash
# scripts/ci/vm-provision/opensuse-tumbleweed-inventory.sh
#
# Read-only tower hypervisor inventory for issue #17 (openSUSE Tumbleweed VM
# bootstrap, parent #9). Runs on the GitLab runner (on Tower), which has SSH
# access to the tower hypervisor via the runner-mounted /root/.ssh config
# (alias: tower). Strictly read-only:
#   - virsh list --all
#   - per-guest dumpxml summaries (name, disk, interface, agent channel)
#   - storage pools / volumes overview
#   - libvirt networks (br0 attachment facts)
#   - ARP/neighbor table + ping occupancy probe for VM_IP 192.168.1.245
#   - ISO media inventory for openSUSE images
#
# Emits human logs + a machine-readable JSON record for acceptance evidence.
set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
VM_IP="${VM_IP:-192.168.1.245}"
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

echo "=== [inventory] storage pools ==="
tower 'sudo virsh pool-list --all; for p in $(sudo virsh pool-list --name --all); do echo "--- pool $p ---"; sudo virsh pool-dumpxml "$p" | grep -E "<path>|<name>" | head -4; sudo virsh vol-list "$p" 2>/dev/null | head -40; done' | tee "$OUT_DIR/pools.txt" || true

echo "=== [inventory] libvirt networks ==="
tower 'sudo virsh net-list --all; for n in $(sudo virsh net-list --name --all); do echo "--- net $n ---"; sudo virsh net-dumpxml "$n" | grep -E "<name>|bridge=|<ip |<range" | head -8; done' | tee "$OUT_DIR/networks.txt" || true

echo "=== [inventory] opensuse-tumbleweed-named guest detail ==="
tower 'for d in $(sudo virsh list --all --name); do
  case "$d" in *opensuse*|*tumbleweed*|*opensuse-tumbleweed*|*opensuse-tw*|*osuse*) echo "===== $d ====="; sudo virsh dumpxml "$d";; esac
done' > "$OUT_DIR/opensuse-guest-dumpxml.txt" || true
wc -l "$OUT_DIR/opensuse-guest-dumpxml.txt"

echo "=== [inventory] ISO media inventory (openSUSE images) ==="
tower "ls -la /mnt/user/isos/ 2>/dev/null | grep -i -E 'opensuse|tumbleweed|osuse' || echo '(no openSUSE ISOs in /mnt/user/isos)'; ls -la /boot/custom/ 2>/dev/null | grep -i iso | head -20 || true; find /mnt/user /mnt/pool_one -maxdepth 3 -iname '*opensuse*' -type f 2>/dev/null | head -20" | tee "$OUT_DIR/iso-inventory.txt" || true

# Disk + network detail for the opensuse-tw guest (read-only)
DISK_PATH="/mnt/pool_two/domains/opensuse-tw/vdisk1.qcow2"
echo "=== [inventory] opensuse-tw disk detail (qemu-img info) ==="
tower "sudo qemu-img info '$DISK_PATH' 2>/dev/null || echo 'disk $DISK_PATH not readable/absent'" \
  | tee "$OUT_DIR/opensuse-disk-info.txt" || true
echo "=== [inventory] opensuse-tw disk size on tower (ls) ==="
tower "ls -la '$DISK_PATH' 2>/dev/null || echo 'no file'; ls -la /mnt/pool_two/domains/opensuse-tw/ 2>/dev/null || true" \
  | tee -a "$OUT_DIR/opensuse-disk-info.txt" || true

echo "=== [inventory] br0 network bridge detail ==="
tower 'sudo virsh net-dumpxml br0 2>/dev/null | grep -E "name>|bridge=|<ip |<range|<forward|<interface|<domain" | head -12' \
  | tee "$OUT_DIR/br0-detail.txt" || true

# ISO boot layout (kernel/initrd paths) for headless serial install planning
ISO_PATH="/mnt/pool_one/isos/openSUSE-Tumbleweed-GNOME-Live-x86_64-Current.iso"
echo "=== [inventory] ISO boot layout (read-only) ==="
tower "bsdtar -tf '$ISO_PATH' 2>/dev/null | grep -E '^boot/' | head -40; echo '---EFI---'; bsdtar -tf '$ISO_PATH' 2>/dev/null | grep -iE 'EFI/BOOT|loader/' | head -20" \
  | tee "$OUT_DIR/iso-boot-layout.txt" || true

echo "=== [inventory] $VM_IP occupancy probe (arp + ping, read-only) ==="
tower "ip neigh show | grep -i '$VM_IP' || echo 'no arp entry'; ping -c1 -W2 '$VM_IP' >/dev/null 2>&1 && echo 'PING: $VM_IP answers' || echo 'PING: $VM_IP silent'" | tee "$OUT_DIR/ip-occupancy.txt" || true

# Structured summary record
GUEST_COUNT=$(grep -cE '^ [0-9]+ +[a-zA-Z0-9._-]+ ' "$OUT_DIR/virsh-list.txt" || echo 0)
OSUSE_NAMES=$(grep -iE 'opensuse|tumbleweed|osuse' "$OUT_DIR/virsh-list.txt" | awk '{print $2}' | tr '\n' ',')
IP_ANSWERS=$(grep -c "answers" "$OUT_DIR/ip-occupancy.txt" 2>/dev/null || echo 0)

cat > "$OUT_DIR/inventory.json" <<JSON
{"hypervisor":"tower","checked_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","vm_ip":"$VM_IP","guest_count_hint":$GUEST_COUNT,"opensuse_named_guests":"${OSUSE_NAMES}","ip_answers_ping":$IP_ANSWERS,"ci_job":"${CI_JOB_ID:-0}","ci_pipeline":"${CI_PIPELINE_ID:-0}","ci_commit":"${CI_COMMIT_SHA:-local}"}
JSON

echo "=== inventory done ==="
exit 0
