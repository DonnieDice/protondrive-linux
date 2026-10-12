#!/usr/bin/env bash
# scripts/ci/vm-provision/fedora-43-install.sh
#
# Install Fedora 43 into the fedora-43 guest domain on the tower hypervisor
# (issue #18, parent #12) and bring it to the acceptance spec:
#   OS installed to qcow2 + br0 @ 192.168.1.183 + sshd + qemu-guest-agent
#   + the Hermes (workforce) key authorized for root.
#
# Runs on the tower-mounted GitLab runner (tags: [android]) whose RO
# /root/.ssh mount provides the SSH alias `tower` and the workforce public
# key /root/.ssh/id_ed25519.pub (the same key CI uses for vm:ssh:smoke and
# the transfer/install/vmtest fedora-43 stages).
#
# Preconditions verified by vm:inventory:fedora-43:
#   - guest fedora-43 defined or absent (driver creates if needed)
#   - br0 network exists (virsh net-dumpxml)
#   - 192.168.1.183 free (no arp entry, ping silent) unless pre-existing
#   - Fedora 43 ISO available on tower at ${ISO_PATH}
#   - OVMF firmware present (Fedora 43 is UEFI-capable)
#
# Mutations are confined to the fedora-43 guest's resources: its qcow2 disk
# contents, its domain definition (one-time OVMF loader addition), NVRAM
# files inside its own domain directory, power state, the transient sibling
# domain fedora-43-install (removed before the job ends), and scratch files
# in its own domain directory + tower /tmp. No other guest, disk, network,
# or host service is touched.
set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
GUEST="${GUEST:-fedora43}"
TRANSIENT="${TRANSIENT:-fedora-43-install}"
VM_IP="${VM_IP:-192.168.1.183}"
TOWER_IP="${TOWER_IP:-192.168.1.31}"
ISO_PATH="${ISO_PATH:-/mnt/pool_one/isos/Fedora-Workstation-Live-43-1.6.x86_64.iso}"
DISK_PATH="${DISK_PATH:-/mnt/pool_two/domains/fedora43/vdisk1.qcow2}"
DOMAIN_DIR="${DOMAIN_DIR:-/mnt/pool_two/domains/fedora43}"
MAC="${MAC:-52:54:00:38:58:f7}"
KS_PORT="${KS_PORT:-8010}"
OUT_DIR="${PROVISION_OUT_DIR:-provision-results}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$OUT_DIR"

VM_KNOWN_HOSTS="${CI_PROJECT_DIR:-.}/.vm-known-hosts"
: >"$VM_KNOWN_HOSTS"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$VM_KNOWN_HOSTS"

tower() { ssh $SSH_OPTS "$TOWER_HOST" "$@"; }
log() { echo "[provision] $*"; }
die() {
  echo "FATAL: $*" >&2
  exit 1
}
CONSOLE_LOG="$OUT_DIR/console-session.log"
CONSOLE_BUDGET="${CONSOLE_BUDGET:-3600}"

