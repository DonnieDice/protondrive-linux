#!/usr/bin/env bash
# scripts/ci/vm-provision/ubuntu-26.04-install.sh
#
# Install Ubuntu 26.04 into the existing ubuntu2604 guest domain on the
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
#   - guest ubuntu2604 defined (may be running or shut off; the driver
#     destroys it if running so the transient install domain can lock the
#     qcow2 disk, then re-starts the persistent guest after install)
#   - br0 network exists and is active
#   - 192.168.1.168 free (no arp entry, ping silent) unless pre-existing
#   - Ubuntu 26.04 live ISO available on tower at /mnt/pool_one/isos/
#
# Method (Subiquity autoinstall, headless, no VNC, deterministic):
#   1. Preflight: record pre-state; ensure the qcow2 + domain XML exist.
#   2. Derive the workforce public key via ssh-keygen -y (never trust a
#      stale .pub sidecar — fixes permission-denied probe failures).
#   3. Extract the live-server kernel/initrd from the ISO on tower (bsdtar).
#   4. Build a Subiquity autoinstall user-data with the workforce key
#      injected, serve it over the LAN from tower with busybox httpd.
#   5. Define a TRANSIENT domain ubuntu2604-install reusing ONLY the guest's
#      real qcow2 disk + br0 NIC, booting the extracted kernel directly with
#      console=ttyS0 and autoinstall url=http://192.168.1.31:<port>/user-data.
#      The persistent domain XML is never edited during install.
#   6. Drive the serial console from the RUNNER via expect (expect -> ssh -tt
#      tower -> sudo virsh console -> guest ttyS0).
#   7. Subiquity autoinstall runs unattended; watch for the late-command
#      marker and the final reboot.
#   8. Undefine the transient domain, boot the persistent ubuntu2604 domain
#      from its installed disk, and run the acceptance probes (SSH from the
#      runner with the same key, in-guest service status, virsh guest-ping,
#      qemu-img info).
#
# Mutations are confined to the ubuntu2604 guest's resources: its qcow2 disk
# file (created when absent), disk contents, power state, the transient
# sibling domain ubuntu2604-install (removed before the job ends), and
# scratch files in its own domain directory + tower /tmp. No other guest,
# disk, network, or host service is touched.
#
# Scope note: Ubuntu 26.04 live ISOs use the Subiquity installer, not
# debian-installer (d-i). The autoinstall format is a cloud-init user-data
# YAML with an `autoinstall` key, distinct from the d-i preseed format.
# The tower only has the desktop live ISO; both server and desktop live
# ISOs use Subiquity and support the same autoinstall kernel cmdline.
# We use BIOS/SeaBIOS boot, matching debian12/debian13 guests that already
# boot successfully on tower.
set -uo pipefail

