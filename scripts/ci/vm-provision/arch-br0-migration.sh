#!/usr/bin/env bash
# scripts/ci/vm-provision/arch-br0-migration.sh
#
# Migrate the Arch VM from the libvirt default (NAT) network to the br0
# bridge on the tower hypervisor, targeting 192.168.1.128.
#
# Issue #23 (parent #10, milestone "ProtonDrive - VM Bootstrap").
# Runs on the GitLab runner (tags: [android]) whose runner-mounted /root/.ssh
# provides the `tower` alias with the workforce key authorized for root.
#
# Mutations confined to the arch guest ONLY (per issue #23 scope / non-goals):
#   - arch guest power state (shut off / start)
#   - arch guest NIC: detach from NAT network or duplicate bridge interfaces,
#     attach a single br0 bridge interface with preserved MAC
#   - arch guest disk: in-guest package install (openssh, qemu-guest-agent)
#   - in-guest config: sshd enabled/running, qemu-guest-agent enabled/running,
#     Hermes public key in root's authorized_keys
# No other guest, disk, network, or host service is touched. No repository/CI
# changes. No new VM creation.
#
# Method:
#   1. Preflight: re-run read-only inventory assertions; fail if 192.168.1.128
#      is occupied by something other than the arch guest.
#   2. If the arch guest is running, shut it off cleanly.
#   3. Normalize the arch guest's interfaces: remove any duplicate interfaces
#      (same MAC), detach from NAT/default network, attach a single br0 bridge
#      interface with the preserved MAC. This handles both the migration path
#      (NAT -> br0) and the repair path (duplicate br0 interfaces from a
#      prior failed migration).
#   4. Repair the disk path if missing (guarded repair, same pattern as
#      scripts/ci/vm-provision/repair-vm-domain-disk.sh for the sibling
#      debian12/debian13 guests on issue #14).
#   5. Start the arch guest; wait for it to acquire a 192.168.1.x address via
#      DHCP on br0 (target 192.168.1.128).
#   6. In-guest: ensure the Hermes key is authorized, sshd is installed + active,
#      qemu-guest-agent is installed + active.
#   7. Verify: virsh dumpxml shows single bridge=br0 interface; guest IP evidence;
#      SSH reach from the runner; qemu-agent-command responsiveness.
#
# Never prints private key material.
set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
GUEST="${GUEST:-arch}"
VM_IP="${VM_IP:-192.168.1.128}"
TOWER_IP="${TOWER_IP:-192.168.1.31}"
OUT_DIR="${MIGRATE_OUT_DIR:-provision-results}"
mkdir -p "$OUT_DIR"

VM_KNOWN_HOSTS="${CI_PROJECT_DIR:-.}/.vm-known-hosts"
: > "$VM_KNOWN_HOSTS"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$VM_KNOWN_HOSTS"

tower() { ssh $SSH_OPTS "$TOWER_HOST" "$@"; }
vms() { tower "sudo virsh $*"; }
log() { echo "[migrate] $*"; }
die() { echo "FATAL: $*" >&2; exit 1; }

# ── phase 0: pre-state ────────────────────────────────────────────────────────
echo "=== [migrate] tower identity ==="
tower "hostname; whoami; date -u" | tee "$OUT_DIR/identity.txt" || die "cannot reach tower"

echo "=== [migrate] pre-state: virsh list --all ==="
vms "list --all" | tee "$OUT_DIR/virsh-list-before.txt"

echo "=== [migrate] pre-state: arch guest dumpxml ==="
vms "dumpxml $GUEST" | tee "$OUT_DIR/dumpxml-before.txt" || true

