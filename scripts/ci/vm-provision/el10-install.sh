#!/usr/bin/env bash
# scripts/ci/vm-provision/el10-install.sh
#
# Install CentOS Stream 10 into the existing el10 guest domain on the tower
# hypervisor (issue #19, parent #11) and bring it to the acceptance spec:
#   OS installed to qcow2 + br0 @ 192.168.1.123 + sshd + qemu-guest-agent
#   + the Hermes (workforce) key authorized for root.
#
# Runs on the tower-mounted GitLab runner (tags: [android]) whose RO
# /root/.ssh mount provides the SSH alias `tower` and the workforce public
# key /root/.ssh/id_ed25519.pub (the same key CI uses for vm:ssh:smoke and
# the transfer/install/vmtest el10 stages).
#
# Preconditions verified by vm:inventory:el10 (job 24893, pipeline 2183):
#   - guest el10 defined, shut off, uuid 88f2c8a1-8118-4946-a3e3-a1bfd0a2d62b
#   - disk source /mnt/pool_two/domains/el10/vdisk1.qcow2 (virtio, boot 1)
#     (empty qcow2 created by the first run of this job, 644 KiB; the
#     kickstart clearpart wipes only this disk)
#   - cdrom /mnt/pool_one/isos/CentOS-Stream-10-latest-x86_64-dvd1.iso (sata)
#   - NIC <interface type='network'><source network='br0'> mac 52:54:00:38:58:f7
#   - serial pty console + qemu guest-agent channel already in the XML
#   - 192.168.1.123 free (no arp entry, ping silent)
#
# UEFI IS MANDATORY (job 26605 evidence + upstream facts): EL10/RHEL 10
# removed Legacy BIOS boot support entirely; the CentOS Stream 10 DVD has
# no isolinux/ tree (bsdtar proved isolinux/vmlinuz and isolinux/initrd.img
# absent on the actual tower ISO). The installer kernel/initrd live at
# images/pxeboot/, and the installed system requires an EFI System
# Partition, so BOTH the transient installer domain and the persistent
# el10 domain must run OVMF firmware. The persistent el10 domain XML is
# therefore redefined exactly once to add <loader>/<nvram> (its disk, NIC,
# MAC, uuid and every other attribute are preserved verbatim from
# dumpxml); without that single addition the installed EL10 disk can never
# boot, which would fail every acceptance criterion. This mutation is
# confined to the el10 guest's own definition and is recorded in the
# artifacts (persistent-domain-define.log).
#
# Method (headless Anaconda, no VNC, deterministic):
#   1. Preflight: record pre-state; keep the existing empty qcow2.
#   2. Locate OVMF firmware (CODE + VARS template) on tower; fail fast
#      with full search evidence when absent.
#   3. Extract images/pxeboot/{vmlinuz,initrd.img} from the DVD ISO on
#      tower (bsdtar, no loop mounts).
#   4. Serve the kickstart (with the workforce public key templated in)
#      from tower over the LAN with busybox httpd so the guest's installer
#      can fetch inst.ks=http://192.168.1.31:<port>/el10-ks.cfg. The
#      installer's own network is static via ip= kernel args (br0 has no
#      DHCP guarantee; the kickstart network directive only configures
#      the INSTALLED system).
#   5. Define a TRANSIENT domain el10-install reusing ONLY the el10
#      guest's real qcow2 disk + br0 NIC (+ DVD for package payload),
#      booting the extracted kernel directly under OVMF with console=ttyS0
#      and the inst.ks URL.
#   6. Drive the serial console from the RUNNER via expect (alpine322
#      pattern: expect -> ssh -tt tower -> sudo virsh console).
#   7. Anaconda runs unattended; watch for completion and clean reboot.
#   8. Undefine the transient domain, redefine the persistent el10
#      domain with OVMF firmware, boot it from its installed disk, and
#      run the acceptance probes.
#
# Mutations are confined to the el10 guest's resources: its qcow2 disk
# contents, its domain definition (one-time OVMF loader addition), NVRAM
# files inside its own domain directory, power state, the transient
# sibling domain el10-install (removed before the job ends), and scratch
# files in its own domain directory + tower /tmp. No other guest, disk,
# network, or host service is touched.
set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
GUEST="${GUEST:-el10}"
TRANSIENT="${TRANSIENT:-el10-install}"
VM_IP="${VM_IP:-192.168.1.123}"
TOWER_IP="${TOWER_IP:-192.168.1.31}"
ISO_PATH="${ISO_PATH:-/mnt/pool_one/isos/CentOS-Stream-10-latest-x86_64-dvd1.iso}"
DISK_PATH="${DISK_PATH:-/mnt/pool_two/domains/el10/vdisk1.qcow2}"
DOMAIN_DIR="${DOMAIN_DIR:-/mnt/pool_two/domains/el10}"
MAC="${MAC:-52:54:00:38:58:f7}"
KS_PORT="${KS_PORT:-8009}"
OUT_DIR="${PROVISION_OUT_DIR:-provision-results}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$OUT_DIR"