KS_DIR="/tmp/fedora43-ks.$$"
cleanup() {
  # best-effort; never touch other guests. Kill the httpd we started, remove
  # the transient domain, and wipe scratch files.
  tower "pkill -f 'httpd.*fedora43-ks' 2>/dev/null; sudo virsh destroy '$TRANSIENT' 2>/dev/null; sudo virsh undefine '$TRANSIENT' 2>/dev/null; rm -rf '$KS_DIR' '$DOMAIN_DIR/install-media'" \
    >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ------------------------------------------------------------- pre-state ----
tower "hostname; whoami; date -u" | tee "$OUT_DIR/identity.txt" || die "cannot reach tower"

STATE="$(tower "sudo virsh domstate '$GUEST'" 2>/dev/null)"
log "persistent guest state: ${STATE:-not-defined}"
{
  echo "pre-state: ${STATE:-not-defined}"
  if [ -n "$STATE" ]; then
    tower "sudo virsh dumpxml '$GUEST'"
  else
    echo "(guest $GUEST not yet defined)"
  fi
} >"$OUT_DIR/pre-state.txt" || die "could not record pre-state"

# transient domain must not exist
if tower "sudo virsh domstate '$TRANSIENT'" >/dev/null 2>&1; then
  log "removing stale transient domain $TRANSIENT"
  tower "sudo virsh destroy '$TRANSIENT'" >/dev/null 2>&1 || true
  tower "sudo virsh undefine '$TRANSIENT'" >/dev/null 2>&1 || true
fi

# The persistent guest (fedora43) may be running and holding a write lock on
# the shared qcow2 disk (vdisk1.qcow2). The transient install domain must own
# that disk exclusively during install; shut the persistent guest off so the
# lock is released. We restart it (with corrections) after the install.
if [ "${STATE:-}" = "running" ]; then
  log "persistent guest $GUEST is running — shutting it off so the transient install domain can acquire the qcow2 disk lock"
  tower "sudo virsh shutdown '$GUEST'" || die "could not shut off persistent guest $GUEST"
  for _ in $(seq 1 30); do
    if [ "$(tower "sudo virsh domstate '$GUEST'" 2>/dev/null)" = "shut off" ]; then
      log "persistent guest shut off"
      break
    fi
    sleep 5
  done
  [ "$(tower "sudo virsh domstate '$GUEST'" 2>/dev/null)" = "shut off" ] || die "persistent guest $GUEST did not reach shut off state"
fi

# --------------------------------------------------- disk preflight/create --
log "domain dir contents before any change:"
tower "ls -la '$DOMAIN_DIR/' 2>/dev/null || echo '(domain dir absent)'" | tee "$OUT_DIR/disk-preflight.txt"

# search for any fedora-43 disk that may live elsewhere (record only)
tower "find /mnt/pool_one /mnt/pool_two /mnt/user -maxdepth 3 -iname '*fedora*43*' -type f 2>/dev/null; true" |
  tee -a "$OUT_DIR/disk-preflight.txt"

if tower "test -s '$DISK_PATH'"; then
  log "disk exists"
  tower "sudo qemu-img info '$DISK_PATH'" | tee -a "$OUT_DIR/disk-preflight.txt"
else
  # Create the domain dir and a fresh sparse qcow2 if absent.
  # This is authorized by issue #18 scope (provision Fedora 43 to qcow2).
  log "disk $DISK_PATH ABSENT - creating domain dir + fresh qcow2 (sparse)"
  tower "mkdir -p '$DOMAIN_DIR' && sudo qemu-img create -f qcow2 '$DISK_PATH' 60G" |
    tee -a "$OUT_DIR/disk-preflight.txt" || die "qemu-img create failed"
  tower "sudo qemu-img info '$DISK_PATH'" | tee -a "$OUT_DIR/disk-preflight.txt"
fi

# ----------------------------------------------- OVMF firmware discovery ----
# Fedora 43 supports UEFI; OVMF firmware must be present on tower for the
# transient installer domain and the persistent domain to boot.
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
  echo "=== find fallback (code) ==="
  tower "find /usr/share /etc/libvirt /usr/lib -maxdepth 4 -type f \\( -iname 'OVMF_CODE*.bin' -o -iname 'OVMF_CODE*.fd' \\) 2>/dev/null | head -10; true"
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
  tower "find /usr/share /etc/libvirt /usr/lib -maxdepth 4 -type f \\( -iname 'OVMF_VARS*.bin' -o -iname 'OVMF_VARS*.fd' \\) 2>/dev/null | head -10; true"
} >"$OUT_DIR/ovmf-discovery.txt"

OVMF_CODE="$(tower "for p in /usr/share/qemu/ovmf-x64/OVMF_CODE.bin /usr/share/qemu/ovmf-x64/OVMF_CODE.fd /usr/share/qemu/ovmf-x64/OVMF_CODE-pure-efi.bin /usr/share/qemu/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF_CODE.fd /usr/share/edk2/ovmf/OVMF_CODE.fd /usr/share/edk2/ovmf/OVMF_CODE_4M.fd; do test -s \"\$p\" && { echo \"\$p\"; break; }; done")"
[ -n "$OVMF_CODE" ] || OVMF_CODE="$(tower "find /usr/share /etc/libvirt /usr/lib -maxdepth 4 -type f -iname 'OVMF_CODE*' 2>/dev/null | grep -vi secboot | head -1; true")"
OVMF_VARS="$(tower "for p in /usr/share/qemu/ovmf-x64/OVMF_VARS.bin /usr/share/qemu/ovmf-x64/OVMF_VARS.fd /usr/share/qemu/ovmf-x64/OVMF_VARS-pure-efi.bin /usr/share/OVMF/OVMF_VARS.fd /usr/share/ovmf/OVMF_VARS.fd /usr/share/edk2/ovmf/OVMF_VARS.fd /usr/share/edk2/ovmf/OVMF_VARS_4M.fd; do test -s \"\$p\" && { echo \"\$p\"; break; }; done")"
[ -n "$OVMF_VARS" ] || OVMF_VARS="$(tower "find /usr/share /etc/libvirt /usr/lib -maxdepth 4 -type f -iname 'OVMF_VARS*' 2>/dev/null | grep -vi secboot | head -1; true")"

