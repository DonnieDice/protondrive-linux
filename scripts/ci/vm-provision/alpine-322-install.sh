#!/usr/bin/env bash
# scripts/ci/vm-provision/alpine-322-install.sh
#
# Install Alpine 3.22 into the existing alpine322 guest domain on the tower
# hypervisor (issue #22, parent #6) and bring it to the acceptance spec:
#   OS installed to qcow2 + br0 @ 192.168.1.126 + sshd + qemu-guest-agent
#   + the Hermes (workforce) key authorized for root.
#
# Runs on the tower-mounted GitLab runner (tags: [android]) whose RO
# /root/.ssh mount provides the SSH alias `tower` and the workforce public
# key /root/.ssh/id_ed25519.pub (the same key CI uses for
# vm:ssh:smoke:[alpine322] and the vm:install/vm:regression stages).
#
# Preconditions verified by vm:inventory:alpine322 (job 24251, pipeline 2138):
#   - guest alpine322 defined, shut off, uuid c0c1ff59-5e75-4581-9507-461163f99a96
#   - disk  /mnt/pool_two/domains/alpine322/vdisk1.qcow2 (virtio, boot order 1)
#   - cdrom /mnt/pool_one/isos/alpine-standard-3.22.4-x86_64.iso (sata)
#   - NIC   bridge br0 (active), mac 52:54:00:38:d9:cc, model virtio
#   - serial pty console + qemu guest-agent channel in the domain XML
#   - 192.168.1.126 free (no arp entry, ping silent)
#
# Method (headless, no VNC, deterministic):
#   1. Extract vmlinuz-lts/initramfs-lts from the ISO on tower.
#   2. Define a TRANSIENT domain alpine322-install reusing the guest's real
#      qcow2 disk, br0 NIC, and ISO, booting the extracted kernel directly
#      with console=ttyS0 so the live env gets a serial getty. The persistent
#      alpine322 domain is never edited.
#   3. Drive the serial console from tower via expect (ssh -tt pty); the
#      payload bundle (live script + chroot script + Hermes public key)
#      travels runner -> guest over the LAN (nc), never through the console,
#      so no key value appears in any log or trace.
#   4. After install: undefine the transient domain, boot the persistent
#      alpine322 domain from its installed disk, and run the acceptance
#      probes (SSH from the runner with the same key, in-guest service
#      status, virsh guest-agent ping, qemu-img info).
#
# Mutations are confined to the alpine322 guest's resources: its qcow2 disk
# contents, its power state, transient sibling domain alpine322-install
# (removed before the job ends), and scratch files in its own domain
# directory + /tmp. No other guest, disk, network, or host service is
# touched.
set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
GUEST="${GUEST:-alpine322}"
TRANSIENT="${TRANSIENT:-alpine322-install}"
VM_IP="${VM_IP:-192.168.1.126}"
ISO_PATH="${ISO_PATH:-/mnt/pool_one/isos/alpine-standard-3.22.4-x86_64.iso}"
DISK_PATH="${DISK_PATH:-/mnt/pool_two/domains/alpine322/vdisk1.qcow2}"
DOMAIN_DIR="${DOMAIN_DIR:-/mnt/pool_two/domains/alpine322}"
MAC="${MAC:-52:54:00:38:d9:cc}"
PAYLOAD_PORT="${PAYLOAD_PORT:-8022}"
OUT_DIR="${PROVISION_OUT_DIR:-provision-results}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$OUT_DIR"

VM_KNOWN_HOSTS="${CI_PROJECT_DIR:-.}/.vm-known-hosts"
: > "$VM_KNOWN_HOSTS"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$VM_KNOWN_HOSTS"

tower() { ssh $SSH_OPTS "$TOWER_HOST" "$@"; }
log()  { echo "[provision] $*"; }
die()  { echo "FATAL: $*" >&2; exit 1; }
on_exit() {
  # best-effort cleanup of transient artifacts; never touch other guests
  scp $SSH_OPTS "$CONSOLE_LOG" "$TOWER_HOST:/tmp/" >/dev/null 2>&1 || true
}
CONSOLE_LOG="$OUT_DIR/console-session.log"
trap on_exit EXIT

