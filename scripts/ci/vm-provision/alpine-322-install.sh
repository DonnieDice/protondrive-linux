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
#   - disk source /mnt/pool_two/domains/alpine322/vdisk1.qcow2 (virtio, boot 1)
#   - cdrom /mnt/pool_one/isos/alpine-standard-3.22.4-x86_64.iso (sata)
#   - NIC   bridge br0 (active), mac 52:54:00:38:d9:cc, model virtio
#   - serial pty console + qemu guest-agent channel in the domain XML
#   - 192.168.1.126 free (no arp entry, ping silent)
#   NOTE: the domain XML names the disk but the qcow2 FILE was found absent
#   on 2026-09-28 (job 25028: "Cannot access storage file ... No such file or
#   directory"). Issue #22 scope explicitly authorizes creating the qcow2
#   disk, so this job creates it (32G sparse) when missing, after recording
#   the pre-state. No existing file is ever overwritten.
#
# Method (headless, no VNC, deterministic):
#   1. Preflight: record domain-dir contents; create the qcow2 if absent.
#   2. Extract vmlinuz-lts/initramfs-lts from the ISO on tower (bsdtar).
#   3. Define a TRANSIENT domain alpine322-install reusing the guest's real
#      qcow2 disk, br0 NIC, and ISO, booting the extracted kernel directly
#      with console=ttyS0 so the live env gets a serial getty (Alpine's
#      initramfs spawns gettys for every console= param). The persistent
#      alpine322 domain XML is never edited.
#   4. Drive the serial console from the RUNNER via expect (the runner
#      image apk-adds expect; tower has none - job 25177 failed rc=127 when
#      the driver ran there). The pty chain is: expect (runner) -> ssh -tt
#      tower -> sudo virsh console (real pty on tower) -> guest ttyS0. The
#      payload bundle (live script + chroot script + Hermes public key)
#      travels runner -> guest over the LAN (nc), never through the console,
#      so no key value appears in any console log or CI trace. The guest
#      verifies the payload md5 before exploding it.
#   5. Live install: static LAN 192.168.1.126/24, hostname, sshd, then
#      setup-disk -m sys to /dev/vda (ERASE_DISKS/SWAP_SIZE make it
#      non-interactive). setup-disk replicates the live env's /etc config,
#      apk world, and runlevels onto the target.
#   6. Chroot post-config: qemu-guest-agent + enabled, Hermes key as sole
#      root login (password locked, PermitRootLogin prohibit-password),
#      serial getty, boot services.
#   7. Undefine the transient domain, boot the persistent alpine322 domain
#      from its installed disk, and run the acceptance probes (SSH from the
#      runner with the same key, in-guest service status, virsh guest-ping,
#      qemu-img info).
#
# Mutations are confined to the alpine322 guest's resources: its qcow2 disk
# file (created when absent), disk contents, power state, the transient
# sibling domain alpine322-install (removed before the job ends), and
# scratch files in its own domain directory + tower /tmp. No other guest,
# disk, network, or host service is touched.
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
DISK_SIZE="${DISK_SIZE:-32G}"
OUT_DIR="${PROVISION_OUT_DIR:-provision-results}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$OUT_DIR"
# absolute path: the expect driver's log_file and the pusher's grep both run
# from the same CWD, but an absolute CONSOLE_LOG also survives any cd.
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

VM_KNOWN_HOSTS="${CI_PROJECT_DIR:-.}/.vm-known-hosts"
: > "$VM_KNOWN_HOSTS"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$VM_KNOWN_HOSTS"

tower() { ssh $SSH_OPTS "$TOWER_HOST" "$@"; }
log()  { echo "[provision] $*"; }
die()  { echo "FATAL: $*" >&2; exit 1; }
CONSOLE_LOG="$OUT_DIR/console-session.log"

