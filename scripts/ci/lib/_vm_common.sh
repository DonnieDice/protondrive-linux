#!/usr/bin/env bash
# scripts/ci/lib/_vm_common.sh
#
# Transport layer + stage-runner helpers shared by all three VM pipeline stages:
#   transfer/  — locate artifact, SCP to VM, emit dotenv for install stage
#   install/   — run distro-specific package manager on the VM
#   vmtest/    — regression + GUI load tests on the VM
#
# Source this file; do not execute directly.
#
# SSH transport (either is sufficient; checked in this order):
#   1. VM_SSH_KEY   GitLab CI File/Variable-type private key authorized as
#                  VM_SSH_USER (default root) on every test VM.
#   2. Runner-mounted SSH dir: the unraid-docker runner bind-mounts its host
#       /mnt/user/appdata/gitlab-runner/ssh into the job container as
#       /root/.ssh:ro, whose config carries Host aliases (debian12,
#       debian13, …) with pinned user/identity. This is the same transport
#       the .vm_regression jobs already use (aliases resolve to the same
#       VMs as the raw IPs below). Jobs reach a VM either by its alias or
#       by IP; in mounted mode an IP is resolved to its alias first.
#
# Build artifacts are expected in ./artifacts/ (ARTIFACT_DIR).

VM_SSH_USER="${VM_SSH_USER:-root}"
ARTIFACT_DIR="${ARTIFACT_DIR:-artifacts}"

# ── IP → runner SSH-config alias map (mounted-mode transport) ────────────────
# Keys are the raw IPs CI jobs pass; values are Host aliases in the
# runner-mounted /root/.ssh/config. Unknown IPs fall back to user@ip with
# the mounted default identity.
_pd_alias_for_ip() {
  case "$1" in
    192.168.1.162) echo debian12 ;;
    192.168.1.120) echo debian13 ;;
    192.168.1.157) echo alpine320 ;;
    192.168.1.126) echo alpine322 ;;
    192.168.1.128) echo arch ;;
    192.168.1.219) echo ubuntu2404 ;;
    192.168.1.168) echo ubuntu2604 ;;
    192.168.1.31) echo tower ;;
    *) echo "" ;;
  esac
}

# ── SSH key bootstrap ─────────────────────────────────────────────────────────

_PD_KEYFILE=""
_PD_SSH_MODE="" # "key" (VM_SSH_KEY) | "mounted" (runner-mounted /root/.ssh)
_pd_ssh_init() {
  [ -n "$_PD_SSH_MODE" ] && return 0
  if [ -n "${VM_SSH_KEY:-}" ] && [ "${VM_SSH_KEY:-}" != "/root/.ssh/id_ed25519" ]; then
    _PD_KEYFILE="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '$_PD_KEYFILE'" EXIT
    if [ -f "$VM_SSH_KEY" ]; then
      cp "$VM_SSH_KEY" "$_PD_KEYFILE"
    else printf '%s' "$VM_SSH_KEY" >"$_PD_KEYFILE"; fi
    # Normalize: GitLab File vars commonly drop the trailing newline or add CRLF,
    # which makes OpenSSH reject the key with "error in libcrypto".
    sed -i 's/\r$//' "$_PD_KEYFILE"
    [ -n "$(tail -c1 "$_PD_KEYFILE" 2>/dev/null)" ] && printf '\n' >>"$_PD_KEYFILE"
    chmod 600 "$_PD_KEYFILE"
    if ! ssh-keygen -y -f "$_PD_KEYFILE" >/dev/null 2>&1; then
      echo "ERROR: VM_SSH_KEY did not parse as a valid private key." >&2
      echo "  Check: type=File, Protect=off, Expand=off, full BEGIN/END lines + trailing newline." >&2
      return 1
    fi
    _PD_SSH_MODE=key
    echo "SSH transport: VM_SSH_KEY (explicit key, user=$VM_SSH_USER)"
  elif [ -r /root/.ssh/config ] && [ -r /root/.ssh/id_ed25519 ]; then
    # Runner-mounted transport (see header). The per-host config pins
    # user/identity; BatchMode keeps failures immediate instead of prompting.
    _PD_SSH_MODE=mounted
    echo "SSH transport: runner-mounted /root/.ssh (VM_SSH_KEY not set)"
  else
    echo "ERROR: no SSH transport available." >&2
    echo "  Set the VM_SSH_KEY CI variable, or run on the unraid-docker runner" >&2
    echo "  that mounts /root/.ssh (see .gitlab-ci-vm-tests.yml header)." >&2
    return 1
  fi
}