VM_KNOWN_HOSTS="${CI_PROJECT_DIR:-.}/.vm-known-hosts"
: > "$VM_KNOWN_HOSTS"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$VM_KNOWN_HOSTS"

tower() { ssh $SSH_OPTS "$TOWER_HOST" "$@"; }
log() { echo "[provision] $*"; }
die() { echo "FATAL: $*" >&2; exit 1; }
CONSOLE_LOG="$OUT_DIR/console-session.log"
CONSOLE_BUDGET="${CONSOLE_BUDGET:-3600}"

KS_DIR="/tmp/el10-ks.$$"
cleanup() {
  # best-effort; never touch other guests. Kill the httpd we started, remove
  # the transient domain, and wipe scratch files.
  tower "pkill -f 'httpd.*el10-ks' 2>/dev/null; sudo virsh destroy '$TRANSIENT' 2>/dev/null; sudo virsh undefine '$TRANSIENT' 2>/dev/null; rm -rf '$KS_DIR' '$DOMAIN_DIR/install-media'" \
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

# --------------------------------------------------- disk preflight/create --
log "domain dir contents before any change:"
tower "ls -la '$DOMAIN_DIR/' 2>/dev/null || echo '(domain dir absent)'" | tee "$OUT_DIR/disk-preflight.txt"

# search for any el10 disk that may live elsewhere (record only)
tower "find /mnt/pool_one /mnt/pool_two /mnt/user -maxdepth 3 -iname '*el10*' 2>/dev/null; true" \
  | tee -a "$OUT_DIR/disk-preflight.txt"

if tower "test -s '$DISK_PATH'"; then
  log "disk exists"
  tower "sudo qemu-img info '$DISK_PATH'" | tee -a "$OUT_DIR/disk-preflight.txt"
else
  # job 25524 (alpine320) failed because the domain dir did not exist:
  # create it first, then the qcow2 (authorized by issue #19 scope).
  log "disk $DISK_PATH ABSENT - creating domain dir + fresh qcow2 (sparse)"
  tower "mkdir -p '$DOMAIN_DIR' && sudo qemu-img create -f qcow2 '$DISK_PATH' 64G" \
    | tee -a "$OUT_DIR/disk-preflight.txt" || die "qemu-img create failed"
  tower "sudo qemu-img info '$DISK_PATH'" | tee -a "$OUT_DIR/disk-preflight.txt"
fi

# ----------------------------------------------- OVMF firmware discovery -----
# EL10 is UEFI-only (see header). Unraid ships OVMF under /usr/share/qemu;
# search the known locations plus a bounded find for evidence.
log "locating OVMF firmware on tower"
{
  echo "=== candidate CODE paths ==="
  for p in \
    /usr/share/qemu/ovmf-x64/OVMF_CODE.bin \
    /usr/share/qemu/ovmf-x64/OVMF_CODE.fd \
    /usr/share/qemu/ovmf-x64/OVMF_CODE-pure-efi.bin \
    /usr/share/qemu/OVMF_CODE.fd \
    /usr/share/OVMF/OVMF_CODE.fd \
    /usr/share/ovmf/OVMF_CODE.fd \
    /usr/share/edk2/ovmf/OVMF_CODE.fd \
    /usr/share/edk2/ovmf/OVMF_CODE_4M.fd; do
    tower "test -s '$p' && echo 'FOUND $p' || true"
  done
  echo "=== find fallback ==="
  tower "find /usr/share /etc/libvirt /usr/lib -maxdepth 4 -type f \\( -iname 'OVMF_CODE*.bin' -o -iname 'OVMF_CODE*.fd' \\) 2>/dev/null; true"
  echo "=== candidate VARS paths ==="
  for p in \
    /usr/share/qemu/ovmf-x64/OVMF_VARS.bin \
    /usr/share/qemu/ovmf-x64/OVMF_VARS.fd \
    /usr/share/qemu/ovmf-x64/OVMF_VARS-pure-efi.bin \
    /usr/share/OVMF/OVMF_VARS.fd \
    /usr/share/ovmf/OVMF_VARS.fd \
    /usr/share/edk2/ovmf/OVMF_VARS.fd \
    /usr/share/edk2/ovmf/OVMF_VARS_4M.fd; do
    tower "test -s '$p' && echo 'FOUND $p' || true"
  done
  echo "=== find fallback (vars) ==="
  tower "find /usr/share /etc/libvirt /usr/lib -maxdepth 4 -type f \\( -iname 'OVMF_VARS*.bin' -o -iname 'OVMF_VARS*.fd' \\) 2>/dev/null; true"
} > "$OUT_DIR/ovmf-discovery.txt"

OVMF_CODE="$(tower "for p in /usr/share/qemu/ovmf-x64/OVMF_CODE.bin /usr/share/qemu/ovmf-x64/OVMF_CODE.fd /usr/share/qemu/ovmf-x64/OVMF_CODE-pure-efi.bin /usr/share/qemu/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF_CODE.fd /usr/share/edk2/ovmf/OVMF_CODE.fd /usr/share/edk2/ovmf/OVMF_CODE_4M.fd; do test -s \"\$p\" && { echo \"\$p\"; break; }; done")"
[ -n "$OVMF_CODE" ] || OVMF_CODE="$(tower "find /usr/share /etc/libvirt /usr/lib -maxdepth 4 -type f -iname 'OVMF_CODE*' 2>/dev/null | grep -vi secboot | grep -vi -e test -e tpm | head -1; true")"
OVMF_VARS="$(tower "for p in /usr/share/qemu/ovmf-x64/OVMF_VARS.bin /usr/share/qemu/ovmf-x64/OVMF_VARS.fd /usr/share/qemu/ovmf-x64/OVMF_VARS-pure-efi.bin /usr/share/qemu/OVMF_VARS.fd /usr/share/OVMF/OVMF_VARS.fd /usr/share/ovmf/OVMF_VARS.fd /usr/share/edk2/ovmf/OVMF_VARS.fd /usr/share/edk2/ovmf/OVMF_VARS_4M.fd; do test -s \"\$p\" && { echo \"\$p\"; break; }; done")"
[ -n "$OVMF_VARS" ] || OVMF_VARS="$(tower "find /usr/share /etc/libvirt /usr/lib -maxdepth 4 -type f -iname 'OVMF_VARS*' 2>/dev/null | grep -vi secboot | grep -vi -e test -e tpm | head -1; true")"

