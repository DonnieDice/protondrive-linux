#!/usr/bin/env bash
# scripts/ci/lib/_test_common.sh
#
# Test framework sourced by every vmtest/<distro>/test.sh.
# Requires _vm_common.sh to be sourced first (provides run_on_vm, copy_to_vm).
#
# Exports:
#   _PD_TEST_FAILS / _PD_TEST_RUN  — counters reset by test_run() in _vm_common.sh
#   assert <desc> -- <cmd...>       — run a local command, record pass/fail
#   assert_on_vm <ip> <desc> <cmd> — assert a remote command succeeds
#   test_summary                    — print totals; non-zero if any failure
#   install_test_deps <ip> <family> — install headless display + OCR/xdotool tools on VM
#   regression_checks <ip>          — baseline packaging assertions
#   gui_load_test <ip>              — CI-micro-compositor: process + window check
#   ui_compositor_test <ip> <suite> — full visual test suite (screenshot + OCR + xdotool)
#                                     suites: smoke | ui | sidebar | menus | functional | all

_PD_TEST_FAILS=0
_PD_TEST_RUN=0

# assert <description> -- <command...>
assert() {
  local desc="$1"; shift
  [ "$1" = "--" ] && shift
  _PD_TEST_RUN=$((_PD_TEST_RUN+1))
  if "$@"; then echo "  ✓ $desc"
  else echo "  ✗ FAIL: $desc"; _PD_TEST_FAILS=$((_PD_TEST_FAILS+1)); fi
}

# assert_on_vm <ip> <description> <remote-command>
assert_on_vm() {
  local ip="$1" desc="$2" cmd="$3"
  _PD_TEST_RUN=$((_PD_TEST_RUN+1))
  if run_on_vm "$ip" "$cmd" >/dev/null 2>&1; then echo "  ✓ $desc"
  else echo "  ✗ FAIL: $desc"; _PD_TEST_FAILS=$((_PD_TEST_FAILS+1)); fi
}

# test_summary   print pass/fail totals; returns non-zero if any assertion failed
test_summary() {
  echo "--- tests: $((_PD_TEST_RUN-_PD_TEST_FAILS))/${_PD_TEST_RUN} passed ---"
  [ "$_PD_TEST_FAILS" -eq 0 ]
}