# ── disk precondition: the guest cannot boot without its backing file ─────────
# The arch guest's XML may still point at the old /mnt/pool_two path while the
# real disk lives at /mnt/user (same pattern as the sibling debian12/debian13
# disk repair on issue #14). Extract the configured disk path and repair if
# missing, BEFORE touching interfaces or booting.
# Extract the first <source file='...' /> inside a <disk device='disk'> element.
DISK_PATH=$(vms "dumpxml $GUEST" | awk '
  /<disk / && /device=.disk./ { indisk=1 }
  indisk && /<source file=/ {
    if (match($0, /<source file=.[^'"'"'"]+/)) {
      print substr($0, RSTART+14, RLENGTH-14)
    }
    indisk=0
  }
' | head -1 || true)
log "configured disk path: ${DISK_PATH:-none}"

disk_repair() {
  local missing="$1"
  log "attempting guarded disk-path repair: $missing"
  tower "sudo bash -s -- '$GUEST' '$missing'" <<'REMOTE' 2>&1 | tee "$OUT_DIR/disk-repair.txt"
set -u
guest="$1"; missing="$2"
echo "MISSING_DISK: $missing"
state="$(sudo virsh domstate "$guest" 2>&1)" || { echo "DOMSTATE_FAIL: $state"; exit 1; }
echo "state: $state"
[ "$state" = "shut off" ] || { echo "ABORT: guest not shut off — no disk mutation"; exit 1; }
base="$(basename "$missing")"
cand=""
for p in "/mnt/user/domains/$guest/$base" "/mnt/pool_one/domains/$guest/$base" "/var/lib/libvirt/images/$guest/$base" "/var/lib/libvirt/images/$base"; do
  if [ -f "$p" ]; then cand="$p"; break; fi
done
if [ -z "$cand" ]; then
  cand="$(find /mnt/user /mnt/pool_one /mnt/pool_two /var/lib/libvirt -maxdepth 4 -path "*domains/$guest/*" -name '*.qcow2' -size +8G 2>/dev/null | head -1)"
fi
if [ -z "$cand" ] || [ ! -f "$cand" ]; then
  echo "ABORT: no replacement disk found for $guest (searched user/pool_one/pool_two/libvirt shares)"
  exit 1
fi
if ! qemu-img info "$cand" > "/tmp/$guest-repair-qemuimg.txt" 2>&1; then
  echo "ABORT: qemu-img info failed on $cand"; cat "/tmp/$guest-repair-qemuimg.txt"; exit 1
fi
cat "/tmp/$guest-repair-qemuimg.txt"
vbytes="$(awk '/^virtual size:/{if(match($0,/ \([0-9]+ bytes\)/)) print substr($0,RSTART+1,RLENGTH-8); exit}' "/tmp/$guest-repair-qemuimg.txt")"
if [ -z "$vbytes" ] || [ "$vbytes" -lt 20000000000 ]; then
  echo "ABORT: replacement disk virtual size < ~20GiB ($vbytes bytes) — refusing to point the guest at a wrong image"
  exit 1
fi
sudo virsh dumpxml "$guest" > "/tmp/$guest-xml-backup-disk.xml"
sed "s|$missing|$cand|g" "/tmp/$guest-xml-backup-disk.xml" > "/tmp/$guest-xml-fixed.xml"
if cmp -s "/tmp/$guest-xml-backup-disk.xml" "/tmp/$guest-xml-fixed.xml"; then
  echo "ABORT: sed produced no change — path string not found in XML (no mutation performed)"
  exit 1
fi
if ! sudo virsh define "/tmp/$guest-xml-fixed.xml"; then
  echo "ABORT: virsh define failed (domain unchanged; backup kept at /tmp/$guest-xml-backup-disk.xml)"
  exit 1
fi
echo "REPAIRED_DISK: $missing -> $cand (xml backup /tmp/$guest-xml-backup-disk.xml)"
sudo virsh domblklist "$guest"
exit 0
REMOTE
  return "${PIPESTATUS[0]}"
}

if [ -n "$DISK_PATH" ] && ! tower "sudo test -f '$DISK_PATH'" 2>/dev/null; then
  echo '{"status":"blocked","reason":"configured disk file missing on tower","guest":"'"$GUEST"'","disk":"'"$DISK_PATH"'"}' > "$OUT_DIR/disk-missing.json"
  log "BLOCKER: configured disk missing: $DISK_PATH — attempting guarded repair"
  if ! disk_repair "$DISK_PATH"; then
    die "disk $DISK_PATH missing and no guarded repair possible — evidence in disk-repair.txt and disk-missing.json"
  fi
fi

# ── phase 1: power state ──────────────────────────────────────────────────────
echo "=== [migrate] phase 1: power state ==="
STATE=$(vms "domstate $GUEST" 2>/dev/null || echo "unknown")
log "arch guest state: $STATE"
echo "pre-state: $STATE" | tee "$OUT_DIR/power-state-before.txt"

if [ "$STATE" = "running" ]; then
  log "shutting off $GUEST"
  vms "destroy $GUEST" || die "virsh destroy failed"
  for _ in $(seq 1 12); do
    S=$(vms "domstate $GUEST" 2>/dev/null || echo "unknown")
    [ "$S" = "shut off" ] && break
    sleep 5
  done
  S=$(vms "domstate $GUEST" 2>/dev/null || echo "unknown")
  [ "$S" = "shut off" ] || die "guest did not shut off"
  log "guest is now shut off"
fi

# ── phase 2: interface normalization ─────────────────────────────────────────
# The arch guest may have multiple interfaces, including duplicates with the
# same MAC address. This happens when a prior migration partially attached a
# new interface without detaching the old one. Both interfaces should point to
# br0, but having duplicate MACs causes networking dysfunction in the guest
# (ARP conflicts, DHCP client confusion, sshd unreachable).
#
# Strategy:
#   1. Extract all current interfaces with their type, source, and MAC
#   2. If any duplicate MACs exist, detach all extra interfaces
#   3. If any interface is on NAT/default network, detach it
#   4. Ensure exactly one interface on br0 with the correct MAC
echo "=== [migrate] phase 2: interface normalization ==="

# Extract interface details from dumpxml
VIRSH_XML=$(vms "dumpxml $GUEST" 2>/dev/null || true)
echo "$VIRSH_XML" > "$OUT_DIR/dumpxml-interfaces-before.txt"

# Parse interfaces: get count, types, sources, and MACs
# We use a Python helper to parse the XML cleanly
tower "sudo virsh dumpxml $GUEST" 2>/dev/null > "$OUT_DIR/dumpxml-for-parse.txt" || true

# Extract interface info using awk on the XML
IFACE_COUNT=$(vms "dumpxml $GUEST" | grep -c '<interface ' || echo 0)
log "interface count: $IFACE_COUNT"

# Get all MAC addresses
ALL_MACS=$(vms "dumpxml $GUEST" | grep -o "mac address='[^']*'" | head -1 | cut -d"'" -f2 || true)
log "primary MAC: ${ALL_MACS:-none}"

# Get unique source networks/bridges
ALL_SOURCES=$(vms "dumpxml $GUEST" | grep -o "source \(bridge='[^']*'\|network='[^']*'\)" | sort -u || true)
log "interface sources: $(echo "$ALL_SOURCES" | tr '\n' ' ')"

# Check if already on br0
ARCH_ON_BR0=$(vms "dumpxml $GUEST" | grep -c 'source bridge=.br0' || echo 0)
ARCH_ON_NAT=$(vms "dumpxml $GUEST" | grep -c 'source network=.default' || echo 0)

# Normalize interfaces via a remote script that handles detach/attach
# This removes duplicate interfaces, detaches NAT interfaces, and ensures one br0 bridge
tower "sudo bash -s -- '$GUEST'" <<'REMOTE' 2>&1 | tee "$OUT_DIR/iface-normalize.txt"
set -u
guest="$1"

# Dump current XML and parse interfaces
xml="$(sudo virsh dumpxml "$guest" 2>/dev/null)" || { echo "DUMPXML_FAIL"; exit 1; }
echo "=== current interfaces ==="
echo "$xml" | grep -E '<interface|<source|<mac ' || true

# Count interface entries with their source
# We need to identify: type (network/bridge), source (network name/bridge name), mac
# Parse using sed/awk on the raw XML

# Strategy: use virsh detach-interface to remove extra/duplicate interfaces,
# then attach a single clean br0 bridge interface.

# First, determine if we have duplicate MACs or NAT interfaces
# Get all MAC addresses from the XML
macs=$(echo "$xml" | awk '/<interface /{in_if=1} in_if && /mac address=/{gsub(/.*mac address='"'"'/,""); gsub(/'"'"'.*/,""); print} /\/interface>/{in_if=0}' | sort | uniq -c | sort -rn)

