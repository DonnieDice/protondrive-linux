#!/usr/bin/env bash
# scripts/ci/vm-provision/ubuntu-24.04-install.sh
#
# Install Ubuntu 24.04 into the existing ubuntu2404 guest domain on the tower
# hypervisor (issue #24, parent #7) and bring it to the acceptance spec:
#   OS installed to qcow2 + br0 @ 192.168.1.219 + sshd + qemu-guest-agent
#   + the Hermes (workforce) key authorized for root.
#
# Runs on the tower-mounted GitLab runner (tags: [android]) whose RO
# /root/.ssh mount provides the SSH alias `tower` and the workforce public
# key /root/.ssh/id_ed25519.pub (the same key CI uses for vm:ssh:smoke and
# the transfer/install/vmtest ubuntu-24.04 stages).
#
# Method (headless subiquity autoinstall, no VNC, deterministic):
#   1. Preflight: record pre-state; create the qcow2 if absent.
#   2. Discover OVMF firmware (Ubuntu 24.04 on QEMU/KVM requires OVMF UEFI).
#   3. Discover Ubuntu 24.04 netboot kernel + initrd (netboot tarball or
#      server ISO casper/ extraction via bsdtar).
#   4. Serve cloud-init user-data (autoinstall) from tower over the LAN
#      with busybox httpd.
#   5. Define a TRANSIENT domain ubuntu2404-install reusing ONLY the
#      ubuntu2404 guest's real qcow2 disk + br0 NIC, booting under OVMF
#      with the netboot kernel directly (kernel= initrd= cmdline=),
#      console=ttyS0 and autoinstall url=<http>.
#   6. Drive the serial console from the RUNNER via expect (the runner
#      has expect; tower has none).
#   7. Subiquity runs unattended; watch for completion and clean reboot.
#   8. Undefine the transient domain, ensure the persistent ubuntu2404
#      domain has OVMF firmware, boot it, and run acceptance probes.
#
# Mutations confined to the ubuntu2404 guest's resources only.
set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
GUEST="${GUEST:-ubuntu2404}"
TRANSIENT="${TRANSIENT:-ubuntu2404-install}"
VM_IP="${VM_IP:-192.168.1.219}"
TOWER_IP="${TOWER_IP:-192.168.1.31}"
DISK_PATH="${DISK_PATH:-/mnt/pool_two/domains/ubuntu2404/vdisk1.qcow2}"
DOMAIN_DIR="${DOMAIN_DIR:-/mnt/pool_two/domains/ubuntu2404}"
MAC="${MAC:-52:54:00:23:04:19}"
KS_PORT="${KS_PORT:-8024}"
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
CONSOLE_BUDGET="${CONSOLE_BUDGET:-3600}"