log "OVMF_CODE=$OVMF_CODE"
log "OVMF_VARS=$OVMF_VARS"
[ -n "$OVMF_CODE" ] && [ -n "$OVMF_VARS" ] ||
  die "no OVMF firmware found on tower (Fedora 43 requires UEFI; see ovmf-discovery.txt)"

NVRAM_INSTALL="$DOMAIN_DIR/nvram-install.fd"
NVRAM_PERSIST="$DOMAIN_DIR/nvram.fd"
tower "cp '$OVMF_VARS' '$NVRAM_INSTALL' && cp '$OVMF_VARS' '$NVRAM_PERSIST' && ls -la '$DOMAIN_DIR/'" |
  tee -a "$OUT_DIR/ovmf-discovery.txt" || die "could not stage NVRAM copies in $DOMAIN_DIR"

# ------------------------------------------------- kernel/initrd extraction --
# Fedora 43 may be either a DVD ISO (images/pxeboot/{vmlinuz,initrd.img}) or
# a Workstation Live ISO. The Live ISO uses isolinux/vmlinuz + isoinux/initrd.img
# (BIOS boot) and boot/x86_64/loader/{vmlinuz,initrd} (UEFI). We enumerate
# candidate paths and accept the first pair that extracts.
log "extracting kernel/initrd from ISO (no loop mounts)"
tower "command -v bsdtar; ls -la '$ISO_PATH'" | tee "$OUT_DIR/iso-extract.log"

# Ensure install-media scratch dir exists before extracting into it
tower "mkdir -p '$DOMAIN_DIR/install-media'" | tee -a "$OUT_DIR/iso-extract.log"

# Discover ISO structure first
tower "bsdtar -t -f '$ISO_PATH' 2>/dev/null | grep -iE 'pxeboot|isolinux|vmlinuz|initrd|boot/x86_64/loader|LiveOS|/linux$|images/pxeboot' | head -40 || echo '(no standard paths found)'" |
  tee -a "$OUT_DIR/iso-extract.log"

# Candidate kernel/initrd path pairs, in preference order. First column is the
# pair prefix under install-media/ after extraction.
EXTRACT_OK=""
for KERNEL_PATH in \
  "isolinux/vmlinuz" \
  "images/pxeboot/vmlinuz" \
  "boot/x86_64/loader/vmlinuz" \
  "boot/x86_64/loader/linux" \
  "boot/vmlinuz" ; do
  for INITRD_PATH in \
    "isolinux/initrd.img" \
    "images/pxeboot/initrd.img" \
    "images/pxeboot/initrd" \
    "boot/x86_64/loader/initrd" \
    "boot/initrd" ; do
    if tower "cd '$DOMAIN_DIR/install-media' 2>/dev/null && bsdtar -x -f '$ISO_PATH' '$KERNEL_PATH' '$INITRD_PATH' 2>/dev/null && test -f '$KERNEL_PATH' && test -f '$INITRD_PATH'"; then
      log "extracted kernel=$KERNEL_PATH initrd=$INITRD_PATH"
      tower "cd '$DOMAIN_DIR/install-media' && mv '$KERNEL_PATH' vmlinuz && mv '$INITRD_PATH' initrd.img && rmdir 2>/dev/null isolinux images/pxeboot boot/x86_64/loader boot; true; ls -la" |
        tee -a "$OUT_DIR/iso-extract.log"
      EXTRACT_OK=1
      break 2
    fi
  done