log "OVMF_CODE=$OVMF_CODE"
log "OVMF_VARS=$OVMF_VARS"
[ -n "$OVMF_CODE" ] && [ -n "$OVMF_VARS" ] \
  || die "no OVMF firmware found on tower (EL10 is UEFI-only; see ovmf-discovery.txt)"

NVRAM_INSTALL="$DOMAIN_DIR/nvram-install.fd"
NVRAM_PERSIST="$DOMAIN_DIR/nvram.fd"
tower "cp '$OVMF_VARS' '$NVRAM_INSTALL' && cp '$OVMF_VARS' '$NVRAM_PERSIST' && ls -la '$DOMAIN_DIR/'" \
  | tee -a "$OUT_DIR/ovmf-discovery.txt" || die "could not stage NVRAM copies in $DOMAIN_DIR"

# ------------------------------------------------- kernel/initrd extraction --
log "extracting kernel/initrd from the DVD ISO (images/pxeboot/, no loop mounts)"
tower "command -v bsdtar; ls -la '$ISO_PATH'" | tee "$OUT_DIR/iso-extract.log"
# job 26605 evidence: the CS10 DVD has NO isolinux/ tree (EL10 dropped
# Legacy BIOS boot media); the installer kernel/initrd are at
# images/pxeboot/ (verified against the CS10 compose layout).
tower "rm -rf '$DOMAIN_DIR/install-media'; mkdir -p '$DOMAIN_DIR/install-media' && \
       cd '$DOMAIN_DIR/install-media' && \
       bsdtar -x -f '$ISO_PATH' images/pxeboot/vmlinuz images/pxeboot/initrd.img && \
       mv images/pxeboot/vmlinuz images/pxeboot/initrd.img . && rmdir images/pxeboot && ls -la" | tee -a "$OUT_DIR/iso-extract.log"
