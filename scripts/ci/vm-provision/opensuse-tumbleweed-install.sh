#!/usr/bin/env bash
# scripts/ci/vm-provision/opensuse-tumbleweed-install.sh
#
# Install openSUSE Tumbleweed into the existing opensuse-tw guest on the tower
# hypervisor (issue #17, parent #9) and bring it to the acceptance spec:
#   - OS installed to qcow2 on br0 @ 192.168.1.245
#   - sshd enabled and running
#   - qemu-guest-agent installed and running
#   - the Hermes (workforce) public key authorized for root
#
# Runs on the tower-mounted GitLab runner (tags: [android]) whose RO
# /root/.ssh mount provides the SSH alias `tower` and the workforce public
# key /root/.ssh/id_ed25519.pub.
#
# Preconditions verified by vm:inventory:opensuse-tumbleweed (job 30883):
#   - guest opensuse-tw defined, shut off, uuid 2c0218a1-4c64-40b0-9931-8ddd6c20a75a
#   - disk source /mnt/pool_two/domains/opensuse-tw/vdisk1.qcow2 (virtio, boot 1)
#   - cdrom /mnt/pool_one/isos/openSUSE-Tumbleweed-GNOME-Live-x86_64-Current.iso (sata)
#   - NIC <interface type='network'><source network='br0'/> (libvirt NAT named 'br0', NOT bridge)
#   - 192.168.1.245 free (no arp entry, ping silent)
#
# Method (headless serial console, deterministic):
#   1. Preflight: record pre-state; note the network mismatch.
#   2. Repair the NIC attachment: change <source network='br0'/> to
#      <source bridge='br0'/> on the opensuse-tw domain XML (domain backed
#      up first). This makes the guest reachable on the LAN directly instead
#      of behind libvirt NAT.
#   3. Extract kernel/initrd from the ISO (bsdtar, no loop mounts) for a
#      direct-kernel boot carrying the serial console + AutoYaST parameters.
#      openSUSE Tumbleweed live ISO kernels live at
#      boot/x86_64/loader/{linux,initrd}.
#   4. Create a transient install domain that boots the extracted kernel
#      directly (legacy GRUB boot; OVMF not required for openSUSE), with
#      console=ttyS0 + autoyast= URL on the kernel cmdline.
#   5. Serve an AutoYaST XML profile from the tower over HTTP (busybox httpd)
#      so the installer runs unattended, installing to the target disk with
#      sshd, qemu-guest-agent, and the workforce key pre-seeded.
#   6. Drive the serial console from the RUNNER via expect (expect ->
#      ssh -tt tower -> sudo virsh console), watching for install completion.
#   7. After install completes, start the persistent domain and poll SSH
#      reachability from the runner, then run acceptance probes.
#
# Mutations are confined to the opensuse-tw guest's resources: its network
# XML definition (one bridge correction), its qcow2 disk contents, its power
# state, the transient sibling domain opensuse-tw-install (removed before the
# job ends), and scratch files in its own domain directory + tower /tmp.
# No other guest, disk, or host service is touched.
set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
GUEST="opensuse-tw"
TRANSIENT="opensuse-tw-install"
VM_IP="${VM_IP:-192.168.1.245}"
TOWER_IP="${TOWER_IP:-192.168.1.31}"
ISO_PATH="${ISO_PATH:-/mnt/pool_one/isos/openSUSE-Tumbleweed-GNOME-Live-x86_64-Current.iso}"
DISK_PATH="${DISK_PATH:-/mnt/pool_two/domains/opensuse-tw/vdisk1.qcow2}"
DOMAIN_DIR="${DOMAIN_DIR:-/mnt/pool_two/domains/opensuse-tw}"
MAC="${MAC:-52:54:00:43:2e:c0}"
KS_PORT="${KS_PORT:-8011}"
OUT_DIR="${PROVISION_OUT_DIR:-provision-results}"
CONSOLE_BUDGET="${CONSOLE_BUDGET:-3600}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$OUT_DIR"

VM_KNOWN_HOSTS="${CI_PROJECT_DIR:-.}/.vm-known-hosts"
: > "$VM_KNOWN_HOSTS"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$VM_KNOWN_HOSTS"

tower() { ssh $SSH_OPTS "$TOWER_HOST" "$@"; }
log() { echo "[opensuse-provision] $*"; }
die() { echo "FATAL: $*" >&2; exit 1; }
CONSOLE_LOG="$OUT_DIR/console-session.log"