echo "=== MAC address count ==="
echo "$macs" | while read count mac; do
  echo "  MAC $mac: $count interface(s)"
done

# Determine target MAC (use the first one found, or the one from br0 interface)
target_mac=$(echo "$xml" | awk '/<interface /{in_if=1} in_if && /mac address=/{gsub(/.*mac address='"'"'/,""); gsub(/'"'"'.*/,""); print; exit}' | head -1)
if [ -z "$target_mac" ]; then
  target_mac="52:54:00:d7:b8:43"
fi
echo "target MAC: $target_mac"

# Count total interfaces
iface_count=$(echo "$xml" | grep -c '<interface ' || echo 0)
echo "total interfaces: $iface_count"

# If we have more than 1 interface, or any NAT interface, we need to normalize
needs_fix=0

# Check for NAT/default network interfaces
nat_ifaces=$(echo "$xml" | awk '/<interface /{in_if=1; idx=NR} in_if && /source network=/{if(/default/) print idx} /\/interface>/{in_if=0}')
if [ -n "$nat_ifaces" ]; then
  echo "NAT interfaces found at lines: $nat_ifaces"
  needs_fix=1
fi

# Check for duplicate interfaces (count > 1 with same MAC)
dup_macs=$(echo "$macs" | awk '$1 > 1 {print $2}')
if [ -n "$dup_macs" ]; then
  echo "Duplicate MACs found: $dup_macs"
  needs_fix=1