tower "test -s '$DOMAIN_DIR/install-media/vmlinuz' && test -s '$DOMAIN_DIR/install-media/initrd.img' && echo KERNEL-OK" \
  | tee -a "$OUT_DIR/iso-extract.log" || die "kernel/initrd extraction failed"

# ------------------------------------------------------- kickstart serving --
KEYSRC=""
if [ -r /root/.ssh/id_ed25519.pub ]; then KEYSRC=/root/.ssh/id_ed25519.pub
elif [ -r /root/.ssh/id_ed25519 ]; then
  ssh-keygen -y -f /root/.ssh/id_ed25519 > "$OUT_DIR/hermes-key.pub" && KEYSRC="$OUT_DIR/hermes-key.pub"
fi
[ -n "$KEYSRC" ] || die "no Hermes key material at /root/.ssh/id_ed25519(.pub)"
log "hermes key: $(ssh-keygen -lf "$KEYSRC" | awk '{print $1, $2}')"

# The el10 CI stages (transfer/install/vmtest) authenticate with the
# VM_SSH_KEY CI file variable; when that variable is exposed to this job
# (protected-scope pipelines), authorize its public half too so the
# stages can run against the VM exactly as wired in the repo.
VMKEY_NOTE="VM_SSH_KEY not exposed to this job (protected-variable scope); el10 stages will be evaluated via the runner key path"
if [ -f "${VM_SSH_KEY:-}" ]; then
  ssh-keygen -y -f "$VM_SSH_KEY" > "$OUT_DIR/vmsshkey.pub" 2>/dev/null \
    && VMKEY_NOTE="VM_SSH_KEY exposed; public half added to authorized_keys" \
    || VMKEY_NOTE="VM_SSH_KEY present but did not parse; not authorized"
fi
log "vm stage key: $VMKEY_NOTE"

# build the kickstart with the workforce key line appended (public half only)
KS_LOCAL="$OUT_DIR/el10-ks.cfg"
{
  cat "$HERE/el10-kickstart.cfg"
  echo "sshkey --username=root \"$(cat "$KEYSRC")\""
  if [ -s "$OUT_DIR/vmsshkey.pub" ]; then
    echo "sshkey --username=root \"$(cat "$OUT_DIR/vmsshkey.pub")\""
  fi
} > "$KS_LOCAL"