# _pd_ssh_target <ip> — echo the ssh destination for the active transport.
_pd_ssh_target() {
  local ip="$1" alias
  if [ "$_PD_SSH_MODE" = key ]; then
    echo "$VM_SSH_USER@$ip"
  else
    alias="$(_pd_alias_for_ip "$ip")"
    if [ -n "$alias" ]; then
      echo "$alias"
    else echo "$VM_SSH_USER@$ip"; fi
  fi
}

# _pd_ssh_opts — echo transport-specific ssh options (use unquoted so the
# options word-split; _PD_KEYFILE comes from mktemp so it never has spaces).
_pd_ssh_opts() {
  if [ "$_PD_SSH_MODE" = key ]; then
    printf '%s\n' \
      -i "$_PD_KEYFILE" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15
  else
    printf '%s\n' -o BatchMode=yes -o ConnectTimeout=15
  fi
}

# ── Transport primitives ──────────────────────────────────────────────────────

# find_artifact <glob>  echoes the first matching path under ARTIFACT_DIR
find_artifact() {
  local glob="$1"
  _pd_ssh_init
  shopt -s nullglob
  local matches=($ARTIFACT_DIR/$glob)
  shopt -u nullglob
  if [ "${#matches[@]}" -lt 1 ]; then
    echo "ERROR: no artifact matched '$ARTIFACT_DIR/$glob'" >&2
    ls -la "$ARTIFACT_DIR" >&2 || true
    return 1
  fi
  echo "${matches[0]}"
}

# run_on_vm <ip> <command...>
run_on_vm() {
  local ip="$1"
  shift
  _pd_ssh_init
  # shellcheck disable=SC2046
  ssh $(_pd_ssh_opts) "$(_pd_ssh_target "$ip")" "$@"
}

# copy_to_vm <ip> <localfile>  SCPs file to /tmp/pd-deploy/ on VM; echoes remote path
copy_to_vm() {
  local ip="$1" file="$2" base
  base="$(basename "$file")"
  _pd_ssh_init
  run_on_vm "$ip" 'rm -rf /tmp/pd-deploy && mkdir -p /tmp/pd-deploy'
  # -O forces legacy SCP protocol (not SFTP subsystem) for compatibility with
  # openSUSE and other sshd configs that don't advertise the sftp subsystem.
  # shellcheck disable=SC2046
  if scp -O $(_pd_ssh_opts) \
    "$file" "$(_pd_ssh_target "$ip"):/tmp/pd-deploy/$base"; then
    echo "/tmp/pd-deploy/$base"
  else
    echo "ERROR: scp failed transferring $base to $ip" >&2
    return 1
  fi
}

# vm_reachable <ip>
vm_reachable() {
  local ip="$1"
  echo "--- checking $VM_SSH_USER@$ip ---"
  run_on_vm "$ip" 'echo connected; uname -a' ||
    {
      echo "ERROR: cannot SSH to $VM_SSH_USER@$ip" >&2
      return 1
    }
}

# ── Stage runners ─────────────────────────────────────────────────────────────

# transfer_run <label> <ip> <glob>
#   Stage 1: locate artifact + SCP to VM.
#   Emits transfer-results/<label>.json   (result record for report stage)
#         transfer-results/<label>.env    (dotenv passed to install stage via GitLab artifact)
transfer_run() {
  local label="$1" ip="$2" glob="$3"
  local rdir="transfer-results"
  mkdir -p "$rdir"
  local pkg="" base="" sha="" version="" remote=""
  local r_artifact=fail r_reach=fail r_transfer=fail status=FAIL
  echo "=== [transfer] $label -> $ip ==="

  set +e
  pkg="$(find_artifact "$glob")" && r_artifact=pass
  if [ "$r_artifact" = pass ]; then
    base="$(basename "$pkg")"
    sha="$(sha256sum "$pkg" 2>/dev/null | cut -d' ' -f1)"
    version="$(printf '%s' "$base" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    echo "artifact: $pkg  sha256=${sha:0:12}…"
    vm_reachable "$ip" && r_reach=pass
    if [ "$r_reach" = pass ]; then
      remote="$(copy_to_vm "$ip" "$pkg")" && r_transfer=pass
      echo "transferred to: $remote"
    fi
  fi
  set -e

  { [ "$r_artifact" = pass ] && [ "$r_reach" = pass ] && [ "$r_transfer" = pass ]; } && status=PASS

  # Dotenv consumed by the install stage job (artifacts: reports: dotenv:)
  cat >"$rdir/${label}.env" <<ENV
REMOTE_PKG_PATH=${remote}
PKG_SHA256=${sha}
PKG_VERSION=${version}
PKG_BASE=${base}
PD_VM_IP=${ip}
ENV

  cat >"$rdir/${label}.json" <<JSON
{"stage":"transfer","distro":"$label","vm_ip":"$ip","package":"$base","version":"$version","sha256":"$sha","artifact_found":"$r_artifact","reachable":"$r_reach","transferred":"$r_transfer","status":"$status","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","ci_commit":"${CI_COMMIT_SHORT_SHA:-local}","ci_pipeline":"${CI_PIPELINE_ID:-0}"}
JSON
  echo "=== $label transfer: $status (artifact=$r_artifact reach=$r_reach transfer=$r_transfer) ==="
  [ "$status" = PASS ]
}