cleanup() {
  # best-effort; never touch other guests. Record final transient state.
  tower "sudo virsh destroy '$TRANSIENT' 2>/dev/null; sudo virsh undefine '$TRANSIENT' 2>/dev/null; \
         rm -rf '$DOMAIN_DIR/install-media' /tmp/alpine322-payload.*" \
    >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ------------------------------------------------------------- pre-state ----
tower "hostname; whoami; date -u" | tee "$OUT_DIR/identity.txt" || die "cannot reach tower"

STATE="$(tower "sudo virsh domstate '$GUEST'" 2>/dev/null)"
log "persistent guest state: ${STATE:-unknown}"
{ echo "pre-state: $STATE"; tower "sudo virsh dumpxml '$GUEST'"; } > "$OUT_DIR/pre-state.txt" \
  || die "dumpxml failed"

# transient domain must not exist
if tower "sudo virsh domstate '$TRANSIENT'" >/dev/null 2>&1; then
  log "removing stale transient domain $TRANSIENT"
  tower "sudo virsh destroy '$TRANSIENT'" >/dev/null 2>&1 || true
  tower "sudo virsh undefine '$TRANSIENT'" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------- disk preflight/create --
log "domain dir contents before any change:"
tower "ls -la '$DOMAIN_DIR/'" | tee "$OUT_DIR/disk-preflight.txt"

# search for any alpine322 disk that may live elsewhere (record only)
tower "find /mnt/pool_one /mnt/pool_two /mnt/user/domains -maxdepth 3 -iname '*alpine*322*' 2>/dev/null; true" \
  | tee -a "$OUT_DIR/disk-preflight.txt"

if tower "test -s '$DISK_PATH'"; then
  log "disk exists"
  tower "sudo qemu-img info '$DISK_PATH'" | tee -a "$OUT_DIR/disk-preflight.txt"
else
  log "disk $DISK_PATH ABSENT - creating fresh qcow2 ($DISK_SIZE, sparse; authorized by issue scope)"
  tower "sudo qemu-img create -f qcow2 '$DISK_PATH' '$DISK_SIZE'" | tee -a "$OUT_DIR/disk-preflight.txt" \
    || die "qemu-img create failed"
  tower "sudo qemu-img info '$DISK_PATH'" | tee -a "$OUT_DIR/disk-preflight.txt"
fi

# ------------------------------------------------- kernel/initrd extraction --
log "extracting kernel/initrd from the ISO (bsdtar, no loop mounts)"
tower "command -v bsdtar; ls -la '$ISO_PATH'" | tee "$OUT_DIR/iso-extract.log"
tower "rm -rf '$DOMAIN_DIR/install-media'; mkdir -p '$DOMAIN_DIR/install-media' && \
       cd '$DOMAIN_DIR/install-media' && \
       bsdtar -xf '$ISO_PATH' boot/vmlinuz-lts boot/initramfs-lts && \
       mv boot/vmlinuz-lts boot/initramfs-lts . && rmdir boot && ls -la" | tee -a "$OUT_DIR/iso-extract.log"
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
KEYSRC=""
if [ -r /root/.ssh/id_ed25519.pub ]; then KEYSRC=/root/.ssh/id_ed25519.pub
elif [ -r /root/.ssh/id_ed25519 ]; then
  ssh-keygen -y -f /root/.ssh/id_ed25519 > "$OUT_DIR/hermes-key.pub" && KEYSRC="$OUT_DIR/hermes-key.pub"
fi
[ -n "$KEYSRC" ] || die "no Hermes key material at /root/.ssh/id_ed25519(.pub)"
log "hermes key: $(ssh-keygen -lf "$KEYSRC" | awk '{print $1, $2}')"

# bundle: live-install.sh + chroot-config.sh + hermes-key.pub (busybox-tar safe)
rm -rf "$OUT_DIR/payload-root"; mkdir -p "$OUT_DIR/payload-root"
cp "$HERE/guest/alpine-322-live-install.sh"  "$OUT_DIR/payload-root/live-install.sh"
cp "$HERE/guest/alpine-322-chroot-config.sh" "$OUT_DIR/payload-root/chroot-config.sh"
cp "$KEYSRC"                                 "$OUT_DIR/payload-root/hermes-key.pub"
tar -czf "$OUT_DIR/payload.tgz" -C "$OUT_DIR/payload-root" live-install.sh chroot-config.sh hermes-key.pub \
  || die "payload tar failed"
md5sum "$OUT_DIR/payload.tgz" | awk '{print $1}' > "$OUT_DIR/payload.md5"
PAYLOAD_MD5="$(cat "$OUT_DIR/payload.md5")"
log "payload built: $(wc -c < "$OUT_DIR/payload.tgz") bytes, md5 $PAYLOAD_MD5"

# Key-identity guard (sibling #21 job 26864 failed its final SSH probe with
# "Permission denied (publickey,...)" after installing the mounted
# id_ed25519.pub into the guest): derive the public half FROM THE PRIVATE KEY
# the runner will actually offer during the acceptance probe and install THAT
# in the guest. If a stale .pub file ever diverges from the private key, the
# probe now uses exactly the derived key, so the .pub can no longer desync
# the guest's authorized_keys from the offered identity. The derivation also
# proves the private key parses before the 45-minute install begins.
ssh-keygen -y -f /root/.ssh/id_ed25519 > "$OUT_DIR/hermes-key-derived.pub" \
  || die "cannot derive public key from /root/.ssh/id_ed25519 (missing/corrupt private key)"
cmp -s "$OUT_DIR/hermes-key-derived.pub" "$KEYSRC" \
  || log "WARN: /root/.ssh/id_ed25519.pub differs from key derived from id_ed25519 - installing the derived key"
cp "$OUT_DIR/hermes-key-derived.pub" "$OUT_DIR/payload-root/hermes-key.pub"
tar -czf "$OUT_DIR/payload.tgz" -C "$OUT_DIR/payload-root" live-install.sh chroot-config.sh hermes-key.pub \
  || die "payload tar rebuild failed"
md5sum "$OUT_DIR/payload.tgz" | awk '{print $1}' > "$OUT_DIR/payload.md5"
PAYLOAD_MD5="$(cat "$OUT_DIR/payload.md5")"
log "payload rebuilt with derived key: $(wc -c < "$OUT_DIR/payload.tgz") bytes, md5 $PAYLOAD_MD5"

# ship payload staging to tower (RELAY FALLBACK ONLY: the primary route is the
# direct runner -> guest LAN push below; if that LAN path is blocked, the
# console driver dies at the md5 check and the job surfaces the failure)
scp $SSH_OPTS "$OUT_DIR/payload.tgz" "$TOWER_HOST:/tmp/alpine322-payload.tgz" \
  || die "payload upload failed"

# --------------------------------------------------------------- install ----
log "starting transient domain $TRANSIENT"
tower "sudo virsh start '$TRANSIENT'" || die "transient start failed"

# Push the payload over the LAN when the guest signals (on the console) that
# its nc listener is up. The signal marker is echoed as NC_RE""ADY so the
# console echo of the command itself can never match the grep.
# NOTE: send the tarball RAW. The guest md5-checks /tmp/payload.tgz (the file
# nc wrote) against $PAYLOAD_MD5 (md5 of the tarball on the runner); piping
# through gzip -c would change every byte and guarantee a MD5_MISMATCH (the
# first run of job 25904 corrupted exactly this way).
push_payload_when_ready() {
  local waited=0
  while [ "$waited" -lt 1500 ]; do
    if grep -q 'NC_READY' "$CONSOLE_LOG" 2>/dev/null; then
      log "console reports guest nc listening - pushing payload"
      nc -w 120 "$VM_IP" "$PAYLOAD_PORT" < "$OUT_DIR/payload.tgz" >/dev/null 2>&1
      log "payload push rc=$?"
      return 0
    fi
    sleep 10; waited=$((waited + 10))
  done
  log "WARN: never saw NC_READY"
  return 1
}
push_payload_when_ready &
PUSHER=$!

# Drive the console from the RUNNER: expect runs here (apk-added in the job
# image) inside a pty allocated by the CI shell, reaching the guest's serial
# console through tower: expect -> ssh -tt tower -> sudo virsh console.
# (tower has no expect binary - job 25177 proved that route fails rc=127 -
# so the driver must run on the runner.) The runner-side driver also keeps
# the pty chain honest: expect's own pty feeds ssh -tt, which gives virsh
# console a real controlling pty on tower.
# VM_KNOWN_HOSTS must be exported so expect's spawn sees it.
# The driver writes console-session.log itself via log_file (absolute path
# passed in CONSOLE_LOG); expect stdout redirected to a file is kept as a
# secondary artifact. The pusher greps $CONSOLE_LOG, which log_file flushes
# per read - expect's own stdout piped through tee is block-buffered, so the
# pusher could otherwise wait past its budget on a marker the guest printed
# minutes earlier (job 25904 hung exactly here).
export VM_KNOWN_HOSTS
export CONSOLE_LOG
expect "$HERE/alpine-322-console.tcl" "$TRANSIENT" "$PAYLOAD_PORT" "$PAYLOAD_MD5" 2700 \
  > "$OUT_DIR/expect-stdout.log" 2>&1
CONSOLE_RC=$?
cat "$OUT_DIR/expect-stdout.log"
kill "$PUSHER" 2>/dev/null || true; wait "$PUSHER" 2>/dev/null || true

if [ "$CONSOLE_RC" != "0" ]; then
  log "console driver failed rc=$CONSOLE_RC (transient domain cleanup happens via trap)"
  die "install failed"
fi

# wait for shut-off, then undefine the transient domain
for i in $(seq 1 30); do
  S="$(tower "sudo virsh domstate '$TRANSIENT'" 2>/dev/null || true)"
  [ "$S" = "shut off" ] && break
  sleep 5
done
tower "sudo virsh undefine '$TRANSIENT'" || die "undefine transient failed"
tower "rm -rf '$DOMAIN_DIR/install-media'" || true
log "transient domain and scratch files removed"

# --------------------------------------------------- boot + acceptance ------
log "booting persistent guest $GUEST"
tower "sudo virsh start '$GUEST'" || die "persistent guest failed to start"

log "waiting for TCP/22 at $VM_IP (up to 180s)"
up=0
for i in $(seq 1 90); do
  if (exec 3<>"/dev/tcp/$VM_IP/22") 2>/dev/null; then up=1; exec 3>&-; break; fi
  sleep 2
done
[ "$up" = "1" ] || die "sshd never came up at $VM_IP"

# SSH probe from the runner. Normalized identity transport, mirroring
# scripts/ci/lib/_vm_common.sh (the transport the vm:regression stages use):
#   - copy the mounted private key to a temp file, chmod 600 (the RO
#     /root/.ssh mount can carry group/world perms that make ssh silently
#     skip a DEFAULT identity - explicit -i would at least fail loudly)
#   - IdentitiesOnly + explicit -i: offer exactly the key whose public half
#     was installed in the guest (derived above), never agent/config keys
#   - -F /dev/null: the mounted ssh config cannot inject other options for
#     this IP-based connection (aliases stay untouched for other jobs)
# Sibling #21's job 26864 failed its probe with "Permission denied
# (publickey,...)" after installing the mounted id_ed25519.pub and probing
# with default-identity discovery; either a stale .pub or a skipped
# identity produces exactly that. This probe eliminates both: the derived
# key pins authorized_keys to the offered identity, and the temp-copy pins
# the offered identity's permissions.
VM_KEY_TMP="$(mktemp)"
cp /root/.ssh/id_ed25519 "$VM_KEY_TMP"
sed -i 's/\r$//' "$VM_KEY_TMP"
[ -n "$(tail -c1 "$VM_KEY_TMP" 2>/dev/null)" ] && printf '\n' >>"$VM_KEY_TMP"
chmod 600 "$VM_KEY_TMP"
# extend the EXIT trap instead of replacing it: the first trap (cleanup)
# still destroys the transient domain if this script dies mid-probe.
trap 'rm -f "$VM_KEY_TMP"; cleanup' EXIT
GUEST_SSH_OPTS="-F /dev/null -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$VM_KNOWN_HOSTS -i $VM_KEY_TMP -o IdentitiesOnly=yes"
log "SSH probe from the runner (workforce key installed in the guest)"
ssh $GUEST_SSH_OPTS "root@$VM_IP" \
  "hostname; whoami; uname -a; cat /etc/alpine-release" | tee "$OUT_DIR/ssh-probe.txt" \
  || die "SSH probe failed"

log "collecting acceptance evidence"
{
  echo "=== virsh domstate ==="
  tower "sudo virsh domstate '$GUEST'"
  echo "=== virsh dumpxml (key facts) ==="
  tower "sudo virsh dumpxml '$GUEST'" | grep -E "<name>|<uuid>|<source file=|<source bridge=|<mac |<channel|guest_agent|<serial|<console" || true
  echo "=== qemu-img info ==="
  tower "sudo qemu-img info '$DISK_PATH'"
  echo "=== ip occupancy (ping from tower) ==="
  tower "ping -c1 -W2 '$VM_IP' >/dev/null 2>&1 && echo 'PING: answers' || echo 'PING: silent'"
  echo "=== in-guest service status (via ssh from runner) ==="
} | tee "$OUT_DIR/acceptance.txt"

ssh $GUEST_SSH_OPTS "root@$VM_IP" \
  "rc-service qemu-guest-agent status; rc-service sshd status; rc-update show default; ip -4 addr show eth0; grep -c ssh-ed25519 /root/.ssh/authorized_keys" \
  | tee -a "$OUT_DIR/acceptance.txt" || die "in-guest verification failed"

echo "=== guest agent ping (virsh) ==="
tower "sudo virsh qemu-agent-command '$GUEST' '{\"execute\":\"guest-ping\"}'" \
  | tee -a "$OUT_DIR/acceptance.txt" || log "WARN: guest-ping failed (check agent in guest)"

log "=== provisioning complete ==="
exit 0