# ------------------------------------------------------------- config --------
TOWER_HOST="${TOWER_HOST:-tower}"
GUEST="${GUEST:-ubuntu2604}"
TRANSIENT="${TRANSIENT:-ubuntu2604-install}"
VM_IP="${VM_IP:-192.168.1.168}"
TOWER_IP="${TOWER_IP:-192.168.1.31}"
# Tower inventory shows ubuntu-26.04-desktop-amd64.iso at /mnt/pool_one/isos/
ISO_PATH="${ISO_PATH:-/mnt/pool_one/isos/ubuntu-26.04-desktop-amd64.iso}"
DISK_PATH="${DISK_PATH:-/mnt/pool_two/domains/ubuntu2604/vdisk1.qcow2}"
DOMAIN_DIR="${DOMAIN_DIR:-/mnt/pool_two/domains/ubuntu2604}"
MAC="${MAC:-52:54:00:e3:5b:6e}"
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
KS_HTTPD_PID_FILE="/tmp/ubuntu2604-httpd-pid.$$"
cleanup() {
  # best-effort; never touch other guests. Kill the HTTP server we started
  # (by PID file first, then pattern fallback), remove the transient domain,
  # and wipe scratch files.
  tower "kill \$(cat '$KS_HTTPD_PID_FILE' 2>/dev/null) 2>/dev/null; pkill -f 'httpd.*ubuntu2604' 2>/dev/null; pkill -f 'http.server.*$KS_PORT' 2>/dev/null; pkill -f 'HTTP::Daemon' 2>/dev/null; sudo virsh destroy '$TRANSIENT' 2>/dev/null; sudo virsh undefine '$TRANSIENT' 2>/dev/null; rm -rf '$KS_DIR' '$DOMAIN_DIR/install-media' '$KS_HTTPD_PID_FILE' /tmp/ubuntu2604-console.tcl" \
    >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ------------------------------------------------------------- pre-state ----
tower "hostname; whoami; date -u" | tee "$OUT_DIR/identity.txt" || die "cannot reach tower"

# Verify the guest domain exists (created by inventory or a prior run)
if ! tower "sudo virsh dumpxml '$GUEST' 2>/dev/null" >/dev/null 2>&1; then
  STATE=""
  log "persistent guest $GUEST: not yet defined"
else
  STATE="$(tower "sudo virsh domstate '$GUEST' 2>/dev/null")"
  log "persistent guest state: ${STATE:-unknown}"
fi
{ echo "pre-state: ${STATE:-not-defined}"; tower "sudo virsh dumpxml '$GUEST' 2>/dev/null"; } > "$OUT_DIR/pre-state.txt" || die "dumpxml failed"

# If the persistent guest is running, destroy it so the transient install
# domain can take write access to the qcow2 disk. A running guest holds a
# shared write lock (or "write" exclusive lock) on the qcow2 file that
# prevents the transient domain from attaching the same disk (see prior
# failure: "Failed to get write lock" at job 47888). The persistent guest's
# XML is never edited — it is re-defined (if needed) and re-started from
# the installed disk after the autoinstall completes (see the persistent
# domain boot section near the end of this script).
if [ "${STATE:-}" = "running" ] || [ "${STATE:-}" = "paused" ] || [ "${STATE:-}" = "idle" ]; then
  log "persistent guest is ${STATE} - destroying before transient install"
  tower "sudo virsh destroy '$GUEST'" || die "destroy persistent guest failed"
  # Wait for it to fully shut off and release the qcow2 lock
  for _ in $(seq 1 12); do
    S="$(tower "sudo virsh domstate '$GUEST' 2>/dev/null || true")"
    [ "$S" = "shut off" ] && break
    sleep 5
  done
  [ "$(tower "sudo virsh domstate '$GUEST' 2>/dev/null || true")" = "shut off" ] || die "persistent guest did not shut off in 60s"
  log "persistent guest destroyed; state: $(tower "sudo virsh domstate '$GUEST'")"
fi

# transient domain must not exist
if tower "sudo virsh domstate '$TRANSIENT'" >/dev/null 2>&1; then
  log "removing stale transient domain $TRANSIENT"
  tower "sudo virsh destroy '$TRANSIENT'" >/dev/null 2>&1 || true
  tower "sudo virsh undefine '$TRANSIENT'" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------- disk preflight/create --
log "domain dir contents before any change:"
tower "ls -la '$DOMAIN_DIR/' 2>/dev/null || echo '(domain dir absent)'" | tee "$OUT_DIR/disk-preflight.txt"

# search for any ubuntu2604 disk that may live elsewhere (record only)
tower "find /mnt/pool_one /mnt/pool_two /mnt/user -maxdepth 3 -iname '*ubuntu*26*' 2>/dev/null; true" \
  | tee -a "$OUT_DIR/disk-preflight.txt"

if tower "test -s '$DISK_PATH'"; then
  log "disk exists"
  tower "sudo qemu-img info '$DISK_PATH'" | tee -a "$OUT_DIR/disk-preflight.txt"
else
  # Create the domain dir + fresh qcow2 if absent (authorized by issue #20).
  log "disk $DISK_PATH ABSENT - creating domain dir + fresh qcow2 ($DISK_SIZE, sparse; authorized by issue scope)"
  tower "mkdir -p '$DOMAIN_DIR' && sudo qemu-img create -f qcow2 '$DISK_PATH' '$DISK_SIZE'" \
    | tee -a "$OUT_DIR/disk-preflight.txt" || die "qemu-img create failed"
  tower "sudo qemu-img info '$DISK_PATH'" | tee -a "$OUT_DIR/disk-preflight.txt"
fi

# ------------------------------------------------- kernel/initrd extraction --
# Ubuntu 26.04 live ISO: the kernel/initrd live at /casper/vmlinuz and
# /casper/initrd (the live-server / casper layout, same as the desktop ISO).
log "extracting kernel/initrd from the Ubuntu 26.04 live ISO (bsdtar, no loop mounts)"
tower "command -v bsdtar; ls -la '$ISO_PATH'" | tee "$OUT_DIR/iso-extract.log"

tower "rm -rf '$DOMAIN_DIR/install-media'; mkdir -p '$DOMAIN_DIR/install-media' && \\
       cd '$DOMAIN_DIR/install-media' && \\
       bsdtar -xf '$ISO_PATH' casper/vmlinuz casper/initrd && \\
       mv casper/vmlinuz . && mv casper/initrd . && rmdir casper && ls -la" \
  | tee -a "$OUT_DIR/iso-extract.log"
tower "test -s '$DOMAIN_DIR/install-media/vmlinuz' && test -s '$DOMAIN_DIR/install-media/initrd' && echo KERNEL-OK" \
  | tee -a "$OUT_DIR/iso-extract.log" || die "kernel/initrd extraction failed"

# ------------------------------------------------------- autoinstall serving --
# Derive the workforce public key from the runner's private key (ssh-keygen -y).
# This is the only way to guarantee the key matches what the CI VM stages use.
log "building autoinstall user-data with workforce key injected"
KEYSRC=""
if [ -r /root/.ssh/id_ed25519.pub ]; then KEYSRC=/root/.ssh/id_ed25519.pub
elif [ -r /root/.ssh/id_ed25519 ]; then
  ssh-keygen -y -f /root/.ssh/id_ed25519 > "$OUT_DIR/hermes-key.pub" && KEYSRC="$OUT_DIR/hermes-key.pub"
fi
[ -n "$KEYSRC" ] || die "no Hermes key material at /root/.ssh/id_ed25519(.pub) (SSH_PRIVATE_KEY_B64 absent; cannot authorize a key the runner can offer)"
log "hermes key: $(ssh-keygen -lf "$KEYSRC" | awk '{print $1, $2}')"

# Derive the public half from the private key to guarantee correctness
ssh-keygen -y -f /root/.ssh/id_ed25519 > "$OUT_DIR/hermes-key-derived.pub" \
  || die "cannot derive public half of the workforce key"
cmp -s "$OUT_DIR/hermes-key-derived.pub" "$KEYSRC" \
  || log "WARN: /root/.ssh/id_ed25519.pub differs from key derived from id_ed25519 - using derived key"

# Build the autoinstall user-data: read the template and inject the workforce
# public key into the identity.ssh_key field (replacing the empty placeholder).
AUTOINSTALL_LOCAL="$OUT_DIR/user-data"
awk -v key="$(cat "$OUT_DIR/hermes-key-derived.pub")" \
  '{ gsub(/ssh_key: ""/, "ssh_key: \"" key "\""); print }' \
  "$HERE/ubuntu-26.04-preseed.cfg" > "$AUTOINSTALL_LOCAL"
grep -q 'ssh_key:' "$AUTOINSTALL_LOCAL" || die "failed to inject hermes key into autoinstall user-data"

# Stage the seed files on tower. NoCloud-net requires BOTH user-data and a
# meta-data file under the seed directory (instance-id can be minimal but the
# file must exist or cloud-init logs a datasource error; prior runs that
# served only user-data never activated Subiquity).
META_LOCAL="$OUT_DIR/meta-data"
printf 'instance-id: ubuntu2604-autoinstall\nlocal-hostname: ubuntu2604\n' > "$META_LOCAL"
tower "mkdir -p '$KS_DIR' && chmod 755 '$KS_DIR'" || die "KS dir creation failed"
scp $SSH_OPTS "$AUTOINSTALL_LOCAL" "$TOWER_HOST:/tmp/ubuntu2604-user-data" >/dev/null 2>&1 || die "autoinstall upload failed"
scp $SSH_OPTS "$META_LOCAL" "$TOWER_HOST:/tmp/ubuntu2604-meta-data" >/dev/null 2>&1 || die "meta-data upload failed"
tower "mv /tmp/ubuntu2604-user-data '$KS_DIR/user-data' && mv /tmp/ubuntu2604-meta-data '$KS_DIR/meta-data' && chmod 644 '$KS_DIR/user-data' '$KS_DIR/meta-data'" \
  || die "autoinstall staging failed"

# Serve the autoinstall user-data over HTTP from the tower. The Unraid tower
# does not expose busybox on the SSH login PATH (provision job 40712: FATAL
# no busybox httpd found on tower), so probe for an HTTP-capable binary in a
# resilient order — same 3-tier fallback as the el10 harness fix (MR !16,
# issue #25) for the identical failure:
#   1. busybox httpd          (Unraid 6.x /usr/bin/busybox — not on SSH PATH)
#   2. python3 -m http.server  (Unraid 6.12+ /usr/bin/python3)
#   3. perl (core IO::Socket::INET + Fcntl) — works with NO non-core modules
# The KS_HTTPD_PID_FILE lets the cleanup trap kill whichever server started.
log "locating an HTTP server on tower for autoinstall serving"
KS_SERVER=""
BB="$(tower "command -v busybox 2>/dev/null; ls /usr/bin/busybox /usr/sbin/busybox /bin/busybox 2>/dev/null | head -1; true")"
BB="$(printf '%s\n' "$BB" | sed '/^$/d' | head -1)"
if [ -n "$BB" ]; then
  KS_SERVER="busybox"
  echo "busybox: $BB" | tee "$OUT_DIR/httpd.log"
else
  PY3="$(tower "command -v python3 2>/dev/null; ls /usr/bin/python3 /usr/local/bin/python3 2>/dev/null | head -1; true")"
  PY3="$(printf '%s\n' "$PY3" | sed '/^$/d' | head -1)"
  if [ -n "$PY3" ]; then
    KS_SERVER="python3"
    echo "python3: $PY3" | tee "$OUT_DIR/httpd.log"
  else
    PERL_BIN="$(tower "command -v perl 2>/dev/null; ls /usr/bin/perl /usr/local/bin/perl 2>/dev/null | head -1; true")"
    PERL_BIN="$(printf '%s\n' "$PERL_BIN" | sed '/^$/d' | head -1)"
    if [ -n "$PERL_BIN" ]; then
      KS_SERVER="perl"
      echo "perl: $PERL_BIN" | tee "$OUT_DIR/httpd.log"
    fi
  fi
fi

if [ -z "$KS_SERVER" ]; then
  die "no HTTP server found on tower (tried busybox, python3, perl); cannot serve autoinstall"
fi

case "$KS_SERVER" in
  busybox)
    log "starting busybox httpd on tower port $KS_PORT"
    tower "nohup busybox httpd -f -v -p '$KS_PORT' -h '$KS_DIR' > /tmp/ubuntu2604-httpd.log 2>&1 & echo \$! > '$KS_HTTPD_PID_FILE'"
    ;;
  python3)
    log "starting python3 -m http.server on tower port $KS_PORT"
    tower "nohup python3 -m http.server --directory '$KS_DIR' '$KS_PORT' > /tmp/ubuntu2604-httpd.log 2>&1 & echo \$! > '$KS_HTTPD_PID_FILE'"
    ;;
  perl)
    log "starting perl HTTP server (core modules only) on tower port $KS_PORT"
    # HTTP::Daemon is NOT a Perl core module (it ships with libwww/LWP, which
    # is absent on the Unraid tower), so `-MHTTP::Daemon` silently dies and
    # the healthcheck fails with HTTPD-HEALTHCHECK-FAIL. Use a minimal
    # raw-HTTP server built only from Perl *core* modules (IO::Socket::INET +
    # Fcntl), staged to KS_DIR via heredoc to avoid ssh inline-quoting
    # problems. It serves only the single user-data file for any GET path.
    cat > "$OUT_DIR/perl-httpd.pl" <<PERL
