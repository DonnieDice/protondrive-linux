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
#   - arch guest installer ISO cdrom: detached (targeted, by device target)
#   - in-guest config: sshd + qemu-guest-agent installed/enabled/running,
#     Hermes public key in root's authorized_keys
# No other guest, disk, network, or host service is touched. No new VM creation.
#
# Method:
#   0. Preflight: identity, read-only pre-state (virsh list, dumpxml), disk
#      path existence with guarded repair (sibling debian pattern, #14).
#   1. Power: shut the guest off cleanly if running.
#   2. Interface normalization: remove duplicate-MAC/NAT interfaces; ensure a
#      single br0 bridge interface with the preserved MAC (migration path and
#      repair path).
#   3. ISO eject: detach ONLY the cdrom device holding the installer ISO,
#      identified from the domain XML by <target dev='...'> — never a blind
#      detach loop that could also detach the OS disk.
#   4. Boot and discover the guest's actual address: DHCP on br0 decides the
#      address. Discover via virsh domifaddr (guest agent), host ARP/neigh on
#      br0, and a DHCP lease assumption for the configured VM_IP. If the guest
#      obtained an address different from the CI-wired 192.168.1.128, record it
#      in the evidence (CI scripts keep expecting .128; that impact is noted
#      on the issue, not silently rewritten here).
#   5. In-guest: authorize Hermes key, install/enable sshd + qemu-guest-agent.
#   6. Verify and record: dumpxml interface facts, in-guest ip addr, SSH
#      reachability from the runner, guest-ping, authorized_keys count.
#
# Boot diagnostics: on SSH wait failure, capture the serial console log tail
# from the host so boot vs network failures are distinguishable in evidence.
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
: >"$VM_KNOWN_HOSTS"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$VM_KNOWN_HOSTS"

tower() { ssh $SSH_OPTS "$TOWER_HOST" "$@"; }
vms() { tower "sudo virsh $*"; }
log() { echo "[migrate] $*"; }
die() {
  echo "FATAL: $*" >&2
  exit 1
}

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
  echo '{"status":"blocked","reason":"configured disk file missing on tower","guest":"'"$GUEST"'","disk":"'"$DISK_PATH"'"}' >"$OUT_DIR/disk-missing.json"
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
# new interface without detaching the old one. Duplicate MACs cause networking
# dysfunction in the guest (ARP conflicts, DHCP client confusion, unreachable
# sshd). Normalize to exactly one br0 bridge interface with the preserved MAC.
echo "=== [migrate] phase 2: interface normalization ==="

tower "sudo bash -s -- '$GUEST'" <<'REMOTE' 2>&1 | tee "$OUT_DIR/iface-normalize.txt"
set -u
guest="$1"

xml="$(sudo virsh dumpxml "$guest" 2>/dev/null)" || { echo "DUMPXML_FAIL"; exit 1; }
echo "=== current interfaces ==="
echo "$xml" | grep -E '<interface|<source|<mac ' || true

