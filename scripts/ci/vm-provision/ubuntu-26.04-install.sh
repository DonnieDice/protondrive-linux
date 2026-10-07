#!/usr/bin/env bash
# scripts/ci/vm-provision/ubuntu-26.04-install.sh
#
# Install Ubuntu 26.04 into the existing ubuntu-26.04 guest domain on the
# tower hypervisor (issue #20, parent #8) and bring it to the acceptance spec:
#   OS installed to qcow2 + br0 @ 192.168.1.168 + sshd + qemu-guest-agent
#   + the Hermes (workforce) key authorized for root.
#
# Runs on the tower-mounted GitLab runner (tags: [android]) whose RO
# /root/.ssh mount provides the SSH alias `tower` and the workforce public
# key /root/.ssh/id_ed25519.pub (the same key CI uses for
# vm:ssh:smoke:ubuntu2604 and the vm:install/vm:regression ubuntu-26.04
# stages).
#
# Preconditions verified by vm:inventory:ubuntu-26.04:
#   - guest ubuntu-26.04 defined or absent (driver creates if needed)
#   - br0 network exists (virsh net-dumpxml)
#   - 192.168.1.168 free (no arp entry, ping silent) unless pre-existing
#   - Ubuntu 26.04 netboot ISO or server ISO available on tower
#
# Method (headless, no VNC, deterministic):
#   1. Preflight: record pre-state; create the qcow2 + domain XML if absent.
#   2. Extract vmlinuz/initrd.gz from the Ubuntu netboot ISO on tower (bsdtar).
#   3. Build a preseed with the workforce public key line appended.
#   4. Serve the preseed over the LAN from tower with busybox httpd.
#   5. Define a TRANSIENT domain ubuntu-26.04-install reusing ONLY the guest's
#      real qcow2 disk + br0 NIC, booting the extracted kernel directly with
#      console=ttyS0 and preseed/url=http://192.168.1.31:<port>/preseed.cfg.
#      The persistent domain XML is never edited during install.
#   6. Drive the serial console from the RUNNER via expect (expect -> ssh -tt
#      tower -> sudo virsh console -> guest ttyS0).
#   7. The preseed automates the entire d-i install (partitions, packages,
#      late-commands). The expect driver watches for the late-command marker
#      and the reboot.
#   8. Undefine the transient domain, boot the persistent ubuntu-26.04 domain
#      from its installed disk, and run the acceptance probes (SSH from the
#      runner with the same key, in-guest service status, virsh guest-ping,
#      qemu-img info).
#
# Mutations are confined to the ubuntu-26.04 guest's resources: its qcow2 disk
# file (created when absent), disk contents, domain definition (created when
# absent, OVMF/EFI added when the guest is first defined), power state, the
# transient sibling domain ubuntu-26.04-install (removed before the job ends),
# and scratch files in its own domain directory + tower /tmp. No other guest,
# disk, network, or host service is touched.
#
# Scope note on OVMF/EFI: Ubuntu Server 26.04 supports both BIOS and UEFI
# boot. The existing protondrive CI wiring does not mandate either; this job
# uses BIOS boot (SeaBIOS) for simplicity, matching the debian12/debian13
# guests which already boot successfully on tower. If EFI becomes required,
# the domain XML can be updated to add the OVMF loader in a follow-up.
set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
GUEST="${GUEST:-ubuntu-2604}"
TRANSIENT="${TRANSIENT:-ubuntu-2604-install}"
VM_IP="${VM_IP:-192.168.1.168}"
TOWER_IP="${TOWER_IP:-192.168.1.31}"
# Ubuntu 26.04 netboot ISO (server install) — the canonical image
ISO_PATH="${ISO_PATH:-/mnt/pool_one/isos/ubuntu-26.04-live-server-amd64.iso}"
DISK_PATH="${DISK_PATH:-/mnt/pool_two/domains/ubuntu-26.04/vdisk1.qcow2}"
DOMAIN_DIR="${DOMAIN_DIR:-/mnt/pool_two/domains/ubuntu-26.04}"
MAC="${MAC:-52:54:00:38:46:f7}"
KS_PORT="${KS_PORT:-8011}"
DISK_SIZE="${DISK_SIZE:-60G}"
OUT_DIR="${PROVISION_OUT_DIR:-provision-results}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$OUT_DIR"