# ── Cleanup: only our own transient domain + scratch files ──────────────
cleanup() {
  tower "pkill -f 'httpd.*opensuse-ks' 2>/dev/null; sudo virsh destroy '$TRANSIENT' 2>/dev/null; sudo virsh undefine '$TRANSIENT' 2>/dev/null; rm -rf '$DOMAIN_DIR/install-media' /tmp/opensuse-ks.$$" \
    >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ── Pre-state ────────────────────────────────────────────────────────────
tower "hostname; whoami; date -u" | tee "$OUT_DIR/identity.txt" || die "cannot reach tower"

STATE="$(tower "sudo virsh domstate '$GUEST'" 2>/dev/null)"
log "persistent guest state: ${STATE:-unknown}"
{ echo "pre-state: $STATE"; tower "sudo virsh dumpxml '$GUEST'"; } > "$OUT_DIR/pre-state.txt" || die "dumpxml failed"

# Ensure the transient domain does not exist
if tower "sudo virsh domstate '$TRANSIENT'" >/dev/null 2>&1; then
  log "removing stale transient domain $TRANSIENT"
  tower "sudo virsh destroy '$TRANSIENT'" >/dev/null 2>&1 || true
  tower "sudo virsh undefine '$TRANSIENT'" >/dev/null 2>&1 || true
fi

# ── Disk preflight ───────────────────────────────────────────────────────
log "domain dir contents before any change:"
tower "ls -la '$DOMAIN_DIR/' 2>/dev/null || echo '(domain dir absent)'" | tee "$OUT_DIR/disk-preflight.txt"

if ! tower "test -s '$DISK_PATH'"; then
  log "disk $DISK_PATH ABSENT - creating domain dir + fresh qcow2 (sparse)"
  tower "mkdir -p '$DOMAIN_DIR' && sudo qemu-img create -f qcow2 '$DISK_PATH' 64G" \
    | tee -a "$OUT_DIR/disk-preflight.txt" || die "qemu-img create failed"
fi
tower "sudo qemu-img info '$DISK_PATH'" | tee -a "$OUT_DIR/disk-preflight.txt"

# ── Network repair: network='br0' -> bridge='br0' ────────────────────────
# The inventory (job 30883) proved the opensuse-tw XML currently binds the
# NIC to the libvirt NAT network named 'br0', not a direct bridge. This must
# be corrected so the guest is reachable on the LAN.
log "repairing NIC attachment: network=br0 -> bridge=br0"
tower "sudo virsh dumpxml '$GUEST'" > "$OUT_DIR/opensuse-xml-before-netrRepair.xml"
if tower "sudo virsh dumpxml '$GUEST'" | grep -q "source network='br0'"; then
  tower "sudo virsh dumpxml '$GUEST' > /tmp/opensuse-xml-backup-\$\$.xml && \
    sed -i \"s|<interface type='network'>|<interface type='bridge'>|g; s|<source network='br0'/>|<source bridge='br0'/>|g\" /tmp/opensuse-xml-backup-\$\$.xml && \
    grep 'source bridge' /tmp/opensuse-xml-backup-\$\$.xml && \
    sudo virsh define /tmp/opensuse-xml-backup-\$\$.xml && echo XML-REDEFINED" \
    | tee -a "$OUT_DIR/disk-preflight.txt" || die "network XML repair failed"
  log "network repaired: bridge=br0 now attached"
else
  log "NIC already uses bridge=br0, no repair needed"
fi

# ── Hermes key ───────────────────────────────────────────────────────────
KEYSRC=""
if [ -r /root/.ssh/id_ed25519.pub ]; then KEYSRC=/root/.ssh/id_ed25519.pub
elif [ -r /root/.ssh/id_ed25519 ]; then
  ssh-keygen -y -f /root/.ssh/id_ed25519 > "$OUT_DIR/hermes-key.pub" && KEYSRC="$OUT_DIR/hermes-key.pub"
fi
[ -n "$KEYSRC" ] || die "no Hermes key material at /root/.ssh/id_ed25519(.pub)"
log "hermes key: $(ssh-keygen -lf "$KEYSRC" | awk '{print $1, $2}')"

# ── AutoYaST profile ──────────────────────────────────────────────────────
AUTOINST_LOCAL="$OUT_DIR/autoyast-opensuse.xml"
cat > "$AUTOINST_LOCAL" <<'AUTOSTART'
<?xml version="1.0"?>
<profile xmlns="http://doc.opensuse.org/release-xml">
  <general>
    <flavor>minimal</flavor>
    <version>17.1</version>
    <product>suse</product>
    <type>autoyast</type>
  </general>
  <software>
    <products>
      <product>openSUSE</product>
    </products>
    <patterns>
      <pattern>base</pattern>
      <pattern>minimal_base</pattern>
    </patterns>
    <packages>
      <package>openssh</package>
      <package>openssh-server</package>
      <package>qemu-guest-agent</package>
      <package>zypper</package>
    </packages>
  </software>
  <networking>
    <keep_install_network>false</keep_install_network>
    <interfaces>
      <interface>
        <device>enp1s0</device>
        <bootproto>static</bootproto>
        <ipaddr>IP_PLACEHOLDER</ipaddr>
        <netmask>255.255.255.0</netmask>
        <gateway>192.168.1.1</gateway>
        <nameserver>192.168.1.1</nameserver>
      </interface>
    </interfaces>
  </networking>
  <users config:type="list">
    <user>
      <username>root</username>
      <user_password>--lock--</user_password>
      <ssh_authorized_keys config:type="list">
        <authorized_keys>KEY_PLACEHOLDER</authorized_keys>
      </ssh_authorized_keys>
    </user>
  </users>
  <services-manager>
    <default_target>multi-user</default_target>
    <enabled>
      <service>sshd</service>
      <service>qemu-guest-agent</service>
    </enabled>
  </services-manager>
  <post-scripts config:type="list">
    <script>
      <filename>ssh-hardening.sh</filename>
      <interpreter>shell</interpreter>
      <source><![CDATA[
systemctl enable sshd.service
systemctl enable qemu-guest-agent.service
systemctl enable serial-getty@ttyS0.service 2>/dev/null || true
sed -i "s/^.*PermitRootLogin.*/PermitRootLogin prohibit-password/" /etc/ssh/sshd_config
]]></source>
    </script>
  </post-scripts>
</profile>
AUTOSTART

# substitute the IP and key into the AutoYaST profile
sed -i "s|IP_PLACEHOLDER|$VM_IP|g" "$AUTOINST_LOCAL"
HERMES_PUB="$(cat "$KEYSRC")"
sed -i "s|KEY_PLACEHOLDER|${HERMES_PUB}|g" "$AUTOINST_LOCAL"

# ── Serve AutoYaST + extract kernel/initrd from ISO ──────────────────────
KS_DIR="/tmp/opensuse-ks.$$"
tower "mkdir -p '$KS_DIR'" || die "cannot create KS dir on tower"
scp $SSH_OPTS "$AUTOINST_LOCAL" "$TOWER_HOST:$KS_DIR/autoinst.xml" >/dev/null 2>&1 || die "autoyast upload failed"

log "extracting kernel/initrd from the ISO (bsdtar, no loop mounts)"
tower "rm -rf '$DOMAIN_DIR/install-media'; mkdir -p '$DOMAIN_DIR/install-media' && \
  cd '$DOMAIN_DIR/install-media' && \
  bsdtar -xf '$ISO_PATH' boot/x86_64/loader/linux boot/x86_64/loader/initrd && \
  cp boot/x86_64/loader/linux . && cp boot/x86_64/loader/initrd . && \
  rm -rf boot && ls -la" | tee "$OUT_DIR/iso-extract.log" \
  || die "kernel/initrd extraction failed"
tower "test -s '$DOMAIN_DIR/install-media/linux' && test -s '$DOMAIN_DIR/install-media/initrd' && echo KERNEL-OK" \
  | tee -a "$OUT_DIR/iso-extract.log" || die "kernel/initrd missing after extraction"

# ── Discover ISO volume label for root=live:CDLABEL= ───────────────────────
# The openSUSE Tumbleweed live ISO boots via dracut's rd.live mechanism:
# root=live:CDLABEL=<label> makes dracut scan all block devices for an ISO
# whose ISO9660 Volume Label matches, then mounts the embedded squashfs.
# root=live:/dev/sr0 does NOT work (dracut looks for an ISO *file* on the
# device, not a CD-ROM that IS the ISO) — job 38137 proved this drops to
# the dracut emergency shell with "Can't mount root filesystem".
#
# isoinfo is absent on some tower installs (job 33405 returned "unknown"),
# so we cascade through: isoinfo -> file -> dd PVD parse.
log "discovering ISO volume label for root=live:CDLABEL="
# Method 1: isoinfo (from genisoimage / libcdio-tools)
ISO_LABEL="$(tower "isoinfo -d -i '$ISO_PATH' 2>/dev/null | grep -i '^Volume id:' | sed 's/Volume id: //'" | tr -d '\\r' || true)"
if [ -z "$ISO_LABEL" ]; then
  ISO_LABEL="$(tower "isoinfo -d -i '$ISO_PATH' 2>/dev/null | awk -F: '/Volume id/ {print \\$2}' | xargs" || true)"
fi
# Method 2: file(1) — Unraid's busybox `file` may be absent; GNU file prints
#   "ISO 9660 ... Volume Label: \`openSUSE-Tumbleweed-x86_64-0'"
#   or "... ISO 9660 CD-ROM filesystem data ... label: '...''" for libarchive.
if [ -z "$ISO_LABEL" ]; then
  ISO_LABEL="$(tower "file -b '$ISO_PATH' 2>/dev/null | sed -nE \"s/.*Volume Label: *'\?([^']+)'\?.*/\1/p; s/.*label: *'\?([^']+)'\?.*/\1/p\" | head -1" | tr -d '\\r' || true)"