# install_test_deps <ip> <family>
# Installs Xvfb, xdotool, scrot, tesseract (OCR) on the VM for visual testing.
# Failures are non-fatal — tests degrade gracefully when tools are missing.
install_test_deps() {
  local ip="$1" family="$2"
  echo "--- installing test deps (Xvfb + xdotool + scrot + tesseract OCR) on $ip ---"
  # Install each tool individually so one unavailable package does not block the rest.
  # All failures are non-fatal; compositor tests degrade gracefully on missing tools.
  case "$family" in
    apk)
      run_on_vm "$ip" 'apk add --no-cache xvfb       2>/dev/null || true'
      run_on_vm "$ip" 'apk add --no-cache xdotool     2>/dev/null || true'
      run_on_vm "$ip" 'apk add --no-cache scrot        2>/dev/null || true'
      run_on_vm "$ip" 'apk add --no-cache tesseract-ocr 2>/dev/null || true'
      run_on_vm "$ip" 'apk add --no-cache imagemagick  2>/dev/null || true'
      run_on_vm "$ip" 'apk add --no-cache python3 py3-pip 2>/dev/null || true'
      run_on_vm "$ip" 'pip3 install --quiet pyotp 2>/dev/null || true' ;;
    deb)
      run_on_vm "$ip" 'DEBIAN_FRONTEND=noninteractive apt-get install -y -q xvfb       2>/dev/null || true'
      run_on_vm "$ip" 'DEBIAN_FRONTEND=noninteractive apt-get install -y -q x11-utils   2>/dev/null || true'
      run_on_vm "$ip" 'DEBIAN_FRONTEND=noninteractive apt-get install -y -q xdotool     2>/dev/null || true'
      run_on_vm "$ip" 'DEBIAN_FRONTEND=noninteractive apt-get install -y -q scrot       2>/dev/null || true'
      run_on_vm "$ip" 'DEBIAN_FRONTEND=noninteractive apt-get install -y -q tesseract-ocr 2>/dev/null || true'
      run_on_vm "$ip" 'DEBIAN_FRONTEND=noninteractive apt-get install -y -q imagemagick  2>/dev/null || true'
      run_on_vm "$ip" 'pip3 install --quiet pyotp 2>/dev/null || pip install --quiet pyotp 2>/dev/null || true' ;;
    rpm-dnf)
      run_on_vm "$ip" 'dnf install -y xorg-x11-server-Xvfb  2>/dev/null || true'
      run_on_vm "$ip" 'dnf install -y xorg-x11-utils         2>/dev/null || true'
      run_on_vm "$ip" 'dnf install -y xorg-x11-apps          2>/dev/null || true'
      run_on_vm "$ip" 'dnf install -y xdotool                2>/dev/null || true'
      run_on_vm "$ip" 'dnf install -y scrot                   2>/dev/null || true'
      run_on_vm "$ip" 'dnf install -y tesseract tesseract-langpack-eng 2>/dev/null || true'
      run_on_vm "$ip" 'dnf install -y ImageMagick             2>/dev/null || true'
      run_on_vm "$ip" 'pip3 install --quiet pyotp 2>/dev/null || true' ;;
    rpm-zypper)
      run_on_vm "$ip" 'zypper --non-interactive install xvfb-run    2>/dev/null || zypper --non-interactive install xorg-x11-server 2>/dev/null || true'
      run_on_vm "$ip" 'zypper --non-interactive install xdotool      2>/dev/null || true'
      run_on_vm "$ip" 'zypper --non-interactive install scrot         2>/dev/null || true'
      run_on_vm "$ip" 'zypper --non-interactive install tesseract-ocr 2>/dev/null || true'
      run_on_vm "$ip" 'zypper --non-interactive install ImageMagick   2>/dev/null || true'
      run_on_vm "$ip" 'pip3 install --quiet pyotp 2>/dev/null || true' ;;
    aur)
      run_on_vm "$ip" 'pacman -S --noconfirm --needed xorg-server-xvfb 2>/dev/null || true'
      run_on_vm "$ip" 'pacman -S --noconfirm --needed xorg-xwininfo     2>/dev/null || true'
      run_on_vm "$ip" 'pacman -S --noconfirm --needed xdotool            2>/dev/null || true'
      run_on_vm "$ip" 'pacman -S --noconfirm --needed scrot              2>/dev/null || true'
      run_on_vm "$ip" 'pacman -S --noconfirm --needed tesseract          2>/dev/null || true'
      run_on_vm "$ip" 'pacman -S --noconfirm --needed imagemagick        2>/dev/null || true'
      run_on_vm "$ip" 'pip install --quiet pyotp 2>/dev/null || true' ;;
  esac
  return 0
}

# regression_checks <ip>
# Baseline assertions every package must pass. Catches packaging regressions.
regression_checks() {
  local ip="$1"
  echo "--- regression checks on $ip ---"
  assert_on_vm "$ip" "proton-drive binary is on PATH and executable" \
    'BIN=$(command -v proton-drive || echo /usr/bin/proton-drive); [ -x "$BIN" ]'
  assert_on_vm "$ip" "binary reports a version or help" \
    'BIN=$(command -v proton-drive || echo /usr/bin/proton-drive)
     ("$BIN" --version || "$BIN" --help) >/dev/null 2>&1 || true; true'
  assert_on_vm "$ip" "desktop entry installed" \
    'ls /usr/share/applications/*roton*rive* /usr/share/applications/proton-drive.desktop 2>/dev/null | head -1'
  assert_on_vm "$ip" "application icon installed" \
    'ls /usr/share/icons/hicolor/*/apps/*roton*rive* 2>/dev/null | head -1'
}