use strict; use warnings;
use IO::Socket::INET;
use Fcntl;
my \$port = \$ARGV[0]; my \$dir = \$ARGV[1];
my \$s = IO::Socket::INET->new(
  LocalAddr => '0.0.0.0', LocalPort => \$port,
  ReuseAddr => 1, Listen => 5, Proto => 'tcp'
) or die "perl-httpd bind: \$!";
while (my \$c = \$s->accept()) {
  my \$path = '/';
  if (my \$l = <\$c>) {
    \$path = \$1 if \$l =~ m{^GET\s+(\S+)};
  }
  while (my \$l = <\$c>) { last if \$l =~ /^\s*\$/; }
  \$path =~ s{^/+}{};
  \$path =~ s{[^A-Za-z0-9._-]}{}g;
  \$path = 'user-data' if \$path eq '';
  my \$file = "\$dir/\$path";
  open(my \$fh, '<', \$file) or do {
    print \$c "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\nConnection: close\r\n\r\nnot found";
    close \$c; next;
  };
  binmode(\$fh);
  seek(\$fh, 0, Fcntl::SEEK_END); my \$n = tell(\$fh); seek(\$fh, 0, Fcntl::SEEK_SET);
  print \$c "HTTP/1.1 200 OK\r\nContent-Type: text/cloud-init\r\nContent-Length: \$n\r\nConnection: close\r\n\r\n";
  while (read(\$fh, my \$buf, 65536)) { print \$c \$buf; }
  close \$fh; close \$c;
}
PERL
    scp $SSH_OPTS "$OUT_DIR/perl-httpd.pl" "$TOWER_HOST:/tmp/ubuntu2604-perl-httpd.pl" >/dev/null 2>&1 || die "perl server staging failed"
    tower "mv /tmp/ubuntu2604-perl-httpd.pl '$KS_DIR/perl-httpd.pl' && chmod 644 '$KS_DIR/perl-httpd.pl'" || die "perl server staging failed"
    tower "nohup perl '$KS_DIR/perl-httpd.pl' '$KS_PORT' '$KS_DIR' > /tmp/ubuntu2604-httpd.log 2>&1 & echo \$! > '$KS_HTTPD_PID_FILE'"
    ;;