done

if [ -z "$EXTRACT_OK" ]; then
  log "WARN: direct extraction failed; showing ISO contents for diagnosis"
  tower "bsdtar -t -f '$ISO_PATH' 2>/dev/null | head -60" |
    tee -a "$OUT_DIR/iso-extract.log"
  die "kernel/initrd extraction failed (ISO layout not recognized; Live ISOs need isolinux/ or boot/x86_64/loader/ paths)"
fi

tower "test -s '$DOMAIN_DIR/install-media/vmlinuz' && test -s '$DOMAIN_DIR/install-media/initrd.img' && echo KERNEL-OK" |
  tee -a "$OUT_DIR/iso-extract.log" ||
  die "kernel/initrd extraction failed (files not found at install-media after extraction)"

# ------------------------------------------------------- kickstart serving --
KEYSRC=""
if [ -r /root/.ssh/id_ed25519.pub ]; then
  KEYSRC=/root/.ssh/id_ed25519.pub
elif [ -r /root/.ssh/id_ed25519 ]; then
  ssh-keygen -y -f /root/.ssh/id_ed25519 >"$OUT_DIR/hermes-key.pub" && KEYSRC="$OUT_DIR/hermes-key.pub"
fi
[ -n "$KEYSRC" ] || die "no Hermes key material at /root/.ssh/id_ed25519(.pub)"
log "hermes key: $(ssh-keygen -lf "$KEYSRC" | awk '{print $1, $2}')"

# The fedora-43 CI stages (transfer/install/vmtest) authenticate with the
# VM_SSH_KEY CI file variable; when that variable is exposed to this job
# (protected-scope pipelines), authorize its public half too so the
# stages can run against the VM exactly as wired in the repo.
VMKEY_NOTE="VM_SSH_KEY not exposed to this job (protected-variable scope); fedora-43 stages will be evaluated via the runner key path"
if [ -f "${VM_SSH_KEY:-}" ]; then
  ssh-keygen -y -f "$VM_SSH_KEY" >"$OUT_DIR/vmsshkey.pub" 2>/dev/null &&
    VMKEY_NOTE="VM_SSH_KEY exposed; public half added to authorized_keys" ||
    VMKEY_NOTE="VM_SSH_KEY present but did not parse; not authorized"
fi
log "vm stage key: $VMKEY_NOTE"

# build the kickstart with the workforce key line appended (public half only)
KS_LOCAL="$OUT_DIR/fedora43-ks.cfg"
{
  cat "$HERE/fedora-43-kickstart.cfg"
  echo "sshkey --username=root \"$(cat "$KEYSRC")\""
  if [ -s "$OUT_DIR/vmsshkey.pub" ]; then
    echo "sshkey --username=root \"$(cat "$OUT_DIR/vmsshkey.pub")\""
  fi
} >"$KS_LOCAL"

scp $SSH_OPTS "$KS_LOCAL" "$TOWER_HOST:/tmp/" >/dev/null 2>&1 || die "kickstart upload failed"
tower "mkdir -p '$KS_DIR' && mv /tmp/fedora43-ks.cfg '$KS_DIR/fedora43-ks.cfg' && chmod 644 '$KS_DIR/fedora43-ks.cfg'" ||
  die "kickstart staging failed"

# busybox httpd: Unraid ships busybox; verify and serve on the LAN port.
tower "command -v busybox || ls /usr/bin/busybox /usr/sbin/busybox 2>/dev/null" | tee "$OUT_DIR/httpd.log"
tower "nohup busybox httpd -f -v -p '$KS_PORT' -h '$KS_DIR' > /tmp/fedora43-httpd.log 2>&1 & echo httpd-pid=\$!" |
  tee -a "$OUT_DIR/httpd.log" || die "busybox httpd failed to start"
sleep 3
tower "wget -q -O- 'http://127.0.0.1:$KS_PORT/fedora43-ks.cfg' | head -3 || curl -s 'http://127.0.0.1:$KS_PORT/fedora43-ks.cfg' | head -3" |
  tee -a "$OUT_DIR/httpd.log" || die "kickstart not fetchable on tower"