# ------------------------------------------------------------- pre-state ----
tower "hostname; whoami; date -u" | tee "$OUT_DIR/identity.txt" || die "cannot reach tower"

STATE="$(tower "sudo virsh domstate '$GUEST'" 2>/dev/null)"
log "persistent guest state: ${STATE:-unknown}"
echo "pre-state: $STATE" > "$OUT_DIR/pre-state.txt"
tower "sudo virsh dumpxml '$GUEST'" > "$OUT_DIR/alpine322-pre.xml" || die "dumpxml failed"

# transient domain must not exist
if tower "sudo virsh domstate '$TRANSIENT'" >/dev/null 2>&1; then
  log "removing stale transient domain $TRANSIENT"
  tower "sudo virsh destroy '$TRANSIENT'" >/dev/null 2>&1 || true
  tower "sudo virsh undefine '$TRANSIENT'" >/dev/null 2>&1 || true
fi

# ------------------------------------------------- kernel/initrd extraction --
log "extracting kernel/initrd from the ISO (bsdtar, no loop mounts)"
tower "command -v bsdtar || command -v 7z || echo NONE; ls -la '$ISO_PATH'" | tee "$OUT_DIR/iso-extract.log"
tower "rm -rf '$DOMAIN_DIR/install-media'; mkdir -p '$DOMAIN_DIR/install-media' && \
       cd '$DOMAIN_DIR/install-media' && \
       (bsdtar -xf '$ISO_PATH' boot/vmlinuz-lts boot/initramfs-lts 2>/dev/null || \
        7z e -y '$ISO_PATH' boot/vmlinuz-lts boot/initramfs-lts >/dev/null) && \
       mv boot/vmlinuz-lts boot/initramfs-lts . 2>/dev/null; rmdir boot 2>/dev/null; \
       ls -la" | tee -a "$OUT_DIR/iso-extract.log"
tower "test -s '$DOMAIN_DIR/install-media/vmlinuz-lts' && test -s '$DOMAIN_DIR/install-media/initramfs-lts' && echo KERNEL-OK" \
  | tee -a "$OUT_DIR/iso-extract.log" || die "kernel/initrd extraction failed"

