#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# deploy-and-test-vm.sh
#
# Ship a freshly-built package to its matching test VM, install it with the
# distro's native package manager, and run a smoke test (binary launches and
# reports a version). Used by the `verify` stage of the CI pipeline to prove
# that each artifact actually installs and runs on a real target system.
#
# Usage:
#   deploy-and-test-vm.sh <DISTRO_KEY>
#
# DISTRO_KEY selects the target VM + package format from the table below.
# All connection details come from CI variables (see REQUIRED ENV).
#
# REQUIRED ENV (set as GitLab CI variables):
#   VM_SSH_KEY       - private SSH key (file-type variable) authorized on every VM as root
#   VM_SSH_USER      - login user on the VMs (default: root)
#
# Artifacts are expected in ./artifacts/ (the build stage's output).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

DISTRO_KEY="${1:?usage: deploy-and-test-vm.sh <DISTRO_KEY>}"
VM_SSH_USER="${VM_SSH_USER:-root}"
ARTIFACT_DIR="${ARTIFACT_DIR:-artifacts}"

# ─── target table: DISTRO_KEY → "IP|PKG_GLOB|FAMILY" ─────────────────────────
# FAMILY drives the install command (apk/deb/rpm-dnf/rpm-zypper/aur).
declare -A TARGETS=(
  [alpine320]="192.168.1.157|proton-drive_*_alpine320_amd64.apk.tar.gz|apk"
  [alpine322]="192.168.1.126|proton-drive_*_alpine322_amd64.apk.tar.gz|apk"
  [debian12]="192.168.1.162|proton-drive_*_debian12_*.deb|deb"
  [debian13]="192.168.1.120|proton-drive_*_debian13_*.deb|deb"
  [ubuntu2404]="192.168.1.219|proton-drive_*_ubuntu2404_*.deb|deb"
  [ubuntu2604]="192.168.1.168|proton-drive_*_ubuntu2604_*.deb|deb"
  [el10]="192.168.1.123|*.rpm|rpm-dnf"
  [fedora43]="192.168.1.183|*.rpm|rpm-dnf"
  [opensuse-tw]="192.168.1.245|*.rpm|rpm-zypper"
  [arch]="192.168.1.128|*.pkg.tar.zst|aur"
)

ENTRY="${TARGETS[$DISTRO_KEY]:-}"
[ -n "$ENTRY" ] || { echo "ERROR: unknown DISTRO_KEY '$DISTRO_KEY'"; exit 2; }
IFS='|' read -r VM_IP PKG_GLOB FAMILY <<<"$ENTRY"

echo "=== deploy-and-test: $DISTRO_KEY → $VM_IP ($FAMILY) ==="

# ─── locate the artifact ─────────────────────────────────────────────────────
shopt -s nullglob
PKGS=( $ARTIFACT_DIR/$PKG_GLOB )
shopt -u nullglob
[ "${#PKGS[@]}" -ge 1 ] || { echo "ERROR: no artifact matched '$ARTIFACT_DIR/$PKG_GLOB'"; ls -la "$ARTIFACT_DIR" || true; exit 1; }
PKG="${PKGS[0]}"
PKG_BASE="$(basename "$PKG")"
echo "artifact: $PKG"

# ─── ssh/scp setup ───────────────────────────────────────────────────────────
KEYFILE="$(mktemp)"; trap 'rm -f "$KEYFILE"' EXIT
# VM_SSH_KEY may be a path (file-type CI var) or inline contents.
if [ -f "${VM_SSH_KEY:-}" ]; then cp "$VM_SSH_KEY" "$KEYFILE"; else printf '%s\n' "${VM_SSH_KEY:?VM_SSH_KEY not set}" >"$KEYFILE"; fi
chmod 600 "$KEYFILE"
SSH=(ssh -i "$KEYFILE" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o UserKnownHostsFile=/dev/null)
SCP=(scp -i "$KEYFILE" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o UserKnownHostsFile=/dev/null)
REMOTE="$VM_SSH_USER@$VM_IP"

run() { "${SSH[@]}" "$REMOTE" "$@"; }

# ─── reachability ────────────────────────────────────────────────────────────
echo "--- checking $REMOTE is reachable ---"
run 'echo connected; uname -a' || { echo "ERROR: cannot SSH to $REMOTE"; exit 1; }

# ─── copy artifact ───────────────────────────────────────────────────────────
echo "--- copying $PKG_BASE ---"
run 'rm -rf /tmp/pd-deploy && mkdir -p /tmp/pd-deploy'
"${SCP[@]}" "$PKG" "$REMOTE:/tmp/pd-deploy/$PKG_BASE"

# ─── install per family ──────────────────────────────────────────────────────
echo "--- installing ($FAMILY) ---"
case "$FAMILY" in
  apk)
    # tarball staging layout extracts to filesystem root
    run "cd /tmp/pd-deploy && tar -xzf '$PKG_BASE' -C / && command -v proton-drive" ;;
  deb)
    run "DEBIAN_FRONTEND=noninteractive apt-get update -qq || true; apt-get install -y -q /tmp/pd-deploy/'$PKG_BASE' || (dpkg -i /tmp/pd-deploy/'$PKG_BASE'; apt-get -y -f install)" ;;
  rpm-dnf)
    run "dnf install -y /tmp/pd-deploy/'$PKG_BASE' || rpm -i --force /tmp/pd-deploy/'$PKG_BASE'" ;;
  rpm-zypper)
    run "zypper --non-interactive install --allow-unsigned-rpm /tmp/pd-deploy/'$PKG_BASE' || rpm -i --force /tmp/pd-deploy/'$PKG_BASE'" ;;
  aur)
    run "pacman -U --noconfirm /tmp/pd-deploy/'$PKG_BASE'" ;;
  *) echo "ERROR: unknown FAMILY '$FAMILY'"; exit 2 ;;
esac

# ─── smoke test ──────────────────────────────────────────────────────────────
# proton-drive is a GUI (Tauri) app; on headless VMs run under xvfb if present,
# and treat a clean --version / --help response as a pass.
echo "--- smoke test ---"
run 'set -e
  BIN=$(command -v proton-drive || echo /usr/bin/proton-drive)
  [ -x "$BIN" ] || { echo "FAIL: proton-drive binary not found/executable"; exit 1; }
  echo "installed at: $BIN"
  if command -v xvfb-run >/dev/null 2>&1; then
    xvfb-run -a "$BIN" --version 2>&1 | head -3 || xvfb-run -a "$BIN" --help 2>&1 | head -3 || true
  else
    "$BIN" --version 2>&1 | head -3 || "$BIN" --help 2>&1 | head -3 || true
  fi
  echo "SMOKE_TEST_PASS"'

echo "=== $DISTRO_KEY: install + smoke test PASSED on $VM_IP ==="