# ------------------------------------------------------------------ transient domain --
log "defining transient install domain $TRANSIENT (OVMF UEFI)"
cat >"$OUT_DIR/transient.xml" <<XML
<domain type='kvm'>
  <name>$TRANSIENT</name>
  <description>transient fedora-43 install session (issue #18)</description>
  <memory unit='MiB'>4096</memory>
  <currentMemory unit='MiB'>4096</currentMemory>
  <vcpu>2</vcpu>
  <os>
    <type arch='x86_64' machine='pc-q35-9.2'>hvm</type>
    <loader readonly='yes' type='pflash'>$OVMF_CODE</loader>
    <nvram>$NVRAM_INSTALL</nvram>
    <kernel>$DOMAIN_DIR/install-media/vmlinuz</kernel>
    <initrd>$DOMAIN_DIR/install-media/initrd.img</initrd>
    <cmdline>console=ttyS0,115200 inst.ks=http://$TOWER_IP:$KS_PORT/fedora43-ks.cfg inst.repo=cdrom:/dev/sr0 ip=$VM_IP::192.168.1.1:255.255.255.0:$GUEST:none nameserver=192.168.1.1</cmdline>
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
ssh $SSH_OPTS "$TOWER_HOST" "sudo virsh define /dev/stdin" <"$OUT_DIR/transient.xml" ||
  die "transient define failed"

# ------------------------------------------------------------------ install --
log "starting transient domain $TRANSIENT"
tower "sudo virsh start '$TRANSIENT'" || die "transient start failed"

# Drive the console from the RUNNER (expect runs here, apk-added in the job
# image) through the proven pty chain: expect -> ssh -tt tower -> virsh console.
export VM_KNOWN_HOSTS
expect "$HERE/fedora-43-console.tcl" "$TRANSIENT" "$CONSOLE_BUDGET" 2>&1 | tee "$CONSOLE_LOG"
CONSOLE_RC="${PIPESTATUS[0]}"

# stop serving the kickstart as soon as the console session ends
tower "pkill -f 'httpd.*fedora43-ks' 2>/dev/null" >/dev/null 2>&1 || true

if [ "$CONSOLE_RC" != "0" ]; then
  log "console driver failed rc=$CONSOLE_RC (transient domain cleanup via trap)"
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
# Fedora 43 supports UEFI; add the OVMF loader to the persistent domain if
# not already present. Also ensure the interface is attached to br0 with
# IP 192.168.1.183 — the inventory (note on #18) showed the fedora43 guest's
# bridge interface was missing <source bridge='br0'/>, causing it to fall
# back to the default network (192.168.122.x) and remain unreachable at .183.
# We rewrite the interface block to include <source bridge='br0'/> while
# preserving the MAC address.
NEEDS_REDEFINE="no"
if ! tower "sudo virsh dumpxml '$GUEST'" | grep -q "<loader"; then
  NEEDS_REDEFINE="yes"
  log "persistent guest lacks OVMF loader — will redefine with UEFI firmware"
elif ! tower "sudo virsh dumpxml '$GUEST'" | grep -q "<source bridge='br0'>"; then
  NEEDS_REDEFINE="yes"
  log "persistent guest lacks br0 bridge source — will redefine with <source bridge='br0'/>"
fi

if [ "$NEEDS_REDEFINE" = "yes" ]; then
  log "redefining persistent guest $GUEST (OVMF loader + br0 network)"
  tower "sudo virsh dumpxml '$GUEST'" >"$OUT_DIR/persistent-before.xml"
  : >"$OUT_DIR/persistent-after.xml"
  WHILE_MAC=""
  while IFS= read -r line; do
    printf '%s\\n' "$line" >>"$OUT_DIR/persistent-after.xml"
    case "$line" in
      *"machine='pc-q35-9.2'>hvm</type>"*)
        # Inject OVMF loader + NVRAM if not already present
        if ! grep -q "<loader" "$OUT_DIR/persistent-after.xml" 2>/dev/null; then
          printf "    <loader readonly=%s type=%s>%s</loader>\\n" "'yes'" "'pflash'" "$OVMF_CODE" >>"$OUT_DIR/persistent-after.xml"
          printf "    <nvram>%s</nvram>\\n" "$NVRAM_PERSIST" >>"$OUT_DIR/persistent-after.xml"
        fi
        ;;
      *"<interface type='bridge'>"*)
        # We are inside the interface block; read the next line to find MAC,
        # then inject <source bridge='br0'/> if missing. We handle this with
        # a targeted sed-style rewrite below after the loop.
        ;;
    esac
  done <"$OUT_DIR/persistent-before.xml"

  # Post-process: fix the network interface to ensure <source bridge='br0'/>.
  # If the interface block lacks a <source bridge='br0'/> line, insert it
  # right after the <interface type='bridge'> line, preserving the MAC.
  # Use a portable approach: check and insert via awk.
  if ! grep -q "<source bridge='br0'>" "$OUT_DIR/persistent-after.xml"; then
    awk '
      /^\s*<interface type=.bridge.>/ {
        print
        getline next_line
        if (next_line ~ /<source bridge=.br0.>/) {
          print next_line
        } else {
          print "      <source bridge='\''br0'\''/>"
          print next_line
        }
        next
      }
      { print }
    ' "$OUT_DIR/persistent-after.xml" >"$OUT_DIR/persistent-after-fixed.xml" \
      && mv "$OUT_DIR/persistent-after-fixed.xml" "$OUT_DIR/persistent-after.xml"
  fi

  grep -q "<loader" "$OUT_DIR/persistent-after.xml" ||
    die "failed to inject OVMF loader into persistent domain XML"
  grep -q "<source bridge='br0'>" "$OUT_DIR/persistent-after.xml" ||
    die "failed to inject br0 bridge source into persistent domain XML"
  ssh $SSH_OPTS "$TOWER_HOST" "sudo virsh define /dev/stdin" \
    <"$OUT_DIR/persistent-after.xml" >"$OUT_DIR/persistent-domain-define.log" 2>&1 ||
    {
      cat "$OUT_DIR/persistent-domain-define.log"
      die "persistent domain redefine failed"
    }
  log "persistent domain redefined with OVMF + br0 (see persistent-domain-define.log)"
