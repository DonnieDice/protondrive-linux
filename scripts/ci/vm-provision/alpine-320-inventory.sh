#!/usr/bin/env bash
# scripts/ci/vm-provision/alpine-320-inventory.sh
#
# Read-only tower hypervisor inventory for issue #21 (Alpine 3.20 VM
# bootstrap, parent #5). Runs on the GitLab runner (on Tower), which has SSH
# access to the tower hypervisor via the runner-mounted /root/.ssh config
# (alias: tower). Strictly read-only:
#   - virsh list --all
#   - per-guest dumpxml summaries (name, disk, interface, agent channel)
#   - storage pools / volumes overview
#   - libvirt networks (br0 attachment facts)
#   - ARP/neighbor table + ping occupancy probe for VM_IP 192.168.1.157
#   - ISO media inventory for alpine-3.20 images
#
# Emits human logs + a machine-readable JSON record for acceptance evidence.
set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
VM_IP="${VM_IP:-192.168.1.157}"
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

echo "=== [inventory] storage pools ==="
tower "sudo virsh pool-list --all; for p in \$(sudo virsh pool-list --name --all); do echo \"--- pool \$p ---\"; sudo virsh pool-dumpxml \"\$p\" | grep -E '<path>|<name>' | head -4; sudo virsh vol-list \"\$p\" 2>/dev/null | head -40; done" | tee "$OUT_DIR/pools.txt" || true

echo "=== [inventory] libvirt networks ==="
tower "sudo virsh net-list --all; for n in \$(sudo virsh net-list --name --all); do echo \"--- net \$n ---\"; sudo virsh net-dumpxml \"\$n\" | grep -E '<name>|bridge=|<ip |<range' | head -8; done" | tee "$OUT_DIR/networks.txt" || true

echo "=== [inventory] alpine-3.20-named guest detail ==="
tower 'for d in $(sudo virsh list --all --name); do
  case "$d" in *alpine*3.20*|*alpine320*|*alpine-320*) echo "===== $d ====="; sudo virsh dumpxml "$d";; esac
done' > "$OUT_DIR/alpine320-guest-dumpxml.txt" || true
wc -l "$OUT_DIR/alpine320-guest-dumpxml.txt"

echo "=== [inventory] ISO media inventory (alpine images) ==="
tower "ls -la /mnt/user/isos/ 2>/dev/null | grep -i alpine || echo '(no alpine ISOs in /mnt/user/isos)'; ls -la /boot/custom/ 2>/dev/null | grep -i iso | head -20 || true; find /mnt/user -maxdepth 3 -iname '*alpine*' -type f 2>/dev/null | head -20" | tee "$OUT_DIR/iso-inventory.txt" || true

echo "=== [inventory] $VM_IP occupancy probe (arp + ping, read-only) ==="
tower "ip neigh show | grep -i '$VM_IP' || echo 'no arp entry'; ping -c1 -W2 '$VM_IP' >/dev/null 2>&1 && echo 'PING: $VM_IP answers' || echo 'PING: $VM_IP silent'" | tee "$OUT_DIR/ip-occupancy.txt" || true

# Structured summary record
GUEST_COUNT=$(grep -cE '^ [0-9]+ +[a-zA-Z0-9._-]+ ' "$OUT_DIR/virsh-list.txt" || echo 0)
ALPINE_NAMES=$(grep -iE 'alpine' "$OUT_DIR/virsh-list.txt" | awk '{print $2}' | tr '\n' ',')
IP_ANSWERS=$(grep -c "answers" "$OUT_DIR/ip-occupancy.txt" 2>/dev/null || echo 0)

cat > "$OUT_DIR/inventory.json" <<JSON
{"hypervisor":"tower","checked_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","vm_ip":"$VM_IP","guest_count_hint":$GUEST_COUNT,"alpine_named_guests":"${ALPINE_NAMES}","ip_answers_ping":$IP_ANSWERS,"ci_job":"${CI_JOB_ID:-0}","ci_pipeline":"${CI_PIPELINE_ID:-0}","ci_commit":"${CI_COMMIT_SHA:-local}"}
JSON

echo "=== inventory done ==="
exit 0