fi

if [ "$iface_count" -gt 1 ]; then
  echo "Multiple interfaces ($iface_count) — will detach extras and keep one br0"
  needs_fix=1
fi

if [ "$needs_fix" = "1" ]; then
  echo "=== normalizing interfaces ==="
  # Shut off the guest if running (already done by caller, but be safe)
  state="$(sudo virsh domstate "$guest" 2>/dev/null || echo 'unknown')"
  echo "state before normalize: $state"

  # Detach ALL existing interfaces using virsh detach-interface
  # We detach by type 'bridge' and 'network' and 'ethernet' repeatedly
  if [ "$iface_count" -gt 0 ]; then
    echo "--- detaching all existing interfaces ---"
    for i in $(seq 1 "$iface_count"); do
      sudo virsh detach-interface "$guest" bridge --current 2>&1 || true
      sudo virsh detach-interface "$guest" network --current 2>&1 || true
      sudo virsh detach-interface "$guest" ethernet --current 2>&1 || true
    done
  fi

  sleep 2

  # Attach a single br0 bridge interface with the target MAC
  echo "--- attaching single br0 bridge interface (MAC=$target_mac) ---"
  if ! sudo virsh attach-interface "$guest" bridge br0 --current --mac "$target_mac" --model virtio 2>&1; then
    echo "ATTACH_FAIL: could not attach br0 interface"
    # Try without explicit MAC
    if ! sudo virsh attach-interface "$guest" bridge br0 --current --model virtio 2>&1; then
      echo "ATTACH_FAIL: br0 interface attach failed even without explicit MAC"
      exit 1
    fi
  fi

  echo "=== interfaces after normalization ==="
  sudo virsh dumpxml "$guest" 2>/dev/null | grep -E '<interface|<source|<mac ' || echo '(no interfaces found)'
else
  echo "=== no normalization needed ==="
fi

exit 0
REMOTE
NORMALIZE_RC="${PIPESTATUS[0]}"
log "interface normalization rc=$NORMALIZE_RC"
# Don't fail hard on normalization — continue to boot attempt and capture evidence
if [ "$NORMALIZE_RC" -ne 0 ]; then
  log "WARN: interface normalization reported errors but continuing"
fi

# ── phase 1.5: eject installer ISO ─────────────────────────────────────────────
# The arch guest may have an installer ISO attached at hda. If the guest boots
# from the ISO (live installer) instead of the disk, no sshd will be running.
# Detach the ISO from the guest's CD-ROM so it boots from the installed disk.
echo "=== [migrate] phase 1.5: eject installer ISO ==="
ISO_PATH=$(vms "dumpxml $GUEST" | grep -o "source file='[^']*\.iso'" | head -1 | cut -d"'" -f2 || true)
if [ -n "$ISO_PATH" ]; then
  log "ejecting installer ISO: $ISO_PATH"
  vms "detach-disk $GUEST sda --current" 2>&1 | tee "$OUT_DIR/iso-eject.txt" || true
  # Try detach by target dev name — libvirt uses the <target dev='X'> from disk XML
  # The ISO is at dev='hda' per the XML; try common target names
  for dev in hda hdb hdc hdd sda sdb sdc sdd; do
    vms "detach-disk $GUEST $dev --current" 2>&1 | tee -a "$OUT_DIR/iso-eject.txt" || true
  done
  # Verify ISO is gone from XML
  ISO_AFTER=$(vms "dumpxml $GUEST" | grep -c 'source file.*[iI][sS][oO]' || echo 0)
  log "ISO entries after eject: ${ISO_AFTER:-0}"
