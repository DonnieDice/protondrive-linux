#!/usr/bin/env bash
# scripts/ci/vm-provision/install-pkg.sh
#
# Runner-side harness (issue #15): install the proton-drive package on a
# managed VM over the runner-mounted SSH transport (ssh aliases from
# /root/.ssh — same transport as the vm:install/vm:regression jobs; no
# dependency on the never-configured VM_SSH_KEY CI variable).
#
# Reuses the last known-good build artifact either from a prior pipeline job
# artifact (artifacts/) or from the content-addressed Generic Package
# Registry cache (proton-drive-build-cache), so a 2h rebuild is not required
# to produce install evidence.
#
# Usage:   install-pkg.sh <vm-alias> <pkg-type: deb>
# Env:     CI_PROJECT_DIR  repository checkout (default: cwd)
#          BUILD_KEY       cache key override
#          FORCE_REBUILD   bypass artifact reuse (not used by this script)
# Emits:   vm-install-results/<alias>.txt  (dpkg/version transcript evidence)
set -euo pipefail

VM_HOST="${1:?usage: install-pkg.sh <vm-alias> <deb>}"
PKG_TYPE="${2:-deb}"
SRC_DIR="${CI_PROJECT_DIR:-$(pwd)}"
ARTIFACT_DIR="${ARTIFACT_DIR:-artifacts}"
RESULTS_DIR="vm-install-results"
VM_KNOWN_HOSTS="${VM_KNOWN_HOSTS:-/dev/null}"

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10
  -o UserKnownHostsFile="$VM_KNOWN_HOSTS" -o StrictHostKeyChecking=accept-new)

vm_ssh() { ssh "${SSH_OPTS[@]}" "$VM_HOST" "$@"; }
vm_scp() { scp -O "${SSH_OPTS[@]}" "$@"; }

mkdir -p "$RESULTS_DIR"
RESULT="$RESULTS_DIR/$VM_HOST.txt"

# ── 1. Locate the .deb: prior job artifact, else package-registry cache ──────
PKG=""
if compgen -G "$ARTIFACT_DIR/*.deb" >/dev/null; then
  PKG="$(ls -1 "$ARTIFACT_DIR"/*.deb | head -1)"
  echo "[vm-install] using job artifact: $PKG"
else
  echo "[vm-install] no artifacts/ .deb; restoring from build cache..."
  # Same content-addressed key the build jobs use (scripts/ci/lib/).
  if [ -z "${BUILD_KEY:-}" ]; then
    BUILD_KEY="$(bash "$SRC_DIR/scripts/ci/lib/compute-build-key.sh" deb debian.12)"
  fi
  export BUILD_KEY
  export BUILD_PACKAGE_TYPE=deb BUILD_TARGET_LABEL=debian.12
  # shellcheck disable=SC1091
  REUSE_BUILD_ARTIFACTS=true bash "$SRC_DIR/scripts/ci/lib/build-artifact-cache.sh" restore \
    && PKG="$(ls -1 "$ARTIFACT_DIR"/*.deb 2>/dev/null | head -1)" \
    || echo "[vm-install] cache restore did not yield a package"
fi
[ -n "$PKG" ] || { echo "ERROR: no .deb found in $ARTIFACT_DIR or cache" >&2; exit 1; }
PKG_NAME="$(basename "$PKG")"
echo "[vm-install] package: $PKG_NAME sha256=$(sha256sum "$PKG" | cut -c1-12)..."

# ── 2. Reachability + current install state ──────────────────────────────────
{
  echo "=== [vm-install] target: $VM_HOST ==="
  echo "connected: $(vm_ssh 'echo "$(hostname) $(uname -rm) user=$(whoami)"')"
} | tee -a "$RESULT"
vm_ssh 'dpkg -l proton-drive 2>/dev/null | grep "^ii" && echo "pre-state: installed" || echo "pre-state: not installed"' | tee -a "$RESULT" || true

# ── 3. Transfer + install on the VM ──────────────────────────────────────────
echo "=== [vm-install] transferring $PKG_NAME to $VM_HOST ===" | tee -a "$RESULT"
vm_scp "$PKG" "$VM_HOST:/tmp/$PKG_NAME"
vm_ssh "DEBIAN_FRONTEND=noninteractive apt-get update -qq || true
  apt-get install -y -q /tmp/$PKG_NAME 2>/dev/null || { dpkg -i /tmp/$PKG_NAME; apt-get -y -f install; }" | tee -a "$RESULT"

# ── 4. Package-manager evidence: dpkg status + version output ─────────────────
{
  vm_ssh 'dpkg -l proton-drive 2>/dev/null | grep -E "^(ii|hi)" || true'
  vm_ssh 'proton-drive --version 2>/dev/null || echo "(no --version output)"'
} | tee -a "$RESULT"

if vm_ssh 'dpkg -l proton-drive 2>/dev/null | grep -q "^ii"'; then
  echo "=== [vm-install] $VM_HOST: proton-drive installed ===" | tee -a "$RESULT"
else
  echo "ERROR: proton-drive not in dpkg ii state on $VM_HOST" >&2
  exit 1
fi