KS_DIR="/tmp/ubuntu2404-ks.$$"
cleanup() {
  tower "pkill -f 'httpd.*ubuntu2404-ks' 2>/dev/null; sudo virsh destroy '$TRANSIENT' 2>/dev/null; sudo virsh undefine '$TRANSIENT' 2>/dev/null; rm -rf '$KS_DIR' '$DOMAIN_DIR/install-media' /tmp/ubuntu2404-ks.*" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ------------------------------------------------------------- pre-state ----
tower "hostname; whoami; date -u" | tee "$OUT_DIR/identity.txt" || die "cannot reach tower"

STATE="$(tower "sudo virsh domstate '$GUEST'" 2>/dev/null)"
log "persistent guest state: ${STATE:-unknown/absent}"
{
  echo "pre-state: ${STATE:-absent}"
  tower "sudo virsh dumpxml '$GUEST'" 2>/dev/null || echo "(guest not defined yet)"
} > "$OUT_DIR/pre-state.txt" || die "dumpxml failed"

# transient domain must not exist
if tower "sudo virsh domstate '$TRANSIENT'" >/dev/null 2>&1; then
  log "removing stale transient domain $TRANSIENT"
  tower "sudo virsh destroy '$TRANSIENT'" >/dev/null 2>&1 || true
  tower "sudo virsh undefine '$TRANSIENT'" >/dev/null 2>&1 || true
fi

# ----------------------------------------------- idempotency: already installed? --
# If the disk already carries an installed Ubuntu 24.04 and the guest boots to
# sshd, skip the full autoinstall reinstall (issue #24 acceptance criteria are
# about the OS being installed, not about reinstalling it). This is the same
# idempotency principle the el10 install harness follows: detect an existing
# installation and skip the destructive install phase, proceeding only to the
# acceptance probes.
log "checking for an existing Ubuntu 24.04 installation on $GUEST"
IDEMPOTENT_SKIP=false
# 1. Is the persistent guest running?
if [ "${STATE:-}" = "running" ]; then
  # 2. Does the disk carry a real (non-empty) filesystem?
  DISK_VERSIG="$(tower "sudo qemu-img info '$DISK_PATH' 2>/dev/null | grep -i 'file format' || true")"
  if tower "sudo blkid '$DISK_PATH' 2>/dev/null | grep -q ext4 || \
     sudo file -s '$DISK_PATH' 2>/dev/null | grep -q 'Linux rev'"; then
    log "disk carries a filesystem signature - checking for an existing OS"
    # 3. Is SSH already up at the target IP?
    if (exec 3<>"/dev/tcp/$VM_IP/22") 2>/dev/null; then
      exec 3>&-
      log "sshd already accepting connections at $VM_IP - OS already installed"
      IDEMPOTENT_SKIP=true
    else
      log "guest running but sshd not yet up - will proceed with install"
    fi
  else
    log "disk appears empty/unformatted - proceeding with fresh install"
  fi
else
  log "guest not running (state: ${STATE:-absent}) - will ensure it is started after install"
fi

if [ "$IDEMPOTENT_SKIP" = "true" ]; then
  log "idempotency: skipping autoinstall (OS already installed to $DISK_PATH)"
  echo "idempotency: skip_install=true reason='OS already installed and sshd reachable'" > "$OUT_DIR/idempotency.txt"
  # Jump straight to acceptance: ensure OVMF on persistent domain, boot, verify.
  # Fall through to the disk preflight which will detect the existing disk,
  # then skip to the persistent-domain OVMF check + acceptance section below.
  SKIP_INSTALL=true
else
  SKIP_INSTALL=false
fi

# ---------------------------------------------------- disk preflight/create --
log "domain dir contents before any change:"
tower "ls -la '$DOMAIN_DIR/' 2>/dev/null || echo '(domain dir absent)'" | tee "$OUT_DIR/disk-preflight.txt"

# search for any ubuntu2404 disk that may live elsewhere (record only)
tower "find /mnt/pool_one /mnt/pool_two /mnt/user/domains -maxdepth 3 -iname '*ubuntu*24*' 2>/dev/null; true" | tee -a "$OUT_DIR/disk-preflight.txt"

if tower "test -s '$DISK_PATH'"; then
  log "disk exists"
  tower "sudo qemu-img info '$DISK_PATH'" | tee -a "$OUT_DIR/disk-preflight.txt"
else
  log "disk $DISK_PATH ABSENT - creating domain dir + fresh qcow2 (64G sparse)"
  tower "sudo mkdir -p '$DOMAIN_DIR'" >>"$OUT_DIR/disk-preflight.txt" 2>&1 || die "mkdir of domain dir failed"
  tower "sudo qemu-img create -f qcow2 '$DISK_PATH' 64G" | tee -a "$OUT_DIR/disk-preflight.txt" || die "qemu-img create failed"
  tower "sudo qemu-img info '$DISK_PATH'" | tee -a "$OUT_DIR/disk-preflight.txt"
fi

# ----------------------------------------------- OVMF firmware discovery ----
log "locating OVMF firmware on tower"
{
  echo "=== candidate CODE paths ==="
  for p in \
    /usr/share/qemu/ovmf-x64/OVMF_CODE.fd \
    /usr/share/qemu/ovmf-x64/OVMF_CODE.bin \
    /usr/share/qemu/ovmf-x64/OVMF_CODE-pure-efi.fd \
    /usr/share/OVMF/OVMF_CODE.fd \
    /usr/share/ovmf/OVMF_CODE.fd \
    /usr/share/edk2/ovmf/OVMF_CODE.fd \
    /usr/share/edk2/ovmf/OVMF_CODE_4M.fd; do
    tower "test -s '$p' && echo 'FOUND $p' || true"
  done
  echo "=== find fallback (CODE) ==="
  tower "find /usr/share /etc/libvirt /usr/lib -maxdepth 4 -type f -iname 'OVMF_CODE*' 2>/dev/null | grep -vi secboot | grep -vi -e test -e tpm | head -5"
  echo "=== candidate VARS paths ==="
  for p in \
    /usr/share/qemu/ovmf-x64/OVMF_VARS.fd \
    /usr/share/qemu/ovmf-x64/OVMF_VARS.bin \
    /usr/share/qemu/ovmf-x64/OVMF_VARS-pure-efi.fd \
    /usr/share/OVMF/OVMF_VARS.fd \
    /usr/share/ovmf/OVMF_VARS.fd \
    /usr/share/edk2/ovmf/OVMF_VARS.fd \
    /usr/share/edk2/ovmf/OVMF_VARS_4M.fd; do
    tower "test -s '$p' && echo 'FOUND $p' || true"
  done
  echo "=== find fallback (VARS) ==="
  tower "find /usr/share /etc/libvirt /usr/lib -maxdepth 4 -type f -iname 'OVMF_VARS*' 2>/dev/null | grep -vi secboot | grep -vi -e test -e tpm | head -5"
} > "$OUT_DIR/ovmf-discovery.txt"

OVMF_CODE="$(tower "for p in /usr/share/qemu/ovmf-x64/OVMF_CODE.fd /usr/share/qemu/ovmf-x64/OVMF_CODE.bin /usr/share/qemu/ovmf-x64/OVMF_CODE-pure-efi.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF_CODE.fd /usr/share/edk2/ovmf/OVMF_CODE.fd /usr/share/edk2/ovmf/OVMF_CODE_4M.fd; do test -s \"\$p\" && { echo \"\$p\"; break; }; done")"
[ -n "$OVMF_CODE" ] || OVMF_CODE="$(tower "find /usr/share /etc/libvirt /usr/lib -maxdepth 4 -type f -iname 'OVMF_CODE*' 2>/dev/null | grep -vi secboot | grep -vi -e test -e tpm | head -1; true")"
OVMF_VARS="$(tower "for p in /usr/share/qemu/ovmf-x64/OVMF_VARS.fd /usr/share/qemu/ovmf-x64/OVMF_VARS.bin /usr/share/qemu/ovmf-x64/OVMF_VARS-pure-efi.fd /usr/share/OVMF/OVMF_VARS.fd /usr/share/ovmf/OVMF_VARS.fd /usr/share/edk2/ovmf/OVMF_VARS.fd /usr/share/edk2/ovmf/OVMF_VARS_4M.fd; do test -s \"\$p\" && { echo \"\$p\"; break; }; done")"
[ -n "$OVMF_VARS" ] || OVMF_VARS="$(tower "find /usr/share /etc/libvirt /usr/lib -maxdepth 4 -type f -iname 'OVMF_VARS*' 2>/dev/null | grep -vi secboot | grep -vi -e test -e tpm | head -1; true")"

