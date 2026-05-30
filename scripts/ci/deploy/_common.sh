#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/ci/deploy/_common.sh
#
# Shared helpers for the per-distro deploy scripts (scripts/ci/deploy/<distro>/
# deploy.sh). Each distro script sources this, sets VM_IP + PKG_GLOB, and
# implements its own install step (distro-specific quirks live in the per-distro
# script, not here). Mirrors the patches/<type>/<distro> layout.
#
# REQUIRED ENV (GitLab CI variables):
#   VM_SSH_KEY   private key authorized as root on every test VM (File-type var)
#   VM_SSH_USER  login user (default: root)
#
# Artifacts are expected in ./artifacts/ (the build job's output).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

VM_SSH_USER="${VM_SSH_USER:-root}"
ARTIFACT_DIR="${ARTIFACT_DIR:-artifacts}"

# Lazily-initialised SSH key file + option arrays.
_PD_KEYFILE=""
_pd_ssh_init() {
  [ -n "$_PD_KEYFILE" ] && return 0
  _PD_KEYFILE="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$_PD_KEYFILE'" EXIT
  if [ -f "${VM_SSH_KEY:-}" ]; then cp "$VM_SSH_KEY" "$_PD_KEYFILE"
  else printf '%s' "${VM_SSH_KEY:?VM_SSH_KEY not set}" >"$_PD_KEYFILE"; fi
  # Normalize: GitLab CI variables commonly drop the trailing newline or add
  # CRLF, which makes OpenSSH reject the key ("error in libcrypto"). Strip CR
  # and guarantee a final newline.
  sed -i 's/\r$//' "$_PD_KEYFILE"
  [ -n "$(tail -c1 "$_PD_KEYFILE" 2>/dev/null)" ] && printf '\n' >>"$_PD_KEYFILE"
  chmod 600 "$_PD_KEYFILE"
  # Fail fast with an actionable message if it still won't parse.
  if ! ssh-keygen -y -f "$_PD_KEYFILE" >/dev/null 2>&1; then
    echo "ERROR: VM_SSH_KEY did not parse as a valid private key." >&2
    echo "  Check the CI variable: type=File, Protect=off, Expand=off, and that" >&2
    echo "  the pasted key includes the full BEGIN/END lines + a trailing newline." >&2
    return 1
  fi
}

# find_artifact <glob> -> echoes the first matching package path (errors if none)
find_artifact() {
  local glob="$1"
  _pd_ssh_init
  shopt -s nullglob
  local matches=( $ARTIFACT_DIR/$glob )
  shopt -u nullglob
  if [ "${#matches[@]}" -lt 1 ]; then
    echo "ERROR: no artifact matched '$ARTIFACT_DIR/$glob'" >&2
    ls -la "$ARTIFACT_DIR" >&2 || true
    return 1
  fi
  echo "${matches[0]}"
}

# run_on_vm <ip> <command...>   run a command on the VM as root
run_on_vm() {
  local ip="$1"; shift
  _pd_ssh_init
  ssh -i "$_PD_KEYFILE" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
      "$VM_SSH_USER@$ip" "$@"
}

# copy_to_vm <ip> <localfile>   scp a file to /tmp/pd-deploy/ on the VM, echoes remote path
copy_to_vm() {
  local ip="$1" file="$2" base; base="$(basename "$file")"
  _pd_ssh_init
  run_on_vm "$ip" 'rm -rf /tmp/pd-deploy && mkdir -p /tmp/pd-deploy'
  scp -i "$_PD_KEYFILE" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
      "$file" "$VM_SSH_USER@$ip:/tmp/pd-deploy/$base"
  echo "/tmp/pd-deploy/$base"
}

# vm_reachable <ip>   fail loudly if the VM can't be reached
vm_reachable() {
  local ip="$1"
  echo "--- checking $VM_SSH_USER@$ip is reachable ---"
  run_on_vm "$ip" 'echo connected; uname -a' \
    || { echo "ERROR: cannot SSH to $VM_SSH_USER@$ip" >&2; return 1; }
}

# smoke_test <ip>   confirm the proton-drive binary is installed and runs
# (GUI/Tauri app: run under xvfb if present; a clean --version/--help = pass)
smoke_test() {
  local ip="$1"
  echo "--- smoke test on $ip ---"
  run_on_vm "$ip" 'set -e
    BIN=$(command -v proton-drive || echo /usr/bin/proton-drive)
    [ -x "$BIN" ] || { echo "FAIL: proton-drive not found/executable"; exit 1; }
    echo "installed at: $BIN"
    if command -v xvfb-run >/dev/null 2>&1; then
      xvfb-run -a "$BIN" --version 2>&1 | head -3 || xvfb-run -a "$BIN" --help 2>&1 | head -3 || true
    else
      "$BIN" --version 2>&1 | head -3 || "$BIN" --help 2>&1 | head -3 || true
    fi
    echo "SMOKE_TEST_PASS"'
}

# deploy_run <distro-label> <ip> <glob> <install-fn>
# Orchestrates: locate artifact -> reachability -> copy -> install (callback) -> smoke test.
deploy_run() {
  local label="$1" ip="$2" glob="$3" install_fn="$4"
  echo "=== deploy+test: $label -> $ip ==="
  local pkg remote
  pkg="$(find_artifact "$glob")"; echo "artifact: $pkg"
  vm_reachable "$ip"
  remote="$(copy_to_vm "$ip" "$pkg")"
  echo "--- installing on $ip ---"
  "$install_fn" "$ip" "$remote"
  smoke_test "$ip"
  echo "=== $label: install + smoke test PASSED on $ip ==="
}