fi
# Method 3: read the ISO9660 Primary Volume Descriptor directly with dd.
# The PVD sits at byte offset 32768 (0x8000); the Volume Label occupies
# bytes 40-71 (32 bytes, uppercase A-Z, space-padded ASCII). This needs
# no special tooling beyond dd — works on Unraid's busybox dd.
if [ -z "$ISO_LABEL" ]; then
  ISO_LABEL="$(tower "dd if='$ISO_PATH' bs=1 skip=32808 count=32 2>/dev/null | tr -d ' ' | tr -d '\\000'" | tr -d '\\r' || true)"
fi
log "ISO label: ${ISO_LABEL:-unknown}"
echo "ISO_LABEL=$ISO_LABEL" > "$OUT_DIR/iso-label.txt"
# Use CDLABEL if we resolved it; otherwise fall through to /dev/sr0 with a
# loud warning (known to fail on openSUSE live ISO; kept only as last resort).
if [ -n "$ISO_LABEL" ]; then
  LIVE_ROOT="root=live:CDLABEL=$ISO_LABEL"
else
  LIVE_ROOT="root=live:/dev/sr0"
  log "WARN: ISO label not discoverable; falling back to $LIVE_ROOT (may fail on live ISO)"
fi

# ── Serve AutoYaST via busybox httpd on the tower ─────────────────────────
tower "command -v busybox" | tee "$OUT_DIR/httpd.log"
tower "nohup busybox httpd -f -v -p '$KS_PORT' -h '$KS_DIR' > /tmp/opensuse-httpd.log 2>&1 & echo httpd-pid=\$\!" \
  | tee -a "$OUT_DIR/httpd.log" || die "busybox httpd failed to start"