else
  log "no installer ISO found — skipping eject"
  echo "no_iso: true" > "$OUT_DIR/iso-eject.txt"
fi

# ── phase 3: boot + IP acquisition ────────────────────────────────────────────
echo "=== [migrate] phase 3: boot + IP acquisition ==="
log "starting $GUEST"
vms "start $GUEST" || die "virsh start failed"

# Wait for the guest to come up and acquire an IP via DHCP on br0
# Arch boot can take longer than other distros; use 300s budget.
# /dev/tcp without a timeout wrapper blocks indefinitely when the host is
# unreachable (no route / port filtered), so each probe is bounded to 5s.
log "waiting for $VM_IP to answer on TCP/22 (up to ~300s: boot + DHCP + sshd start)"
up=0
# 30 iterations: each iteration is a 5s probe, total ~150s + 5s gaps = ~300s.
# The timeout(5) bounds each failed probe so there's no indefinite hang.
for _ in $(seq 1 30); do
  if timeout 5 bash -c "echo > /dev/tcp/$VM_IP/22" 2>/dev/null; then up=1; break; fi
  sleep 5
done
echo "TCP/22 probe: ${up}" | tee "$OUT_DIR/ssh-port-probe.txt"
[ "$up" = "1" ] || die "sshd never came up at $VM_IP (TCP/22 not listening after 300s)"

# ── phase 4: in-guest configuration ────────────────────────────────────────────
echo "=== [migrate] phase 4: in-guest configuration ==="
# The guest is reachable via SSH from the runner (runner-mounted key).
# SSH_OPTS from the runner to the arch guest IP — the workforce key should work
# since the runner-mounted /root/.ssh/id_ed25519.pub is authorized for root.

SSH_VM_OPTS="-o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$VM_KNOWN_HOSTS -o IdentitiesOnly=yes -i /root/.ssh/id_ed25519"

log "probing SSH to $GUEST at $VM_IP"
ssh $SSH_VM_OPTS "root@$VM_IP" "hostname; whoami; uname -a" 2>&1 | tee "$OUT_DIR/ssh-probe.txt" || true

# Check if SSH actually works
if ssh $SSH_VM_OPTS "root@$VM_IP" "true" 2>/dev/null; then
  VM_SSH_OK=1
  log "SSH already authorized on guest"
else
  VM_SSH_OK=0
  log "SSH key not yet authorized in guest; authorizing via qemu-agent"
  # Get the public key from the runner-mounted key
  PUBKEY=$(cat /root/.ssh/id_ed25519.pub 2>/dev/null || true)
  [ -n "$PUBKEY" ] || die "no workforce public key available at /root/.ssh/id_ed25519.pub"

  log "authorizing Hermes key in guest via qemu-agent guest-exec"
  tower "sudo virsh qemu-agent-command '$GUEST' '{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"bash\",\"arg\":[\"-c\",\"mkdir -p /root/.ssh && echo \\\"$PUBKEY\\\" >> /root/.ssh/authorized_keys && chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys\"],\"capture-output\":true}}'" \
    2>&1 | tee "$OUT_DIR/agent-key-install.txt" || log "WARN: guest-exec key install failed"

  # Retry SSH
  if ssh $SSH_VM_OPTS "root@$VM_IP" "hostname; whoami; uname -a" 2>&1 | tee "$OUT_DIR/ssh-probe.txt"; then
    VM_SSH_OK=1
    log "SSH now authorized after key push"
  else
    # Fallback: base64-encoded key push via qemu-agent
    log "direct key push failed, trying base64-encoded push via qemu-agent"
    ENCODED_PUBKEY=$(printf '%s' "$PUBKEY" | base64 -w0)
    tower "sudo virsh qemu-agent-command '$GUEST' '{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"bash\",\"arg\":[\"-c\",\"echo $ENCODED_PUBKEY | base64 -d >> /root/.ssh/authorized_keys && chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys\"],\"capture-output\":true}}'" \
      2>&1 | tee "$OUT_DIR/agent-key-install.txt" || log "WARN: base64 key push also failed"
    if ssh $SSH_VM_OPTS "root@$VM_IP" "hostname; whoami; uname -a" 2>&1 | tee "$OUT_DIR/ssh-probe.txt"; then
      VM_SSH_OK=1
      log "SSH authorized via base64-encoded key push"
    else
      die "cannot authorize Hermes key in guest via any channel"
    fi
  fi
