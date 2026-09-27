#!/usr/bin/env bash
# scripts/ci/vmtest/pytest-unit.sh
#
# Runner-side harness (issue #15): execute the tests/unit/ pytest suite
# INSIDE a managed VM, over the runner-mounted SSH transport (ssh aliases from
# /root/.ssh, same as the vm:install/vm:regression jobs). Does not depend on
# the VM_SSH_KEY CI variable.
#
# Usage:   pytest-unit.sh <vm-alias>
# Env:     CI_PROJECT_DIR  repository checkout to transfer (default: cwd)
#          VM_KNOWN_HOSTS  known-hosts file (default: /dev/null, accept-new)
#
# Emits:   vm-pytest-results/pytest.xml   (junit report, fetched back to runner)
#          vm-pytest-results/context.txt (target/commit/python provenance)
set -uo pipefail

VM_HOST="${1:?usage: pytest-unit.sh <vm-alias>}"
SRC_DIR="${CI_PROJECT_DIR:-$(pwd)}"
WORK="/tmp/pd-pytest"
RESULTS_DIR="vm-pytest-results"
VM_KNOWN_HOSTS="${VM_KNOWN_HOSTS:-/dev/null}"

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10
  -o UserKnownHostsFile="$VM_KNOWN_HOSTS" -o StrictHostKeyChecking=accept-new)

vm_ssh() { ssh "${SSH_OPTS[@]}" "$VM_HOST" "$@"; }

mkdir -p "$RESULTS_DIR"
COMMIT="$(git -C "$SRC_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"

echo "=== [vm-pytest] target=$VM_HOST commit=$COMMIT ==="

# 1. Reachability + host identity evidence.
vm_ssh 'echo "connected: $(hostname) $(uname -rm) user=$(whoami)"'
HOST_LINE="$(vm_ssh 'echo "$(hostname) $(uname -rm)"')"

# 2. Provision python3/pip/venv on the VM (idempotent, non-fatal apt errors:
#    the VM may already be provisioned).
vm_ssh 'DEBIAN_FRONTEND=noninteractive apt-get update -qq || true
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
    python3 python3-pip python3-venv bash ca-certificates >/dev/null 2>&1 || true'

# 3. Transfer this repository checkout to the VM (tar over ssh, no .git/caches).
echo "=== [vm-pytest] transferring checkout to $VM_HOST:$WORK ==="
tar -C "$SRC_DIR" \
    --exclude=.git --exclude=.cargo --exclude=.cargo-fmt \
    --exclude='src-tauri/target' --exclude='WebClients' \
    --exclude='.build-artifact-cache' --exclude='artifacts' \
    -czf - . \
  | vm_ssh "rm -rf '$WORK' && mkdir -p '$WORK' && tar -xzf - -C '$WORK'"

# 4. Provision the test environment and run the suite INSIDE the VM.
#    Primary: venv + pinned tests/requirements.txt. Fallback (no PyPI access
#    from the VM): distro python3-pytest + python3-yaml.
echo "=== [vm-pytest] provisioning python test env on $VM_HOST ==="
vm_ssh "WORK='$WORK' bash -s" <<'REMOTE'
set -e
cd "$WORK"
echo "python: $(python3 --version 2>&1)"
PY=python3
if python3 -m venv venv 2>/dev/null && [ -x venv/bin/python ]; then
  if venv/bin/pip install --disable-pip-version-check --quiet \
       -r tests/requirements.txt; then
    PY="$WORK/venv/bin/python"
    echo "[vm-pytest] venv provisioning OK (pinned tests/requirements.txt)"
  else
    echo "[vm-pytest] WARNING: venv pip install failed (PyPI unreachable?); falling back to distro pytest"
  fi
else
  echo "[vm-pytest] WARNING: python3-venv unavailable; falling back to distro pytest"
fi
if [ "$PY" = "python3" ]; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
    python3-pytest python3-yaml >/dev/null 2>&1 \
    || echo "[vm-pytest] WARNING: distro pytest install failed"
fi
echo "=== [vm-pytest] running: $PY -m pytest tests/unit/ ==="
"$PY" -m pytest tests/unit/ -q --no-header --junitxml="$WORK/pytest.xml"
REMOTE

# 5. Fetch the junit report back to the runner as a CI artifact.
echo "=== [vm-pytest] fetching junit report ==="
scp -O "${SSH_OPTS[@]}" "$VM_HOST:$WORK/pytest.xml" "$RESULTS_DIR/pytest.xml"

{
  echo "vm_host=$VM_HOST"
  echo "host_line=$HOST_LINE"
  echo "commit=$COMMIT"
  vm_ssh 'python3 --version 2>&1'
} > "$RESULTS_DIR/context.txt"

echo "=== [vm-pytest] completed: $RESULTS_DIR/pytest.xml ==="