log "OVMF_CODE=$OVMF_CODE"
log "OVMF_VARS=$OVMF_VARS"
[ -n "$OVMF_CODE" ] && [ -n "$OVMF_VARS" ] || die "no OVMF firmware found on tower (Ubuntu 24.04 on OVMF/UEFI is required; see ovmf-discovery.txt)"

NVRAM_INSTALL="$DOMAIN_DIR/nvram-install.fd"
NVRAM_PERSIST="$DOMAIN_DIR/nvram.fd"
tower "cp '$OVMF_VARS' '$NVRAM_INSTALL' && cp '$OVMF_VARS' '$NVRAM_PERSIST' && ls -la '$DOMAIN_DIR/'" | tee -a "$OUT_DIR/ovmf-discovery.txt" || die "could not stage NVRAM copies in $DOMAIN_DIR"

# ----------------------------------------- kernel/initrd discovery/extract --
log "locating Ubuntu 24.04 netboot kernel + initrd on tower"
{
  echo "=== ISO / netboot media inventory ==="
  tower "ls -la /mnt/pool_one/isos/ 2>/dev/null | grep -i ubuntu || echo '(no ubuntu in /mnt/pool_one/isos)'; ls -la /mnt/user/isos/ 2>/dev/null | grep -i ubuntu || echo '(no ubuntu in /mnt/user/isos)'; find /mnt/pool_one/isos /mnt/user/isos -maxdepth 2 -iname '*ubuntu*24*' -type f 2>/dev/null | head -10"
  echo "=== netboot search ==="
  tower "find /mnt/pool_one /mnt/pool_two /mnt/user -maxdepth 4 -iname 'netboot*_ubuntu' -type f 2>/dev/null | head -5; find /mnt/pool_one /mnt/pool_two /mnt/user -maxdepth 4 -iname 'ubuntu-24.04*netboot*' -type f 2>/dev/null | head -5"
} > "$OUT_DIR/iso-extract.log"