scp $SSH_OPTS "$KS_LOCAL" "$TOWER_HOST:/tmp/" >/dev/null 2>&1 || die "kickstart upload failed"
tower "mkdir -p '$KS_DIR' && mv /tmp/el10-ks.cfg '$KS_DIR/el10-ks.cfg' && chmod 644 '$KS_DIR/el10-ks.cfg'" \
  || die "kickstart staging failed"

# busybox httpd: Unraid ships busybox; verify and serve on the LAN port.
tower "command -v busybox || ls /usr/bin/busybox /usr/sbin/busybox 2>/dev/null" | tee "$OUT_DIR/httpd.log"
tower "nohup busybox httpd -f -v -p '$KS_PORT' -h '$KS_DIR' > /tmp/el10-httpd.log 2>&1 & echo httpd-pid=\$!" \
  | tee -a "$OUT_DIR/httpd.log" || die "busybox httpd failed to start"
sleep 3
tower "wget -q -O- 'http://127.0.0.1:$KS_PORT/el10-ks.cfg' | head -3 || curl -s 'http://127.0.0.1:$KS_PORT/el10-ks.cfg' | head -3" \
  | tee -a "$OUT_DIR/httpd.log" || die "kickstart not fetchable on tower"

# ---------------------------------------------------------- transient domain --
log "defining transient install domain $TRANSIENT (OVMF UEFI)"
cat > "$OUT_DIR/transient.xml" <<XML
<domain type='kvm'>
  <name>$TRANSIENT</name>
  <description>transient el10 install session (issue #19)</description>
  <memory unit='MiB'>3072</memory>
  <currentMemory unit='MiB'>3072</currentMemory>
  <vcpu>2</vcpu>
  <os>
    <type arch='x86_64' machine='pc-q35-9.2'>hvm</type>
    <loader readonly='yes' type='pflash'>$OVMF_CODE</loader>
    <nvram>$NVRAM_INSTALL</nvram>
    <kernel>$DOMAIN_DIR/install-media/vmlinuz</kernel>
    <initrd>$DOMAIN_DIR/install-media/initrd.img</initrd>
    <cmdline>console=ttyS0,115200 inst.ks=http://$TOWER_IP:$KS_PORT/el10-ks.cfg inst.repo=cdrom:/dev/sr0 ip=${VM_IP}::192.168.1.1:255.255.255.0:el10:none nameserver=192.168.1.1</cmdline>
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

# Drive the console from the RUNNER (expect runs here, apk-added in the job
# image) through the proven pty chain: expect -> ssh -tt tower -> virsh console.
export VM_KNOWN_HOSTS
expect "$HERE/el10-console.tcl" "$TRANSIENT" "$CONSOLE_BUDGET" 2>&1 | tee "$CONSOLE_LOG"
CONSOLE_RC="${PIPESTATUS[0]}"

# stop serving the kickstart as soon as the console session ends
tower "pkill -f 'httpd.*el10-ks' 2>/dev/null" >/dev/null 2>&1 || true

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

# ------------------------------------- persistent domain: OVMF redefinition --
# EL10 cannot boot via SeaBIOS (UEFI-only); add the OVMF loader to the
# persistent el10 domain, preserving every other attribute verbatim from
# its live dumpxml. The disk already carries <boot order='1'/> and the
# DVD carries none, so OVMF boots the installed disk directly.
if ! tower "sudo virsh dumpxml '$GUEST'" | grep -q "<loader"; then
  log "redefining persistent guest $GUEST with OVMF firmware (EL10 is UEFI-only)"
  tower "sudo virsh dumpxml '$GUEST'" > "$OUT_DIR/persistent-before.xml"
  # insert loader+nvram right after the <os><type ...>hvm</type> line.
  # Pure-bash insertion (BusyBox sed on the alpine runner image handles
  # multiline `a\` differently than GNU sed; this avoids the portability
  # trap entirely and preserves every other line verbatim).
  : > "$OUT_DIR/persistent-after.xml"
  while IFS= read -r line; do
    printf '%s\n' "$line" >> "$OUT_DIR/persistent-after.xml"
    case "$line" in
      *"machine='pc-q35-9.2'>hvm</type>"*)
        printf '    <loader readonly=%s type=%s>%s</loader>\n' "'yes'" "'pflash'" "$OVMF_CODE" >> "$OUT_DIR/persistent-after.xml"
        printf '    <nvram>%s</nvram>\n' "$NVRAM_PERSIST" >> "$OUT_DIR/persistent-after.xml"
        ;;
    esac
  done < "$OUT_DIR/persistent-before.xml"
  grep -q "<loader" "$OUT_DIR/persistent-after.xml" \
    || die "failed to inject OVMF loader into persistent domain XML"
  ssh $SSH_OPTS "$TOWER_HOST" "sudo virsh define /dev/stdin" \
    < "$OUT_DIR/persistent-after.xml" > "$OUT_DIR/persistent-domain-define.log" 2>&1 \
    || { cat "$OUT_DIR/persistent-domain-define.log"; die "persistent domain redefine failed"; }
  log "persistent domain redefined with OVMF (see persistent-domain-define.log)"