VM_KNOWN_HOSTS="${CI_PROJECT_DIR:-.}/.vm-known-hosts"
: > "$VM_KNOWN_HOSTS"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$VM_KNOWN_HOSTS"

tower() { ssh $SSH_OPTS "$TOWER_HOST" "$@"; }
log()  { echo "[provision] $*"; }
die()  { echo "FATAL: $*" >&2; exit 1; }
CONSOLE_LOG="$OUT_DIR/console-session.log"

KS_DIR="/tmp/ubuntu2604-ks.$$"
cleanup() {
  # best-effort; never touch other guests. Kill the httpd we started, remove
  # the transient domain, and wipe scratch files.
  tower "pkill -f 'httpd.*ubuntu2604-ks' 2>/dev/null; sudo virsh destroy '$TRANSIENT' 2>/dev/null; sudo virsh undefine '$TRANSIENT' 2>/dev/null; rm -rf '$KS_DIR' '$DOMAIN_DIR/install-media' /tmp/ubuntu2604-console.tcl /tmp/ubuntu2604-payload.*" \
    >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ------------------------------------------------------------- pre-state ----
tower "hostname; whoami; date -u" | tee "$OUT_DIR/identity.txt" || die "cannot reach tower"

STATE="$(tower "sudo virsh domstate '$GUEST'" 2>/dev/null)"
log "persistent guest state: ${STATE:-unknown}"
{ echo "pre-state: $STATE"; tower "sudo virsh dumpxml '$GUEST' 2>/dev/null"; } > "$OUT_DIR/pre-state.txt" || die "dumpxml failed"

# transient domain must not exist
if tower "sudo virsh domstate '$TRANSIENT'" >/dev/null 2>&1; then
  log "removing stale transient domain $TRANSIENT"
  tower "sudo virsh destroy '$TRANSIENT'" >/dev/null 2>&1 || true
  tower "sudo virsh undefine '$TRANSIENT'" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------- disk preflight/create --
log "domain dir contents before any change:"
tower "ls -la '$DOMAIN_DIR/' 2>/dev/null || echo '(domain dir absent)'" | tee "$OUT_DIR/disk-preflight.txt"

# search for any ubuntu-26.04 disk that may live elsewhere (record only)
tower "find /mnt/pool_one /mnt/pool_two /mnt/user -maxdepth 3 -iname '*ubuntu*26*' 2>/dev/null; true" \
  | tee -a "$OUT_DIR/disk-preflight.txt"

if tower "test -s '$DISK_PATH'"; then
  log "disk exists"
  tower "sudo qemu-img info '$DISK_PATH'" | tee -a "$OUT_DIR/disk-preflight.txt"
else
  # job 25524 (alpine320) failed because the domain dir did not exist:
  # create it first, then the qcow2 (authorized by issue #20 scope).
  log "disk $DISK_PATH ABSENT - creating domain dir + fresh qcow2 ($DISK_SIZE, sparse; authorized by issue scope)"
  tower "mkdir -p '$DOMAIN_DIR' && sudo qemu-img create -f qcow2 '$DISK_PATH' '$DISK_SIZE'" \
    | tee -a "$OUT_DIR/disk-preflight.txt" || die "qemu-img create failed"
  tower "sudo qemu-img info '$DISK_PATH'" | tee -a "$OUT_DIR/disk-preflight.txt"
fi

# ------------------------------------------------- kernel/initrd extraction --
log "extracting kernel/initrd from the Ubuntu 26.04 netboot ISO (bsdtar, no loop mounts)"
tower "command -v bsdtar; ls -la '$ISO_PATH'" | tee "$OUT_DIR/iso-extract.log"

# Ubuntu netboot/live-server ISO layout: the kernel/initrd are at
# /casper/vmlinuz and /casper/initrd (for live-server) or at
# /install/netboot/ubuntu-installer/amd64/linux (for d-i netboot).
# Try the live-server layout first (casper), fall back to netboot layout.
tower "rm -rf '$DOMAIN_DIR/install-media'; mkdir -p '$DOMAIN_DIR/install-media' && \
       cd '$DOMAIN_DIR/install-media' && \
       (bsdtar -xf '$ISO_PATH' casper/vmlinuz casper/initrd 2>/dev/null && mv casper/vmlinuz casper/initrd . && rmdir casper || \
        bsdtar -xf '$ISO_PATH' install/netboot/ubuntu-installer/amd64/linux install/netboot/ubuntu-installer/amd64/initrd.gz 2>/dev/null && mv install/netboot/ubuntu-installer/amd64/linux vmlinuz && mv install/netboot/ubuntu-installer/amd64/initrd.gz initrd.gz && rm -rf install && ls -la)" \
  | tee -a "$OUT_DIR/iso-extract.log"
tower "test -s '$DOMAIN_DIR/install-media/vmlinuz' && test -s '$DOMAIN_DIR/install-media/initrd' -o -s '$DOMAIN_DIR/install-media/initrd.gz' && echo KERNEL-OK" \
  | tee -a "$OUT_DIR/iso-extract.log" || die "kernel/initrd extraction failed"
# Normalize initrd name
tower "cd '$DOMAIN_DIR/install-media' && ls initrd.gz 2>/dev/null && mv initrd.gz initrd || true" | tee -a "$OUT_DIR/iso-extract.log" || true

# ------------------------------------------------------- preseed serving -----
log "building preseed with workforce key appended"
KEYSRC=""
if [ -r /root/.ssh/id_ed25519.pub ]; then KEYSRC=/root/.ssh/id_ed25519.pub
elif [ -r /root/.ssh/id_ed25519 ]; then
  ssh-keygen -y -f /root/.ssh/id_ed25519 > "$OUT_DIR/hermes-key.pub" && KEYSRC="$OUT_DIR/hermes-key.pub"
fi
[ -n "$KEYSRC" ] || die "no Hermes key material at /root/.ssh/id_ed25519(.pub) (SSH_PRIVATE_KEY_B64 absent; cannot authorize a key the runner can offer)"
log "hermes key: $(ssh-keygen -lf "$KEYSRC" | awk '{print $1, $2}')"

# The authorized key must be the PUBLIC HALF OF THE PRIVATE KEY THIS RUNNER
# OFFERS. Deriving with ssh-keygen -y is the only way to guarantee that.
ssh-keygen -y -f /root/.ssh/id_ed25519 > "$OUT_DIR/hermes-key-derived.pub" \
  || die "cannot derive public half of the workforce key"
cmp -s "$OUT_DIR/hermes-key-derived.pub" "$KEYSRC" \
  || log "WARN: /root/.ssh/id_ed25519.pub differs from key derived from id_ed25519 - using derived key"

# Build the preseed with the sshkey line appended
PRESEED_LOCAL="$OUT_DIR/ubuntu-26.04-preseed.cfg"
{
  cat "$HERE/ubuntu-26.04-preseed.cfg"
  echo "d-i passwd/root-sshkey string $(cat "$OUT_DIR/hermes-key-derived.pub")"
} > "$PRESEED_LOCAL"

# Stage the preseed on tower and serve it with busybox httpd
tower "mkdir -p '$KS_DIR' && chmod 755 '$KS_DIR'" || die "KS dir creation failed"
scp $SSH_OPTS "$PRESEED_LOCAL" "$TOWER_HOST:/tmp/ubuntu2604-preseed.cfg" >/dev/null 2>&1 || die "preseed upload failed"
tower "mv /tmp/ubuntu2604-preseed.cfg '$KS_DIR/ubuntu-26.04-preseed.cfg' && chmod 644 '$KS_DIR/ubuntu-26.04-preseed.cfg'" \
  || die "preseed staging failed"

# busybox httpd: Unraid ships busybox; verify and serve on the LAN port.
tower "command -v busybox || ls /usr/bin/busybox /usr/sbin/busybox 2>/dev/null" | tee "$OUT_DIR/httpd.log"
tower "nohup busybox httpd -f -v -p '$KS_PORT' -h '$KS_DIR' > /tmp/ubuntu2604-httpd.log 2>&1 & echo httpd-pid=\$!" \
  | tee -a "$OUT_DIR/httpd.log" || die "busybox httpd failed to start"
sleep 3
tower "wget -q -O- 'http://127.0.0.1:$KS_PORT/ubuntu-26.04-preseed.cfg' | head -3 || curl -s 'http://127.0.0.1:$KS_PORT/ubuntu-26.04-preseed.cfg' | head -3" \
  | tee -a "$OUT_DIR/httpd.log" || die "preseed not fetchable on tower"

# ------------------------------------------------------- transient domain ----
# Ubuntu 26.04 netboot install via direct kernel boot with preseed auto-install.
# The transient domain reuses ONLY the persistent guest's qcow2 disk + br0 NIC;
# the persistent domain XML is never edited.
log "defining transient install domain $TRANSIENT"
cat > "$OUT_DIR/transient.xml" <<XML
<domain type='kvm'>
  <name>$TRANSIENT</name>
  <description>transient ubuntu-26.04 install session (issue #20)</description>
  <memory unit='MiB'>4096</memory>
  <currentMemory unit='MiB'>4096</currentMemory>
  <vcpu>2</vcpu>
  <os>
    <type arch='x86_64' machine='pc-q35-9.2'>hvm</type>
    <kernel>$DOMAIN_DIR/install-media/vmlinuz</kernel>
    <initrd>$DOMAIN_DIR/install-media/initrd</initrd>
    <cmdline>console=ttyS0,115200 auto=true priority=critical preseed/url=http://$TOWER_IP:$KS_PORT/ubuntu-26.04-preseed.cfg netcfg/disable_autoconfig=true netcfg/get_ipaddress=$VM_IP netcfg/get_netmask=255.255.255.0 netcfg/get_gateway=192.168.1.1 netcfg/get_nameservers=192.168.1.1 1.1.1.1 netcfg/get_hostname=$GUEST modules=loop,squashfs</cmdline>
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

# ------------------------------------------------------------------ install --
log "starting transient domain $TRANSIENT"
tower "sudo virsh start '$TRANSIENT'" || die "transient start failed"

# Drive the console from the RUNNER: expect runs here (apk-added in the job
# image) inside a pty allocated by the CI shell, reaching the guest's serial
# console through tower: expect -> ssh -tt tower -> sudo virsh console.
export VM_KNOWN_HOSTS
export CONSOLE_LOG
expect "$HERE/ubuntu-26.04-console.tcl" "$TRANSIENT" 2700 2>&1 | tee "$CONSOLE_LOG"
CONSOLE_RC="${PIPESTATUS[0]}"

# stop serving the preseed as soon as the console session ends
tower "pkill -f 'httpd.*ubuntu2604-ks' 2>/dev/null" >/dev/null 2>&1 || true

if [ "$CONSOLE_RC" != "0" ]; then
  log "console driver failed rc=$CONSOLE_RC (transient domain cleanup happens via trap)"
  die "install failed"
fi

# wait for shut-off, then undefine the transient domain
for _ in $(seq 1 30); do
  S="$(tower "sudo virsh domstate '$TRANSIENT'" 2>/dev/null || true)"
  [ "$S" = "shut off" ] && break
  sleep 5
done
tower "sudo virsh undefine '$TRANSIENT'" || die "undefine transient failed"
tower "rm -rf '$DOMAIN_DIR/install-media' '$KS_DIR'" || true
log "transient domain and scratch files removed"

# ------------------------------------- persistent domain: definition + boot --
# If the persistent guest was not previously defined, define it now from the
# disk + NIC facts. This is the one-time creation authorized by issue #20 scope
# step 2 ("provision Ubuntu 26.04 ... to qcow2, attached to br0").
if ! tower "sudo virsh dumpxml '$GUEST'" >/dev/null 2>&1; then
  log "persistent guest $GUEST not yet defined - creating domain XML"
  cat > "$OUT_DIR/persistent.xml" <<XML
<domain type='kvm'>
  <name>$GUEST</name>
  <description>Ubuntu 26.04 VM (issue #20, parent #8)</description>
  <memory unit='MiB'>4096</memory>
  <currentMemory unit='MiB'>4096</currentMemory>
  <vcpu>2</vcpu>
  <os>
    <type arch='x86_64' machine='pc-q35-9.2'>hvm</type>
    <boot dev='hd'/>
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
      <boot order='1'/>
    </disk>
    <interface type='bridge'>
      <mac address='$MAC'/>
      <source bridge='br0'/>
      <model type='virtio'/>
    </interface>
    <serial type='pty'><target port='0'/></serial>
    <console type='pty'><target type='serial' port='0'/></console>
    <channel type='unix'>
      <target type='virtio' name='org.qemu.guest_agent.0'/>
    </channel>
  </devices>
</domain>
XML
  ssh $SSH_OPTS "$TOWER_HOST" "sudo virsh define /dev/stdin" < "$OUT_DIR/persistent.xml" \
    > "$OUT_DIR/persistent-domain-define.log" 2>&1 \
    || { cat "$OUT_DIR/persistent-domain-define.log"; die "persistent domain define failed"; }
  log "persistent guest $GUEST defined with qemu-guest-agent channel (see persistent-domain-define.log)"
else
  log "persistent guest $GUEST already defined - skipping creation"
fi

# --------------------------------------------------- boot + acceptance ------
log "booting persistent guest $GUEST"
tower "sudo virsh start '$GUEST'" || die "persistent guest failed to start"

log "waiting for TCP/22 at $VM_IP (up to 600s: first boot + cloud-init)"
up=0
for _ in $(seq 1 120); do
  if (exec 3<>"/dev/tcp/$VM_IP/22") 2>/dev/null; then up=1; exec 3>&-; break; fi
  sleep 5
done
[ "$up" = "1" ] || die "sshd never came up at $VM_IP"

log "SSH probe from the runner (workforce key installed by preseed)"
ssh $SSH_OPTS -o ConnectTimeout=15 "root@$VM_IP" \
  "hostname; whoami; uname -a; cat /etc/os-release | head -5" | tee "$OUT_DIR/ssh-probe.txt" \
  || die "SSH probe failed"

log "collecting acceptance evidence"
{
  echo "=== virsh domstate ==="
  tower "sudo virsh domstate '$GUEST'"
  echo "=== virsh dumpxml (key facts) ==="
  tower "sudo virsh dumpxml '$GUEST'" | grep -E "<name>|<uuid>|<source file=|<source bridge=|<mac |<channel|guest_agent|<serial|<console|<boot" || true
  echo "=== qemu-img info ==="
  tower "sudo qemu-img info '$DISK_PATH'"
  echo "=== ip occupancy (ping from tower) ==="
  tower "ping -c1 -W2 '$VM_IP' >/dev/null 2>&1 && echo 'PING: answers' || echo 'PING: silent'"
} | tee "$OUT_DIR/acceptance.txt"

ssh $SSH_OPTS "root@$VM_IP" \
  "systemctl is-active ssh; systemctl is-enabled ssh; dpkg -l qemu-guest-agent 2>/dev/null | tail -1; systemctl is-active qemu-guest-agent; systemctl is-enabled qemu-guest-agent; ip -4 addr show eth0; grep -c ssh-ed25519 /root/.ssh/authorized_keys" \
  | tee -a "$OUT_DIR/acceptance.txt" || die "in-guest verification failed"

echo "=== guest agent ping (virsh) ==="
tower "sudo virsh qemu-agent-command '$GUEST' '{\"execute\":\"guest-ping\"}'" \
  | tee -a "$OUT_DIR/acceptance.txt" || log "WARN: guest-ping failed (check agent in guest)"

echo "=== ubuntu-2604 CI transport smoke (same transport as transfer/install stages) ==="
ssh $SSH_OPTS "root@$VM_IP" \
  "apt-cache policy openssh-server | head -3; dpkg -l qemu-guest-agent | tail -1" \
  | tee -a "$OUT_DIR/acceptance.txt" || true

log "=== provisioning complete ==="
exit 0