# Try the netboot tarball first, then the server ISO casper/ extraction.
# The netboot tarball (netboot.tar.gz) contains vmlinuz + initrd.gz for the
# installer directly. If only the server ISO is present, extract from
# casper/vmlinuz + casper/initrd from it (bsdtar, no loop mounts).
KERNEL_PATH=""
INITRD_PATH=""

# netboot tarball pattern. ISO files are symlinks (issue #24: they point into a
# cold-archive pool); follow them with -L so -type f resolves the real file.
# Search all three isos trees (inventory #24 lists /mnt/pool_one, /mnt/pool_two,
# /mnt/user).
NETBOOT_ISO="$(tower "find -L /mnt/pool_one/isos /mnt/pool_two/isos /mnt/user/isos -maxdepth 3 -iname '*ubuntu*24*netboot*' -type f 2>/dev/null | head -1; true")"
SERVER_ISO="$(tower "find -L /mnt/pool_one/isos /mnt/pool_two/isos /mnt/user/isos -maxdepth 3 -iname '*ubuntu-24.04-server*' -type f 2>/dev/null | head -1; true")"

# Use env override if set, otherwise detect
ISO_PATH="${ISO_PATH:-${NETBOOT_ISO:-${SERVER_ISO:-}}}"
if [ -z "$ISO_PATH" ]; then
  # Fall back to a broader symlink-following search across all isos trees
  ISO_PATH="$(tower "find -L /mnt/pool_one/isos /mnt/pool_two/isos /mnt/user/isos -maxdepth 3 -iname '*ubuntu*24*' -type f 2>/dev/null | head -1; true")"
fi

log "Using ISO/netboot: ${ISO_PATH:-(not found)}"
echo "Using ISO/netboot: ${ISO_PATH:-(not found)}" >> "$OUT_DIR/iso-extract.log"

if [ -z "$ISO_PATH" ]; then
  die "no Ubuntu 24.04 ISO or netboot media found on tower (searched /mnt/pool_one/isos and /mnt/user/isos)"
fi

# Extract kernel and initrd
# For netboot.tar.gz: paths are vmlinuz + initrd.gz
# For server ISO: paths are casper/vmlinuz + casper/initrd
tower "rm -rf '$DOMAIN_DIR/install-media'; mkdir -p '$DOMAIN_DIR/install-media' && \
       cd '$DOMAIN_DIR/install-media' && \
       bsdtar -xf '$ISO_PATH' vmlinuz initrd.gz 2>/dev/null || \
       bsdtar -xf '$ISO_PATH' casper/vmlinuz casper/initrd 2>/dev/null && \
       [ -f vmlinuz ] && mv vmlinuz vmlinuz-installer || true && \
       [ -f initrd.gz ] && mv initrd.gz initrd-installer || true && \
       [ -f casper/vmlinuz ] && mv casper/vmlinuz vmlinuz-installer && rmdir casper 2>/dev/null || true && \
       [ -f casper/initrd ] && mv casper/initrd initrd-installer && rmdir casper 2>/dev/null || true && \
       ls -la" | tee -a "$OUT_DIR/iso-extract.log" || die "kernel/initrd extraction failed"