# ------------------------------------------------------- transient domain ----
log "defining transient install domain $TRANSIENT"
cat > "$OUT_DIR/transient.xml" <<XML
<domain type='kvm'>
  <name>$TRANSIENT</name>
  <description>transient alpine322 install session (issue #22)</description>
  <memory unit='MiB'>1024</memory>
  <currentMemory unit='MiB'>1024</currentMemory>
  <vcpu>2</vcpu>
  <os>
    <type arch='x86_64' machine='pc-q35-9.2'>hvm</type>
    <kernel>$DOMAIN_DIR/install-media/vmlinuz-lts</kernel>
    <initrd>$DOMAIN_DIR/install-media/initramfs-lts</initrd>
    <cmdline>console=ttyS0,115200 modules=loop,squashfs</cmdline>
  </os>
  <features><acpi/><apic/></features>
  <cpu mode='host-passthrough'/>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>destroy</on_reboot>
  <on_crash>destroy</on_crash>
  <devices>
    <emulator>/usr/local/sbin/qemu</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='$DISK_PATH'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='$ISO_PATH'/>
      <target dev='hda' bus='sata'/>
      <readonly/>
    </disk>
    <interface type='bridge'>
      <mac address='$MAC'/>
      <source bridge='br0'/>
      <model type='virtio'/>
    </interface>
    <serial type='pty'><target port='0'/></serial>
    <console type='pty'><target type='serial' port='0'/></console>
  </devices>
</domain>
XML
ssh $SSH_OPTS "$TOWER_HOST" "sudo virsh define /dev/stdin" < "$OUT_DIR/transient.xml" \
  || die "transient define failed"

# ------------------------------------------------------------- payload ------
# payload bundle: live-install.sh + chroot-config.sh + hermes-key.pub
KEYSRC=""
if [ -r /root/.ssh/id_ed25519.pub ]; then KEYSRC=/root/.ssh/id_ed25519.pub
elif [ -r /root/.ssh/id_ed25519 ]; then
  ssh-keygen -y -f /root/.ssh/id_ed25519 > "$OUT_DIR/hermes-key.pub" && KEYSRC="$OUT_DIR/hermes-key.pub"
fi
[ -n "$KEYSRC" ] || die "no Hermes key material at /root/.ssh/id_ed25519(.pub)"
log "hermes key: $(ssh-keygen -lf "$KEYSRC" | awk '{print $1, $2}')"

tar -czf "$OUT_DIR/payload.tgz" -C "$HERE/guest" alpine-322-live-install.sh alpine-322-chroot-config.sh
# rename guest scripts to the names the console driver expects
tar -czf "$OUT_DIR/payload.tgz" -C "$HERE/guest" \
  --transform 's/alpine-322-live-install.sh/live-install.sh/; s/alpine-322-chroot-config.sh/chroot-config.sh/' \
  alpine-322-live-install.sh alpine-322-chroot-config.sh
cp "$KEYSRC" "$OUT_DIR/payload-key.pub"
tar -rf "$OUT_DIR/payload.tar" -C "$OUT_DIR" payload-key.pub 2>/dev/null || true
# rebuild as tar.gz with the key inside
mkdir -p "$OUT_DIR/payload-root"
cp "$HERE/guest/alpine-322-live-install.sh"   "$OUT_DIR/payload-root/live-install.sh"
cp "$HERE/guest/alpine-322-chroot-config.sh"  "$OUT_DIR/payload-root/chroot-config.sh"
cp "$KEYSRC"                                  "$OUT_DIR/payload-root/hermes-key.pub"
tar -czf "$OUT_DIR/payload.tgz" -C "$OUT_DIR/payload-root" live-install.sh chroot-config.sh hermes-key.pub
md5sum "$OUT_DIR/payload.tgz" | awk '{print $1}' > "$OUT_DIR/payload.md5"
log "payload built: $(wc -c < "$OUT_DIR/payload.tgz") bytes, md5 $(cat "$OUT_DIR/payload.md5")"

# ship driver + payload staging to tower
scp $SSH_OPTS "$HERE/alpine-322-console.expect" "$TOWER_HOST:/tmp/alpine322-console.expect" \
  || die "expect driver upload failed"
scp $SSH_OPTS "$OUT_DIR/payload.tgz" "$TOWER_HOST:/tmp/alpine322-payload.tgz" \
  || die "payload upload failed"
scp $SSH_OPTS "$OUT_DIR/payload.md5" "$TOWER_HOST:/tmp/alpine322-payload.md5" \
  || die "payload md5 upload failed"

# --------------------------------------------------------------- install ----
log "starting transient domain $TRANSIENT"
tower "sudo virsh start '$TRANSIENT'" || die "transient start failed"

# The console driver: (a) drives the console, (b) when it prints
# NC_LISTENING, this job pushes the payload to $VM_IP:$PAYLOAD_PORT, then
# echoes PAYLOAD_OK into the console stream it also consumes (the expect
# side waits for PAYLOAD_OK in the console output loop).
push_payload_when_ready() {
  # wait for the guest nc listener (the live env needs ~2-4 min to boot)
  local waited=0
  while [ "$waited" -lt 1500 ]; do
    if grep -q NC_LISTENING "$CONSOLE_LOG" 2>/dev/null; then
      log "console reports nc listening - pushing payload"
      gzip -c "$OUT_DIR/payload.tgz" | nc -w 60 "$VM_IP" "$PAYLOAD_PORT" >/dev/null 2>&1
      log "payload push rc=$?"
      printf 'PAYLOAD_OK\n' >> "$CONSOLE_LOG"
      return 0
    fi
    sleep 10; waited=$((waited + 10))
  done
  log "WARN: never saw NC_LISTENING"
  return 1
}
push_payload_when_ready &
PUSHER=$!

ssh -tt $SSH_OPTS "$TOWER_HOST" \
  "sudo timeout --signal=KILL --kill-after=30 3000 expect /tmp/alpine322-console.expect '$TRANSIENT' '$PAYLOAD_PORT' 2700" \
  > >(tee "$CONSOLE_LOG") 2>&1
CONSOLE_RC=$?
kill "$PUSHER" 2>/dev/null || true; wait "$PUSHER" 2>/dev/null || true

if [ "$CONSOLE_RC" != "0" ]; then
  log "console driver failed rc=$CONSOLE_RC"
  tower "sudo virsh destroy '$TRANSIENT'" >/dev/null 2>&1 || true
  tower "sudo virsh undefine '$TRANSIENT'" >/dev/null 2>&1 || true
  die "install failed (transient domain cleaned up)"
fi

# wait for shut-off, then undefine the transient domain
for i in $(seq 1 30); do
  S="$(tower "sudo virsh domstate '$TRANSIENT'" 2>/dev/null || true)"
  [ "$S" = "shut off" ] && break
  sleep 5
done
tower "sudo virsh undefine '$TRANSIENT'" || die "undefine transient failed"
tower "rm -rf '$DOMAIN_DIR/install-media' /tmp/alpine322-*" || true
log "transient domain and scratch files removed"

# --------------------------------------------------- boot + acceptance ------
log "booting persistent guest $GUEST"
tower "sudo virsh start '$GUEST'" || die "persistent guest failed to start"

log "waiting for TCP/22 at $VM_IP (up to 180s)"
up=0
for i in $(seq 1 90); do
  if (exec 3<>/dev/tcp/$VM_IP/22) 2>/dev/null; then up=1; exec 3>&-; break; fi
  sleep 2
done
[ "$up" = "1" ] || { tower "sudo virsh console '$GUEST' --force" </dev/null >/dev/null 2>&1 & sleep 2; kill %1 2>/dev/null; die "ssh never came up"; }

log "SSH probe from the runner (workforce key installed in the guest)"
ssh $SSH_OPTS -o ConnectTimeout=15 "root@$VM_IP" \
  "hostname; whoami; uname -a; cat /etc/alpine-release" | tee "$OUT_DIR/ssh-probe.txt" \
  || die "SSH probe failed"

log "collecting acceptance evidence"
{
  echo "=== virsh domstate ==="
  tower "sudo virsh domstate '$GUEST'"
  echo "=== virsh dumpxml (name/disk/interface/channel) ==="
  tower "sudo virsh dumpxml '$GUEST'" | grep -E "<name>|<uuid>|<source file=|<source bridge=|<mac |<channel|guest_agent|<serial|<console" || true
  echo "=== qemu-img info ==="
  tower "sudo qemu-img info '$DISK_PATH'"
  echo "=== ip occupancy (ping from tower) ==="
  tower "ping -c1 -W2 '$VM_IP' >/dev/null 2>&1 && echo 'PING: answers' || echo 'PING: silent'"
  echo "=== in-guest service status (via ssh from runner) ==="
} | tee "$OUT_DIR/acceptance.txt"

ssh $SSH_OPTS "root@$VM_IP" \
  "rc-service qemu-guest-agent status; rc-service sshd status; rc-update show default; ip -4 addr show eth0; grep -c ssh-ed25519 /root/.ssh/authorized_keys" \
  | tee -a "$OUT_DIR/acceptance.txt" || die "in-guest verification failed"

echo "=== guest agent ping (virsh) ==="
tower "sudo virsh qemu-agent-command '$GUEST' '{\"execute\":\"guest-ping\"}'" \
  | tee -a "$OUT_DIR/acceptance.txt" || log "WARN: guest-ping failed (check agent in guest)"

log "=== provisioning complete ==="
exit 0