else
  log "persistent guest already carries firmware loader and br0 bridge source"
fi

# --------------------------------------------------- boot + acceptance ------
log "booting persistent guest $GUEST"
tower "sudo virsh start '$GUEST'" || die "persistent guest failed to start"

log "waiting for TCP/22 at $VM_IP (up to 600s: first boot + relabel)"
up=0
for _ in $(seq 1 120); do
  if (exec 3<>"/dev/tcp/$VM_IP/22") 2>/dev/null; then
    up=1
    exec 3>&-
    break
  fi
  sleep 5
done
[ "$up" = "1" ] || die "sshd never came up at $VM_IP"

log "SSH probe from the runner (workforce key installed by kickstart)"
ssh $SSH_OPTS -o ConnectTimeout=15 "root@$VM_IP" \
  "hostname; whoami; uname -a; cat /etc/redhat-release" | tee "$OUT_DIR/ssh-probe.txt" ||
  die "SSH probe failed"

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
  "systemctl is-active sshd qemu-guest-agent; systemctl is-enabled sshd qemu-guest-agent; ip -4 addr show; grep -c ssh-ed25519 /root/.ssh/authorized_keys; rpm -q qemu-guest-agent openssh-server; test -d /boot/efi && echo ESP-PRESENT; efibootmgr | head -8" |
  tee -a "$OUT_DIR/acceptance.txt" || die "in-guest verification failed"

echo "=== guest agent ping (virsh) ==="
tower "sudo virsh qemu-agent-command '$GUEST' '{\"execute\":\"guest-ping\"}'" |
  tee -a "$OUT_DIR/acceptance.txt" || log "WARN: guest-ping failed (check agent in guest)"

echo "=== fedora-43 CI transport smoke (same transport as transfer/install stages) ==="
ssh $SSH_OPTS "root@$VM_IP" \
  "dnf -v repolist --enabled 2>/dev/null | grep -iE 'fedora|updates' || echo 'WARN: repos not visible'" |
  tee -a "$OUT_DIR/acceptance.txt" || true

log "=== provisioning complete ==="
echo '{"hypervisor":"tower","vm_ip":"'$VM_IP'","guest":"'$GUEST'","provisioned_at":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"' >"$OUT_DIR/provision-result.json"
exit 0