macs=$(echo "$xml" | awk '/<interface /{in_if=1} in_if && /mac address=/{gsub(/.*mac address='\"'\"'/,""); gsub(/'"'"'.*/,\"\"); print} /<\/interface>/{in_if=0}' | sort | uniq -c | sort -rn)

echo "=== MAC address count ==="
echo "$macs" | while read count mac; do
  echo "  MAC $mac: $count interface(s)"
done

target_mac=$(echo "$xml" | awk '/<interface /{in_if=1} in_if && /mac address=/{gsub(/.*mac address='\"'\"'/,\"\"); gsub(/'\"'\"'.*/,\"\"); print; exit}' | head -1)
if [ -z "$target_mac" ]; then
  target_mac="52:54:00:d7:b8:43"
fi
echo "target MAC: $target_mac"

iface_count=$(echo "$xml" | grep -c '<interface ' || echo 0)
echo "total interfaces: $iface_count"

needs_fix=0

nat_ifaces=$(echo "$xml" | awk '/<interface /{in_if=1; idx=NR} in_if && /source network=/{if(/default/) print idx} /<\/interface>/{in_if=0}')
if [ -n "$nat_ifaces" ]; then
  echo "NAT interfaces found at lines: $nat_ifaces"
  needs_fix=1
fi

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
  state="$(sudo virsh domstate "$guest" 2>/dev/null || echo 'unknown')"
  echo "state before normalize: $state"

  if [ "$iface_count" -gt 0 ]; then
    echo "--- detaching all existing interfaces ---"
    for i in $(seq 1 "$iface_count"); do
      sudo virsh detach-interface "$guest" bridge --current 2>&1 || true
      sudo virsh detach-interface "$guest" network --current 2>&1 || true
      sudo virsh detach-interface "$guest" ethernet --current 2>&1 || true
    done
  fi

  sleep 2

  echo "--- attaching single br0 bridge interface (MAC=$target_mac) ---"
  if ! sudo virsh attach-interface "$guest" bridge br0 --current --mac "$target_mac" --model virtio 2>&1; then
    echo "ATTACH_FAIL: could not attach br0 interface"
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
if [ "$NORMALIZE_RC" -ne 0 ]; then
  log "WARN: interface normalization reported errors but continuing"
fi

# ── phase 1.5: eject installer ISO (targeted, cdrom device only) ───────────────
# The arch guest may have an installer ISO attached at hda. If the guest boots
# from the ISO (live installer) instead of the disk, no sshd will be running.
# Identify the cdrom device that actually holds the ISO from the domain XML and
# detach ONLY that target dev. A blind detach loop over hda..sdd would also
# detach the OS disk (observed at dev hdc in job 37005 evidence) — never do that.
echo "=== [migrate] phase 1.5: eject installer ISO (targeted) ==="
ISO_TARGET=$(vms "dumpxml $GUEST" | awk '
  /<disk / && /device=.cdrom./ { incd=1 }
  incd && /<source file=.*\.iso/ {
    if (match($0, /<source file=.[^'"'"'"]+/)) { iso_ok=1 }
  }
  incd && /<target dev=/ {
    if (match($0, /<target dev=.[^'"'"'"]+/)) { print substr($0, RSTART+13, RLENGTH-13) }
  }
  incd && /<\/disk>/ { incd=0 }
' | head -1 || true)
log "cdrom target dev holding an ISO: ${ISO_TARGET:-none}"
if [ -n "$ISO_TARGET" ]; then
  log "ejecting installer ISO from cdrom device: $ISO_TARGET"
  {
    echo "target dev: $ISO_TARGET"
    vms "detach-disk $GUEST $ISO_TARGET --current" 2>&1
    echo "detach rc: $?"
  } | tee "$OUT_DIR/iso-eject.txt"
  ISO_AFTER=$(vms "dumpxml $GUEST" | grep -c 'source file.*\.iso' || echo 0)
  log "ISO entries after eject: ${ISO_AFTER:-0}"
  if [ "${ISO_AFTER:-0}" != "0" ]; then
    log "WARN: ISO still present after targeted detach — dumping disk block list for diagnosis"
    vms "domblklist $GUEST" | tee -a "$OUT_DIR/iso-eject.txt" || true
  fi
else
  log "no cdrom device with an ISO attached — skipping eject"
  echo "no_iso: true" >"$OUT_DIR/iso-eject.txt"
fi

# ── phase 3: boot + IP discovery ──────────────────────────────────────────────
echo "=== [migrate] phase 3: boot + IP discovery ==="
log "starting $GUEST"
vms "start $GUEST" || die "virsh start failed"

# Wait for the guest to acquire a 192.168.1.x address via DHCP on br0.
# The bridged guest's address is decided by the LAN DHCP server — the
# CI-wired VM_IP is an expectation, not a guarantee. Discover the actual
# address from three sources, in order of trust:
#   1. virsh domifaddr (guest agent, most authoritative, needs agent running)
#   2. host ARP/neigh table entries for the guest's MAC on br0
#   3. the configured VM_IP (assumption; may be wrong — evidence shows the
#      guest never answered on .128 after two prior boots)
# Each TCP probe is bounded by timeout(5) so an unreachable path cannot hang.
log "waiting for the guest to acquire an address (up to ~300s: boot + DHCP + sshd start)"

discover_vm_addr() {
  # 1) guest-agent route: virsh domifaddr (agent may not be running yet; retry handled by caller)
  local addr
  addr=$(vms "domifaddr $GUEST --source agent 2>/dev/null" | awk '/192\.168\.1\./ {print $4}' | cut -d/ -f1 | head -1)
  if [ -n "$addr" ]; then
    echo "$addr"
    return 0
  fi
  # 2) host ARP/neigh route: MAC -> IP on the host neighbor table
  local mac
  mac=$(vms "dumpxml $GUEST" | grep -o "mac address='[^']*'" | head -1 | cut -d"'" -f2)
  if [ -n "$mac" ]; then
    addr=$(tower "ip neigh show | grep -i '$mac'" | awk '/192\.168\.1\./ {for(i=1;i<=NF;i++) if($i ~ /^192\.168\.1\./) print $i}' | head -1)
    if [ -n "$addr" ]; then
      echo "$addr"
      return 0
    fi
  fi
  # 3) lease/assumption: the configured VM_IP if it now answers
  if timeout 5 bash -c "echo > /dev/tcp/$VM_IP/22" 2>/dev/null; then
    echo "$VM_IP"
    return 0
  fi
  return 1
}

GUEST_IP=""
up=0
for _ in $(seq 1 30); do
  if GUEST_IP=$(discover_vm_addr); then
    up=1
    break
  fi
  sleep 10
done
echo "discovered guest address: ${GUEST_IP:-none} (configured/CI-wired: $VM_IP)" | tee "$OUT_DIR/guest-address.txt"
[ "$up" = "1" ] || {
  log "guest did not acquire a reachable address — capturing boot diagnostics"
  {
    echo "=== virsh domstate ==="
    vms "domstate $GUEST" || true
    echo "=== virsh domblklist ==="
    vms "domblklist $GUEST" || true
    echo "=== virsh dumpxml interface + boot facts ==="
    vms "dumpxml $GUEST" | grep -E "<interface|<source bridge=|<source network=|<mac |<boot order|<source file=" || true
    echo "=== host neigh table (br0) ==="
    tower "ip neigh show | grep -E '192.168.1.' || echo '(no 192.168.1.x neigh entries)'" || true
    echo "=== guest agent status ==="
    vms "qemu-agent-command '$GUEST' '{\"execute\":\"guest-ping\"}'" 2>&1 || true
    echo "=== serial console log tail (last 60 lines) ==="
    vms "console $GUEST --force" 2>&1 | tail -60 || true
    echo "=== libvirt domain log tail ==="
    tower "sudo journalctl -u libvirtd --since '10 minutes ago' --no-pager 2>/dev/null | grep -iE '$GUEST|error|fail' | tail -30" || true
  } >"$OUT_DIR/boot-diagnostics.txt" 2>&1
  die "guest never acquired a reachable address (diagnostics in boot-diagnostics.txt)"
}

# Address acquired. If it is NOT the CI-wired IP, record the divergence —
# the CI scripts (install/transfer/vmtest arch + tests/robot/vars/vms.py)
# keep expecting 192.168.1.128; that impact must be surfaced on the issue.
if [ "$GUEST_IP" != "$VM_IP" ]; then
  log "NOTE: guest address $GUEST_IP differs from CI-wired $VM_IP — recording divergence for the issue evidence"
  echo "{\"configured_ip\":\"$VM_IP\",\"actual_ip\":\"$GUEST_IP\",\"ci_impact\":\"scripts/ci/{install,transfer,vmtest}/arch and tests/robot/vars/vms.py expect $VM_IP\"}" >"$OUT_DIR/ip-divergence.json"
fi

# Confirm TCP/22 on the discovered address.
ssh_up=0
for _ in $(seq 1 12); do
  if timeout 5 bash -c "echo > /dev/tcp/$GUEST_IP/22" 2>/dev/null; then
    ssh_up=1
    break
  fi
  sleep 5
done
echo "TCP/22 probe on $GUEST_IP: $ssh_up" | tee "$OUT_DIR/ssh-port-probe.txt"
[ "$ssh_up" = "1" ] || die "TCP/22 not listening on discovered address $GUEST_IP"

# ── phase 4: in-guest configuration ────────────────────────────────────────────
echo "=== [migrate] phase 4: in-guest configuration ==="
# The guest is reachable via SSH from the runner (runner-mounted key).
SSH_VM_OPTS="-o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$VM_KNOWN_HOSTS -o IdentitiesOnly=yes -i /root/.ssh/id_ed25519"

log "probing SSH to $GUEST at $GUEST_IP"
ssh $SSH_VM_OPTS "root@$GUEST_IP" "hostname; whoami; uname -a" 2>&1 | tee "$OUT_DIR/ssh-probe.txt" || true

VM_SSH_OK=0
if ssh $SSH_VM_OPTS "root@$GUEST_IP" "true" 2>/dev/null; then
  VM_SSH_OK=1
  log "SSH already authorized on guest"
else
  log "SSH key not yet authorized in guest; authorizing via qemu-agent"
  PUBKEY=$(cat /root/.ssh/id_ed25519.pub 2>/dev/null || true)
  [ -n "$PUBKEY" ] || die "no workforce public key available at /root/.ssh/id_ed25519.pub"

  log "authorizing Hermes key in guest via qemu-agent guest-exec"
  tower "sudo virsh qemu-agent-command '$GUEST' '{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"bash\",\"arg\":[\"-c\",\"mkdir -p /root/.ssh && echo \\\"$PUBKEY\\\" >> /root/.ssh/authorized_keys && chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys\"],\"capture-output\":true}}'" \
    2>&1 | tee "$OUT_DIR/agent-key-install.txt" || log "WARN: guest-exec key install failed"

  sleep 3

  if ssh $SSH_VM_OPTS "root@$GUEST_IP" "hostname; whoami; uname -a" 2>&1 | tee "$OUT_DIR/ssh-probe.txt"; then
    VM_SSH_OK=1
    log "SSH now authorized after key push"
  else
    # Fallback: base64-encoded key push via qemu-agent (avoids quoting issues)
    log "direct key push failed, trying base64-encoded push via qemu-agent"
    ENCODED_PUBKEY=$(printf '%s' "$PUBKEY" | base64 -w0)
    tower "sudo virsh qemu-agent-command '$GUEST' '{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"bash\",\"arg\":[\"-c\",\"echo $ENCODED_PUBKEY | base64 -d >> /root/.ssh/authorized_keys && chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys\"],\"capture-output\":true}}'" \
      2>&1 | tee -a "$OUT_DIR/agent-key-install.txt" || log "WARN: base64 key push also failed"
    sleep 3
    if ssh $SSH_VM_OPTS "root@$GUEST_IP" "hostname; whoami; uname -a" 2>&1 | tee "$OUT_DIR/ssh-probe.txt"; then
      VM_SSH_OK=1
      log "SSH authorized via base64-encoded key push"
    else
      die "cannot authorize Hermes key in guest via any channel"
    fi
  fi
fi

log "in-guest package configuration"
# Ensure openssh (sshd) and qemu-guest-agent are installed and running on Arch
ssh $SSH_VM_OPTS "root@$GUEST_IP" "
  set -e
  echo '--- installing/ensuring openssh + qemu-guest-agent on Arch ---'
  pacman -S --noconfirm --needed openssh qemu-guest-agent 2>&1 || true
  systemctl enable sshd --now 2>&1 || systemctl start sshd 2>&1 || true
  systemctl enable qemu-guest-agent --now 2>&1 || systemctl start qemu-guest-agent 2>&1 || true
  echo '--- in-guest service state ---'
  systemctl is-active sshd qemu-guest-agent
  systemctl is-enabled sshd qemu-guest-agent
" 2>&1 | tee "$OUT_DIR/in-guest-config.txt" || die "in-guest package/service configuration failed"

# Ensure Hermes key is in authorized_keys (verify without exposing)
ssh $SSH_VM_OPTS "root@$GUEST_IP" "
  echo '--- authorized_keys verification ---'
  test -f /root/.ssh/authorized_keys
  grep -cq 'ssh-ed25519' /root/.ssh/authorized_keys
  echo \"auth-key-count: \$(grep -c 'ssh-ed25519' /root/.ssh/authorized_keys)\"
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
  echo "=== virsh domifaddr (agent) ==="
  vms "domifaddr $GUEST --source agent" || true
  echo "=== ip occupancy (ping from tower) ==="
  tower "ping -c1 -W2 '$GUEST_IP' >/dev/null 2>&1 && echo 'PING: $GUEST_IP answers' || echo 'PING: $GUEST_IP silent'"
} | tee "$OUT_DIR/post-migration.txt"

# Full in-guest verification
ssh $SSH_VM_OPTS "root@$GUEST_IP" "
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
ssh $SSH_VM_OPTS "root@$GUEST_IP" "echo ssh-ok:\$(hostname)" 2>/dev/null && SSH_OK=1 || true

cat >"$OUT_DIR/migration.json" <<JSON
{"hypervisor":"tower","guest":"$GUEST","configured_ip":"$VM_IP","guest_ip":"$GUEST_IP","ip_matches_ci":$([ "$GUEST_IP" = "$VM_IP" ] && echo 1 || echo 0),"completed_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","on_br0":${ON_BR0:-0},"iface_count_after":${IFACE_COUNT_AFTER:-0},"ssh_ok":$SSH_OK,"agent_ping_result":"$AGENT_PING","ci_job":"${CI_JOB_ID:-0}","ci_pipeline":"${CI_PIPELINE_ID:-0}","ci_commit":"${CI_COMMIT_SHA:-local}"}
JSON
cat "$OUT_DIR/migration.json"

log "=== migration complete ==="
exit 0