# install_run <label> <ip> <remote-pkg-path> <install-fn>
#   Stage 2: run the distro-specific package manager on the VM.
#   Reads REMOTE_PKG_PATH injected by the transfer stage dotenv artifact.
#   Emits install-results/<label>.json
install_run() {
  local label="$1" ip="$2" remote="$3" install_fn="$4"
  local rdir="install-results"
  mkdir -p "$rdir"
  local r_install=fail status=FAIL
  echo "=== [install] $label on $ip : $remote ==="

  set +e
  "$install_fn" "$ip" "$remote" && r_install=pass
  set -e

  [ "$r_install" = pass ] && status=PASS
  cat >"$rdir/${label}.json" <<JSON
{"stage":"install","distro":"$label","vm_ip":"$ip","remote_pkg":"$remote","installed":"$r_install","status":"$status","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","ci_commit":"${CI_COMMIT_SHORT_SHA:-local}","ci_pipeline":"${CI_PIPELINE_ID:-0}"}
JSON
  echo "=== $label install: $status ==="
  [ "$status" = PASS ]
}

# test_run <label> <ip> <pkg-family>
#   Stage 3: regression checks + GUI load test on the VM.
#   Requires _test_common.sh to be sourced before calling (provides regression_checks,
#   gui_load_test, install_test_deps, test_summary and the _PD_TEST_* counters).
#   Emits test-results/<label>.json
test_run() {
  local label="$1" ip="$2" family="$3"
  local rdir="test-results"
  mkdir -p "$rdir"
  _PD_TEST_FAILS=0
  _PD_TEST_RUN=0
  echo "=== [vmtest] $label on $ip (family=$family) ==="

  install_test_deps "$ip" "$family"
  network_preflight_checks "$ip"
  regression_checks "$ip"

  # Per-distro hook — define distro_checks() in the vmtest/<distro>/test.sh script.
  # Called here so results are included in the same JSON record and test counters.
  if declare -f distro_checks >/dev/null 2>&1; then
    distro_checks "$ip"
  fi

  # gui_load_test: process + compositor window check (fast baseline)
  gui_load_test "$ip"

  # ui_compositor_test: full visual suite — screenshot + OCR + xdotool interaction.
  # smoke: login screen OCR, no crash dialog, Proton branding
  # ui:    form fields visible, sidebar hidden pre-login
  # sidebar/menus: skipped automatically if no credentials
  local ui_artifact_dir="${VERIFY_RESULTS_DIR:-verify-results}/ui-screenshots/${label}"
  ui_compositor_test "$ip" smoke "$ui_artifact_dir"
  ui_compositor_test "$ip" ui "$ui_artifact_dir"
  # Credential-gated suites — skip automatically if env vars absent
  require_proton_login_credentials
  ui_compositor_test "$ip" sidebar "$ui_artifact_dir"
  if [ "${RUN_VM_LOGIN_TESTS:-false}" = "true" ]; then
    ui_compositor_test "$ip" functional "$ui_artifact_dir"
  fi
  ui_compositor_test "$ip" menus "$ui_artifact_dir"

  local status=FAIL
  test_summary && status=PASS
  cat >"$rdir/${label}.json" <<JSON
{"stage":"vmtest","distro":"$label","vm_ip":"$ip","pkg_family":"$family","tests_run":$_PD_TEST_RUN,"tests_failed":$_PD_TEST_FAILS,"status":"$status","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","ci_commit":"${CI_COMMIT_SHORT_SHA:-local}","ci_pipeline":"${CI_PIPELINE_ID:-0}"}
JSON
  echo "=== $label vmtest: $status ($((_PD_TEST_RUN - _PD_TEST_FAILS))/$_PD_TEST_RUN passed) ==="
  [ "$status" = PASS ]
}