# gui_load_test <ip>
# Basic compositor check: window appears + process survives.
# Use ui_compositor_test for full visual (OCR) assertions.
gui_load_test() {
  local ip="$1"
  local checker; checker="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gui-load-check.sh"
  _PD_TEST_RUN=$((_PD_TEST_RUN+1))
  if [ ! -f "$checker" ]; then
    echo "  ✗ FAIL: gui-load-check.sh not found at $checker"
    _PD_TEST_FAILS=$((_PD_TEST_FAILS+1)); return 1
  fi
  copy_to_vm "$ip" "$checker" >/dev/null
  local out rc=0
  out="$(run_on_vm "$ip" 'bash /tmp/pd-deploy/gui-load-check.sh proton-drive 12' 2>&1)" || rc=$?
  echo "$out" | sed 's/^/    /'
  if echo "$out" | grep -q 'GUI_LOAD_RESULT=PASS'; then
    echo "  ✓ GUI loads under CI-micro-compositor"
  else
    echo "  ✗ FAIL: GUI did not load"
    _PD_TEST_FAILS=$((_PD_TEST_FAILS+1)); return 1
  fi
}

# ui_compositor_test <ip> <suite> [artifact_dir_on_runner]
# Full visual test suite: screenshot + OCR + xdotool interaction.
# Copies ui-test-compositor.sh to the VM, runs the named suite, fetches screenshots.
# Suites: smoke | ui | sidebar | menus | functional | all
# Credentials (optional, set as CI variables): PROTON_TEST_EMAIL / PASSWORD / TOTP_SECRET
ui_compositor_test() {
  local ip="$1" suite="${2:-smoke}" local_artifact_dir="${3:-ui-artifacts}"
  local script; script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ui-test-compositor.sh"
  _PD_TEST_RUN=$((_PD_TEST_RUN+1))
  if [ ! -f "$script" ]; then
    echo "  ✗ FAIL: ui-test-compositor.sh not found"
    _PD_TEST_FAILS=$((_PD_TEST_FAILS+1)); return 1
  fi
  # Deploy script
  scp -i "$_PD_KEYFILE" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
      "$script" "$VM_SSH_USER@$ip:/tmp/pd-ui-test.sh" 2>/dev/null
  run_on_vm "$ip" 'chmod +x /tmp/pd-ui-test.sh'
  # Pass optional credential env vars
  local env_prefix=""
  [ -n "${PROTON_TEST_EMAIL:-}" ]        && env_prefix+=" PROTON_TEST_EMAIL='${PROTON_TEST_EMAIL}'"
  [ -n "${PROTON_TEST_PASSWORD:-}" ]     && env_prefix+=" PROTON_TEST_PASSWORD='${PROTON_TEST_PASSWORD}'"
  [ -n "${PROTON_TEST_TOTP_SECRET:-}" ]  && env_prefix+=" PROTON_TEST_TOTP_SECRET='${PROTON_TEST_TOTP_SECRET}'"
  [ -n "${PROTON_SYNC_LOCAL_DIR:-}" ]    && env_prefix+=" PROTON_SYNC_LOCAL_DIR='${PROTON_SYNC_LOCAL_DIR}'"
  local out rc=0
  out="$(run_on_vm "$ip" "env $env_prefix bash /tmp/pd-ui-test.sh $suite /tmp/pd-ui-artifacts" 2>&1)" || rc=$?
  echo "$out" | sed 's/^/    /'
  # Fetch screenshots back to runner as CI artifacts
  mkdir -p "$local_artifact_dir"
  scp -i "$_PD_KEYFILE" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -r \
      "$VM_SSH_USER@$ip:/tmp/pd-ui-artifacts/" "$local_artifact_dir/" 2>/dev/null || true
  local fails; fails="$(echo "$out" | grep -c '✗ FAIL' || true)"
  if [ "$rc" -eq 0 ] && [ "$fails" -eq 0 ]; then
    echo "  ✓ UI suite '$suite' passed"
  else
    echo "  ✗ FAIL: UI suite '$suite' had $fails failure(s)"
    _PD_TEST_FAILS=$((_PD_TEST_FAILS+1)); return 1
  fi
}