esac
sleep 3

# PROVE the seed files are actually fetchable on loopback and that meta-data
# (required by nocloud-net) is served too. A bare exit-0 from wget with an
# error page would otherwise pass silently. wget first, curl fallback.
tower "(wget -q -O- 'http://127.0.0.1:$KS_PORT/user-data' 2>/dev/null || curl -s 'http://127.0.0.1:$KS_PORT/user-data' 2>/dev/null) | head -1 | grep -q 'cloud-config' && echo HTTPD-OK || { echo 'HTTPD-HEALTHCHECK-FAIL'; exit 1; }" \
  | tee -a "$OUT_DIR/httpd.log" || die "autoinstall user-data not fetchable on tower loopback (HTTP server did not bind or crashed)"
tower "(wget -q -O- 'http://127.0.0.1:$KS_PORT/meta-data' 2>/dev/null || curl -s 'http://127.0.0.1:$KS_PORT/meta-data' 2>/dev/null) | head -1 | grep -q 'instance-id' && echo META-OK || { echo 'META-HEALTHCHECK-FAIL'; exit 1; }" \
  | tee -a "$OUT_DIR/httpd.log" || die "meta-data not fetchable on tower loopback"

# ------------------------------------------------------- transient domain ----
# Ubuntu 26.04 live-server install via direct kernel boot with Subiquity
# autoinstall. The transient domain reuses ONLY the persistent guest's
# qcow2 disk + br0 NIC; the persistent domain XML is never edited.
log "defining transient install domain $TRANSIENT"
cat > "$OUT_DIR/transient.xml" <<XML
<domain type='kvm'>
  <name>$TRANSIENT</name>
  <description>transient ubuntu2604 install session (issue #20)</description>
  <memory unit='MiB'>4096</memory>
  <currentMemory unit='MiB'>4096</currentMemory>
  <vcpu>2</vcpu>
  <os>
    <type arch='x86_64' machine='pc-q35-9.2'>hvm</type>
    <kernel>$DOMAIN_DIR/install-media/vmlinuz</kernel>
    <initrd>$DOMAIN_DIR/install-media/initrd</initrd>
    <cmdline>console=ttyS0,115200 net.ifnames=0 biosdevname=0 autoinstall "ds=nocloud-net;s=http://$TOWER_IP:$KS_PORT/" ip=${VM_IP}::192.168.1.1:255.255.255.0:ubuntu2604:eth0:none nameserver=192.168.1.1</cmdline>
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

# stop serving the autoinstall as soon as the console session ends
tower "kill \$(cat '$KS_HTTPD_PID_FILE' 2>/dev/null) 2>/dev/null; pkill -f 'httpd.*ubuntu2604' 2>/dev/null; pkill -f 'http.server.*$KS_PORT' 2>/dev/null; pkill -f 'HTTP::Daemon' 2>/dev/null" >/dev/null 2>&1 || true
tower "rm -f '$KS_HTTPD_PID_FILE'" >/dev/null 2>&1 || true

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
# disk + NIC facts. This is the one-time creation authorized by issue #20
# scope ("provision Ubuntu 26.04 ... to qcow2, attached to br0").
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

log "SSH probe from the runner (workforce key installed by autoinstall)"
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

echo "=== ubuntu2604 CI transport smoke (same transport as transfer/install stages) ==="
ssh $SSH_OPTS "root@$VM_IP" \
  "apt-cache policy openssh-server | head -3; dpkg -l qemu-guest-agent | tail -1" \
  | tee -a "$OUT_DIR/acceptance.txt" || true

log "=== provisioning complete ==="
exit 0