KREL="$DOMAIN_DIR/install-media/vmlinuz-installer"
IREL="$DOMAIN_DIR/install-media/initrd-installer"
tower "test -s '$KREL' && test -s '$IREL' && echo KERNEL-OK" | tee -a "$OUT_DIR/iso-extract.log" || die "kernel/initrd not found after extraction (tried vmlinuz+initrd.gz and casper/vmlinuz+initrd)"

# ------------------------------------------------------------- key + metadata --
if [ "$SKIP_INSTALL" != "true" ]; then
  KEYSRC=""
  if [ -r /root/.ssh/id_ed25519.pub ]; then KEYSRC=/root/.ssh/id_ed25519.pub
  elif [ -r /root/.ssh/id_ed25519 ]; then
    ssh-keygen -y -f /root/.ssh/id_ed25519 > "$OUT_DIR/hermes-key.pub" && KEYSRC="$OUT_DIR/hermes-key.pub"
  fi
  [ -n "$KEYSRC" ] || die "no Hermes key material at /root/.ssh/id_ed25519(.pub)"
  log "hermes key: $(ssh-keygen -lf "$KEYSRC" | awk '{print $1, $2}')"

# VM_SSH_KEY CI variable for the el10 stages (when exposed to this job)
VMKEY_NOTE="VM_SSH_KEY not exposed to this job (protected-variable scope)"
if [ -f "${VM_SSH_KEY:-}" ]; then
  ssh-keygen -y -f "$VM_SSH_KEY" > "$OUT_DIR/vmsshkey.pub" 2>/dev/null \
    && VMKEY_NOTE="VM_SSH_KEY exposed; public half available for stages" \
    || VMKEY_NOTE="VM_SSH_KEY present but did not parse"
fi
log "vm stage key: $VMKEY_NOTE"

# Build the cloud-init/autoinstall user-data with the workforce key line
CLOUD_INIT_LOCAL="$OUT_DIR/ubuntu-24.04-cloud-init.yaml"
cp "$HERE/ubuntu-24.04-cloud-init.yaml" "$CLOUD_INIT_LOCAL"
# Replace the placeholder with the actual workforce public key
WORKFORCE_KEY="$(cat "$KEYSRC")"
# Escape for sed replacement: replace the placeholder line with the actual key
sed "s|PLACEHOLDER_REPLACE_WITH_WORKFORCE_KEY|$WORKFORCE_KEY|g" "$CLOUD_INIT_LOCAL" > "$OUT_DIR/user-data"
# Also add the VM_SSH_KEY public half if available
if [ -s "$OUT_DIR/vmsshkey.pub" ]; then
  VM_KEY_LINE="$(cat "$OUT_DIR/vmsshkey.pub")"
  sed -i "s|- PLACEHOLDER_REPLACE_WITH_WORKFORCE_KEY|- PLACEHOLDER_REPLACE_WITH_WORKFORCE_KEY\\n    - $VM_KEY_LINE|" "$OUT_DIR/user-data" 2>/dev/null || true
fi
fi

# ------------------------------------------------- serve autoinstall over LAN --
if [ "$SKIP_INSTALL" != "true" ]; then
tower "mkdir -p '$KS_DIR' && chmod 755 '$KS_DIR'" || die "could not create KS dir on tower"
scp $SSH_OPTS "$OUT_DIR/user-data" "$TOWER_HOST:/tmp/" >/dev/null 2>&1 || die "cloud-init upload failed"
tower "mv /tmp/user-data '$KS_DIR/user-data' && chmod 644 '$KS_DIR/user-data' && ls -la '$KS_DIR/'" || die "cloud-init staging failed"

# busybox httpd: serve on the LAN port
tower "command -v busybox || ls /usr/bin/busybox /usr/sbin/busybox 2>/dev/null" | tee "$OUT_DIR/httpd.log"
tower "nohup busybox httpd -f -v -p '$KS_PORT' -h '$KS_DIR' > /tmp/ubuntu2404-httpd.log 2>&1 & echo httpd_pid=\$!" | tee -a "$OUT_DIR/httpd.log" || die "busybox httpd failed to start"
sleep 3
tower "wget -q -O- 'http://127.0.0.1:$KS_PORT/user-data' | head -3 || curl -s 'http://127.0.0.1:$KS_PORT/user-data' | head -3" | tee -a "$OUT_DIR/httpd.log" || die "cloud-init not fetchable on tower"
log "cloud-init user-data served on tower port $KS_PORT"