else
  log "persistent guest already carries a firmware loader"
fi

# --------------------------------------------------- boot + acceptance ------
log "booting persistent guest $GUEST"
tower "sudo virsh start '$GUEST'" || die "persistent guest failed to start"

log "waiting for TCP/22 at $VM_IP (up to 600s: first boot + relabel)"
up=0
for _ in $(seq 1 120); do
  if (exec 3<>"/dev/tcp/$VM_IP/22") 2>/dev/null; then up=1; exec 3>&-; break; fi
  sleep 5
done
[ "$up" = "1" ] || die "sshd never came up at $VM_IP"

log "SSH probe from the runner (workforce key installed by kickstart)"
ssh $SSH_OPTS -o ConnectTimeout=15 "root@$VM_IP" \
  "hostname; whoami; uname -a; cat /etc/redhat-release" | tee "$OUT_DIR/ssh-probe.txt" \
  || die "SSH probe failed"

log "collecting acceptance evidence"
{
  echo "=== virsh domstate ==="
  tower "sudo virsh domstate '$GUEST'"
  echo "=== virsh dumpxml (key facts) ==="
  tower "sudo virsh dumpxml '$GUEST'" | grep -E "<name>|<uuid>|<source file=|<source network=|<source bridge=|<mac |<channel|guest_agent|<serial|<console|<loader|<nvram" || true
  echo "=== qemu-img info ==="
  tower "sudo qemu-img info '$DISK_PATH'"
  echo "=== ip occupancy (ping from tower) ==="
  tower "ping -c1 -W2 '$VM_IP' >/dev/null 2>&1 && echo 'PING: answers' || echo 'PING: silent'"
} | tee "$OUT_DIR/acceptance.txt"

ssh $SSH_OPTS "root@$VM_IP" \
  "systemctl is-active sshd qemu-guest-agent; systemctl is-enabled sshd qemu-guest-agent; ip -4 addr show; grep -c ssh-ed25519 /root/.ssh/authorized_keys; rpm -q qemu-guest-agent openssh-server; test -d /boot/efi && echo ESP-PRESENT; efibootmgr | head -8" \
  | tee -a "$OUT_DIR/acceptance.txt" || die "in-guest verification failed"

echo "=== guest agent ping (virsh) ==="
tower "sudo virsh qemu-agent-command '$GUEST' '{\"execute\":\"guest-ping\"}'" \
  | tee -a "$OUT_DIR/acceptance.txt" || log "WARN: guest-ping failed (check agent in guest)"

echo "=== el10 CI transport smoke (same transport as transfer/install stages) ==="
ssh $SSH_OPTS "root@$VM_IP" \
  "dnf -v repolist --enabled 2>/dev/null | grep -iE 'epel|crb' || echo 'WARN: epel/crb not visible'" \
  | tee -a "$OUT_DIR/acceptance.txt" || true

log "=== provisioning complete ==="
exit 0