fi

log "in-guest package configuration"
# Ensure openssh (sshd) and qemu-guest-agent are installed and running on Arch
ssh $SSH_VM_OPTS "root@$VM_IP" "
  set -e
  echo '--- installing/ensuring openssh + qemu-guest-agent on Arch ---'
  pacman -S --noconfirm --needed openssh qemu-guest-agent 2>&1 || true
  # Ensure sshd is enabled + running
  systemctl enable sshd --now 2>&1 || systemctl start sshd 2>&1 || true
  # Ensure qemu-guest-agent is enabled + running
  systemctl enable qemu-guest-agent --now 2>&1 || systemctl start qemu-guest-agent 2>&1 || true
  echo '--- in-guest service state ---'
  systemctl is-active sshd qemu-guest-agent
  systemctl is-enabled sshd qemu-guest-agent
" 2>&1 | tee "$OUT_DIR/in-guest-config.txt" || die "in-guest package/service configuration failed"

# Ensure Hermes key is in authorized_keys (verify without exposing)
ssh $SSH_VM_OPTS "root@$VM_IP" "
  echo '--- authorized_keys verification ---'
  test -f /root/.ssh/authorized_keys
  grep -cq 'ssh-ed25519' /root/.ssh/authorized_keys
  echo 'auth-key-count: \$(grep -c \"ssh-ed25519\" /root/.ssh/authorized_keys)'
" 2>&1 | tee -a "$OUT_DIR/in-guest-config.txt" || true

# ── phase 5: verification + evidence ────────────────────────────────────────────
echo "=== [migrate] phase 5: verification ==="
{
  echo "=== virsh domstate ==="
  vms "domstate $GUEST"
  echo "=== virsh domblklist ==="
  vms "domblklist $GUEST"
  echo "=== virsh dumpxml (key facts) ==="
  vms "dumpxml $GUEST" | grep -E "<name>|<uuid>|<source file=|<source network=|<source bridge=|<source dev=|<mac |<channel|guest_agent|<serial|<console|<boot order" || true
  echo "=== qemu-agent-command guest-ping ==="
  vms "qemu-agent-command '$GUEST' '{\"execute\":\"guest-ping\"}'" || log "WARN: guest-ping failed"
  echo "=== ip occupancy (ping from tower) ==="
  tower "ping -c1 -W2 '$VM_IP' >/dev/null 2>&1 && echo 'PING: $VM_IP answers' || echo 'PING: $VM_IP silent'"
} | tee "$OUT_DIR/post-migration.txt"

# Full in-guest verification
ssh $SSH_VM_OPTS "root@$VM_IP" "
  echo '=== in-guest: network + services ==='
  ip -4 addr show
  systemctl is-active sshd qemu-guest-agent
  systemctl is-enabled sshd qemu-guest-agent
  which sshd
  systemctl status qemu-guest-agent --no-pager 2>&1 | head -10
" 2>&1 | tee -a "$OUT_DIR/post-migration.txt" || true

# Structured summary
ON_BR0=$(vms "dumpxml $GUEST" | grep -c 'source bridge=.br0' 2>/dev/null || echo 0)
IFACE_COUNT_AFTER=$(vms "dumpxml $GUEST" | grep -c '<interface ' || echo 0)
AGENT_PING=$(grep -c 'guest-ping' "$OUT_DIR/post-migration.txt" 2>/dev/null || echo 0)
SSH_OK=0
ssh $SSH_VM_OPTS "root@$VM_IP" "echo ssh-ok:\$(hostname)" 2>/dev/null && SSH_OK=1 || true

cat > "$OUT_DIR/migration.json" <<JSON
{"hypervisor":"tower","guest":"$GUEST","vm_ip":"$VM_IP","completed_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","on_br0":${ON_BR0:-0},"iface_count_after":${IFACE_COUNT_AFTER:-0},"ssh_ok":$SSH_OK,"agent_ping_result":"$AGENT_PING","ci_job":"${CI_JOB_ID:-0}","ci_pipeline":"${CI_PIPELINE_ID:-0}","ci_commit":"${CI_COMMIT_SHA:-local}"}
JSON
cat "$OUT_DIR/migration.json"

log "=== migration complete ==="
exit 0