# ---------------------------------------------------------- transient domain --
log "defining transient install domain $TRANSIENT (OVMF UEFI, netboot kernel)"
# The persistent guest may or may not be defined yet; we define the transient
# domain which reuses the same qcow2 disk + br0 NIC. The persistent guest
# gets OVMF added separately if it exists.
cat > "$OUT_DIR/transient.xml" <<XML
<domain type='kvm'>
  <name>$TRANSIENT</name>
  <description>transient ubuntu2404 install session (issue #24)</description>
  <memory unit='MiB'>4096</memory>
  <currentMemory unit='MiB'>4096</currentMemory>
  <vcpu>2</vcpu>
  <os>
    <type arch='x86_64' machine='pc-q35-9.2'>hvm</type>
    <loader readonly='yes' type='pflash'>$OVMF_CODE</loader>
    <nvram>$NVRAM_INSTALL</nvram>
    <kernel>$KREL</kernel>
    <initrd>$IREL</initrd>
    <cmdline>console=ttyS0,115200 autoinstall url=http://$TOWER_IP:$KS_PORT/user-data ip=${VM_IP}::192.168.1.1:255.255.255.0:ubuntu2404:none</cmdline>
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
ssh $SSH_OPTS "$TOWER_HOST" "sudo virsh define /dev/stdin" < "$OUT_DIR/transient.xml" || die "transient define failed"

# ------------------------------------------------------------------ install --
log "starting transient domain $TRANSIENT"
tower "sudo virsh start '$TRANSIENT'" || die "transient start failed"

# Drive the console from the RUNNER via expect
export VM_KNOWN_HOSTS
export CONSOLE_LOG
expect "$HERE/ubuntu-24.04-console.expect" "$TRANSIENT" "$CONSOLE_BUDGET" 2>&1 | tee "$CONSOLE_LOG"
CONSOLE_RC="${PIPESTATUS[0]}"

# stop serving the cloud-init as soon as the console session ends
tower "pkill -f 'httpd.*ubuntu2404-ks' 2>/dev/null" >/dev/null 2>&1 || true

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
fi  # end SKIP_INSTALL guard for transient domain

# ------------------------------------- persistent domain: OVMF redefinition --
# Ubuntu 24.04 on OVMF/UEFI: if the persistent guest exists and lacks a firmware
# loader, redefine it with OVMF (preserving all other attributes).
if tower "sudo virsh dumpxml '$GUEST'" 2>/dev/null | grep -q "<loader"; then
  log "persistent guest already carries a firmware loader"
else
  log "redefining persistent guest $GUEST with OVMF firmware (Ubuntu 24.04 UEFI)"
  tower "sudo virsh dumpxml '$GUEST'" > "$OUT_DIR/persistent-before.xml" 2>/dev/null || die "cannot dump persistent guest XML"
  # If the guest doesn't exist yet, define it from the transient XML (minus the
  # kernel/initrd/cmdline, keeping the disk + NIC + serial + console)
  if [ ! -s "$OUT_DIR/persistent-before.xml" ]; then
    log "persistent guest not defined yet - defining from persistent.xml template"
    cat > "$OUT_DIR/persistent.xml" <<XML
<domain type='kvm'>
  <name>$GUEST</name>
  <description>Ubuntu 24.04 test VM (issue #24, parent #7)</description>
  <memory unit='MiB'>4096</memory>
  <currentMemory unit='MiB'>4096</currentMemory>
  <vcpu>2</vcpu>
  <os>
    <type arch='x86_64' machine='pc-q35-9.2'>hvm</type>
    <loader readonly='yes' type='pflash'>$OVMF_CODE</loader>
    <nvram>$NVRAM_PERSIST</nvram>
  </os>
  <features><acpi/><apic/></features>
  <cpu mode='host-passthrough'/>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>restart</on_crash>
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
      <source mode='bind' type='socket' path='/var/lib/libvirt/qemu/channel/target/org.qemu.guest_agent.0'/>
      <target type='virtio' name='org.qemu.guest_agent.0'/>
    </channel>
  </devices>
</domain>
XML
    ssh $SSH_OPTS "$TOWER_HOST" "sudo virsh define /dev/stdin" < "$OUT_DIR/persistent.xml" || die "persistent domain define failed"
    log "persistent guest defined with OVMF"
  else
    # Guest exists but lacks OVMF - inject loader after the <type> line
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
    grep -q "<loader" "$OUT_DIR/persistent-after.xml" || die "failed to inject OVMF loader into persistent domain XML"
    ssh $SSH_OPTS "$TOWER_HOST" "sudo virsh define /dev/stdin" < "$OUT_DIR/persistent-after.xml" > "$OUT_DIR/persistent-domain-define.log" 2>&1 || { cat "$OUT_DIR/persistent-domain-define.log"; die "persistent domain redefine failed"; }
    log "persistent domain redefined with OVMF (see persistent-domain-define.log)"
  fi
fi

# --------------------------------------------------- boot + acceptance ------
log "booting persistent guest $GUEST"
tower "sudo virsh start '$GUEST'" || die "persistent guest failed to start"

log "waiting for TCP/22 at $VM_IP (up to 600s: first boot + cloud-init + autoinstall)"
up=0
for _ in $(seq 1 120); do
  if (exec 3<>"/dev/tcp/$VM_IP/22") 2>/dev/null; then up=1; exec 3>&-; break; fi
  sleep 5
done
[ "$up" = "1" ] || die "sshd never came up at $VM_IP"

log "SSH probe from the runner (workforce key installed by cloud-init)"
ssh $SSH_OPTS -o ConnectTimeout=15 "root@$VM_IP" \
  "hostname; whoami; uname -a; lsb_release -a 2>/dev/null || cat /etc/os-release" | tee "$OUT_DIR/ssh-probe.txt" \
  || die "SSH probe failed"

log "collecting acceptance evidence"
{
  echo "=== virsh domstate ==="
  tower "sudo virsh domstate '$GUEST'"
  echo "=== virsh dumpxml (key facts) ==="
  tower "sudo virsh dumpxml '$GUEST'" | grep -E "<name>|<uuid>|<source file=|<source bridge=|<mac |<channel|guest_agent|<serial|<console|<loader|<nvram|<interface" || true
  echo "=== qemu-img info ==="
  tower "sudo qemu-img info '$DISK_PATH'"
  echo "=== ip occupancy (ping from tower) ==="
  tower "ping -c1 -W2 '$VM_IP' >/dev/null 2>&1 && echo 'PING: answers' || echo 'PING: silent'"
} | tee "$OUT_DIR/acceptance.txt"

ssh $SSH_OPTS "root@$VM_IP" \
  "systemctl is-active sshd qemu-guest-agent; systemctl is-enabled sshd qemu-guest-agent; ip -4 addr show; grep -c ssh-ed25519 /root/.ssh/authorized_keys; dpkg -l qemu-guest-agent openssh-server 2>/dev/null | grep '^ii'; test -d /boot/efi && echo ESP-PRESENT; ip route show default" \
  | tee -a "$OUT_DIR/acceptance.txt" || die "in-guest verification failed"

echo "=== guest agent ping (virsh) ==="
tower "sudo virsh qemu-agent-command '$GUEST' '{\"execute\":\"guest-ping\"}'" \
  | tee -a "$OUT_DIR/acceptance.txt" || log "WARN: guest-ping failed (check agent in guest)"

echo "=== ubuntu-24.04 CI transport smoke (same transport as transfer/install stages) ==="
ssh $SSH_OPTS "root@$VM_IP" \
  "dpkg -l | grep -E 'qemu-guest-agent|openssh-server'; echo '---'; ls -la /root/.ssh/authorized_keys; echo '---'; cat /etc/ssh/sshd_config | grep PermitRootLogin" \
  | tee -a "$OUT_DIR/acceptance.txt" || true

log "=== provisioning complete ==="
exit 0