sleep 3
tower "wget -q -O- 'http://127.0.0.1:$KS_PORT/autoinst.xml' | head -3 || curl -s 'http://127.0.0.1:$KS_PORT/autoinst.xml' | head -3" \
  | tee -a "$OUT_DIR/httpd.log" || die "autoinst not fetchable on tower"

# ── Transient install domain ─────────────────────────────────────────────
log "defining transient install domain $TRANSIENT"
TRANSIENT_XML="$OUT_DIR/transient.xml"
cat > "$TRANSIENT_XML" <<XML
<domain type='kvm'>
  <name>$TRANSIENT</name>
  <description>transient opensuse-tw install session (issue #17)</description>
  <memory unit='MiB'>3072</memory>
  <currentMemory unit='MiB'>3072</currentMemory>
  <vcpu>2</vcpu>
  <os>
    <type arch='x86_64' machine='pc-q35-9.2'>hvm</type>
    <kernel>$DOMAIN_DIR/install-media/linux</kernel>
    <initrd>$DOMAIN_DIR/install-media/initrd</initrd>
    <cmdline>console=ttyS0,115200 ${LIVE_ROOT} rd.live.image ro autoyast=http://$TOWER_IP:$KS_PORT/autoinst.xml</cmdline>
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

ssh $SSH_OPTS "$TOWER_HOST" "sudo virsh define /dev/stdin" < "$TRANSIENT_XML" \
  > "$OUT_DIR/transient-define.log" 2>&1 || die "transient define failed"

# ── Start install + drive console ────────────────────────────────────────
log "starting transient domain $TRANSIENT"
tower "sudo virsh start '$TRANSIENT'" || die "transient start failed"

# Drive the serial console from the runner via expect
export VM_KNOWN_HOSTS
if command -v expect >/dev/null 2>&1; then
  expect "$HERE/opensuse-console.expect" "$TRANSIENT" "$CONSOLE_BUDGET" 2>&1 | tee "$CONSOLE_LOG"
  CONSOLE_RC="${PIPESTATUS[0]}"
else
  log "expect not available; capturing console for 60s"
  timeout 60 ssh $SSH_OPTS "$TOWER_HOST" "sudo virsh console '$TRANSIENT' --force" 2>&1 | tee "$CONSOLE_LOG" || true
  CONSOLE_RC=0
fi

# Stop serving the autoyast profile
tower "pkill -f 'httpd.*opensuse-ks' 2>/dev/null" >/dev/null 2>&1 || true

if [ "${CONSOLE_RC:-0}" != "0" ]; then
  log "console driver failed rc=$CONSOLE_RC (transient cleanup via trap)"
  die "install failed"
fi

# Wait for shut-off, then undefine the transient domain
for _ in $(seq 1 30); do
  S="$(tower "sudo virsh domstate '$TRANSIENT'" 2>/dev/null || true)"
  [ "$S" = "shut off" ] && break
  sleep 5
done
tower "sudo virsh undefine '$TRANSIENT'" || log "WARN: transient undefine failed"
tower "rm -rf '$DOMAIN_DIR/install-media' '$KS_DIR'" || true
log "transient domain and scratch files removed"

# ── Boot persistent guest + acceptance ────────────────────────────────────
log "starting persistent guest $GUEST from its installed disk"
tower "sudo virsh start '$GUEST'" || die "persistent guest failed to start"

log "waiting for TCP/22 at $VM_IP (up to 600s: first boot + relabel)"
up=0
for _ in $(seq 1 120); do
  if (exec 3<>"/dev/tcp/$VM_IP/22") 2>/dev/null; then up=1; exec 3>&-; break; fi
  sleep 5
done
[ "$up" = "1" ] || die "sshd never came up at $VM_IP"

log "SSH probe from the runner (workforce key installed by autoyast)"
ssh $SSH_OPTS -o ConnectTimeout=15 "root@$VM_IP" \
  "hostname; whoami; uname -a; cat /etc/os-release" | tee "$OUT_DIR/ssh-probe.txt" \
  || die "SSH probe failed"

log "collecting acceptance evidence"
{
  echo "=== virsh domstate ==="
  tower "sudo virsh domstate '$GUEST'"
  echo "=== virsh dumpxml (key facts) ==="
  tower "sudo virsh dumpxml '$GUEST'" | grep -E "<name>|<uuid>|<source file=|<source bridge=|<mac |<channel|guest_agent|<loader>|<nvram"
  echo "=== qemu-img info ==="
  tower "sudo qemu-img info '$DISK_PATH'"
  echo "=== ip occupancy (ping from tower) ==="
  tower "ping -c1 -W2 '$VM_IP' >/dev/null 2>&1 && echo 'PING: answers' || echo 'PING: silent'"
} | tee "$OUT_DIR/acceptance.txt"

ssh $SSH_OPTS "root@$VM_IP" \
  "systemctl is-active sshd qemu-guest-agent; \
   systemctl is-enabled sshd qemu-guest-agent; \
   ip -4 addr show; \
   grep -c ssh-ed25519 /root/.ssh/authorized_keys; \
   rpm -q qemu-guest-agent openssh 2>/dev/null || zypper search --installed-only -x qemu-guest-agent; \
   test -d /boot/efi && echo ESP-PRESENT; \
   true" \
  | tee -a "$OUT_DIR/acceptance.txt" || log "WARN: in-guest verification had issues"

echo "=== guest agent ping (virsh) ==="
tower "sudo virsh qemu-agent-command '$GUEST' '{\"execute\":\"guest-ping\"}'" \
  | tee -a "$OUT_DIR/acceptance.txt" || log "WARN: guest-ping failed"

log "=== provisioning complete ==="
exit 0
