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
# Registry fallback inputs (step 1b): the GitLab v4 API base for this project
# and the build-cache package-version prefix for this package type/target.
# Both derive from standard CI variables; no host is hardcoded.
API_BASE="${CI_API_V4_URL:?CI_API_V4_URL not set}/projects/${CI_PROJECT_ID:?CI_PROJECT_ID not set}"
PKG_PREFIX="${PKG_PREFIX:-deb-debian.12-}"

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
  # Same content-addressed key the build jobs use (scripts/ci/lib/). Run from
  # the source checkout: the key hashes git-tracked blobs via git ls-files.
  if [ -z "${BUILD_KEY:-}" ]; then
    BUILD_KEY="$(cd "$SRC_DIR" && bash scripts/ci/lib/compute-build-key.sh deb debian.12)"
  fi
  export BUILD_KEY
  export BUILD_PACKAGE_TYPE=deb BUILD_TARGET_LABEL=debian.12
  # shellcheck disable=SC1091
  REUSE_BUILD_ARTIFACTS=true bash "$SRC_DIR/scripts/ci/lib/build-artifact-cache.sh" restore \
    && PKG="$(ls -1 "$ARTIFACT_DIR"/*.deb 2>/dev/null | head -1)" \
    || echo "[vm-install] exact-key cache restore did not yield a package"
fi

# ── 1b. Fallback: newest deb-debian.12-* registry entry ───────────────────────
# The content-addressed key follows the live source tree, but package builds
# run only on release tags (.rules:build), so the freshest cached .deb usually
# predates any tree change and the exact key misses. When it does, fall back to
# the most recently created deb-debian.12-* generic package: it is the same
# verified artifact-cache archive (build-key + SHA256SUMS checked on restore),
# just addressed by its registry version instead of the current tree key.
if [ -z "$PKG" ]; then
  echo "[vm-install] exact key missed; querying registry for newest ${PKG_PREFIX}* ..."
  REGISTRY_LIST="${CACHE_LIST_DIR:-/tmp}/vm-install-registry.json"
  mkdir -p "$(dirname "$REGISTRY_LIST")"
  QUERY_OK=1
  LATEST_VERSION=""
  PAGE=1
  # The registry is server-side sorted by created_at desc; take the first
  # matching version. Page once more only if a page is exactly full.
  while [ -z "$LATEST_VERSION" ] && [ "$PAGE" -le 5 ]; do
    HTTP_STATUS="$(curl --silent --show-error \
        --output "$REGISTRY_LIST" --write-out '%{http_code}' \
        --header "JOB-TOKEN: ${CI_JOB_TOKEN:?CI_JOB_TOKEN not set}" \
        "$API_BASE/packages?package_type=generic&per_page=100&order_by=created_at&sort=desc&page=$PAGE")" \
      || HTTP_STATUS=""
    if [ "$HTTP_STATUS" != "200" ]; then
      QUERY_OK=0
      break
    fi
    LATEST_VERSION="$(grep -o '"version":"[^"]*"' "$REGISTRY_LIST" \
      | sed 's/"version":"//; s/"$//' \
      | grep "^$PKG_PREFIX" | head -1 || true)"
    # Stop paging when the page has fewer than 100 package entries (top-level
    # packages each carry exactly one "package_type":"generic" field).
    if [ "$(grep -c '"package_type":' "$REGISTRY_LIST")" -lt 100 ]; then
      break
    fi
    PAGE=$((PAGE + 1))
  done
  rm -f "$REGISTRY_LIST"
  if [ "$QUERY_OK" = "1" ]; then
    if [ -n "$LATEST_VERSION" ]; then
      export BUILD_KEY="$LATEST_VERSION"
      echo "[vm-install] falling back to newest registry cache entry: $LATEST_VERSION"
      # shellcheck disable=SC1091
      REUSE_BUILD_ARTIFACTS=true bash "$SRC_DIR/scripts/ci/lib/build-artifact-cache.sh" restore \
        && PKG="$(ls -1 "$ARTIFACT_DIR"/*.deb 2>/dev/null | head -1)" \
        || echo "[vm-install] registry-fallback restore did not yield a package"
    else
      echo "[vm-install] no ${PKG_PREFIX}* registry entries found"
    fi
  else
    echo "[vm-install] registry query failed (HTTP ${HTTP_STATUS:-none}); cannot fall back"
  fi
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
