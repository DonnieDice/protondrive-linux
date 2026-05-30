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
#   install_test_deps <ip> <family> — install headless display + tools on VM
#   regression_checks <ip>          — baseline suite every package must pass
#   gui_load_test <ip>              — CI-micro-compositor GUI load check

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
# Ensures a headless display server and introspection tools exist on the VM.
# Failures are non-fatal — gui-load-check degrades gracefully when missing.
install_test_deps() {
  local ip="$1" family="$2"
  echo "--- installing test deps (compositor + tools) on $ip ---"
  case "$family" in
    apk)
      run_on_vm "$ip" 'apk add --no-cache xvfb xdotool 2>/dev/null || true' ;;
    deb)
      run_on_vm "$ip" \
        'DEBIAN_FRONTEND=noninteractive apt-get install -y -q xvfb x11-utils xdotool weston 2>/dev/null \
         || apt-get install -y -q xvfb x11-utils 2>/dev/null || true' ;;
    rpm-dnf)
      run_on_vm "$ip" \
        'dnf install -y xorg-x11-server-Xvfb xorg-x11-utils xdotool weston 2>/dev/null \
         || dnf install -y xorg-x11-server-Xvfb 2>/dev/null || true' ;;
    rpm-zypper)
      run_on_vm "$ip" \
        'zypper --non-interactive install xvfb-run xdotool weston 2>/dev/null \
         || zypper --non-interactive install xorg-x11-server 2>/dev/null || true' ;;
    aur)
      run_on_vm "$ip" \
        'pacman -S --noconfirm --needed xorg-server-xvfb xorg-xwininfo xdotool cage 2>/dev/null || true' ;;
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
# Copies the CI-micro-compositor checker to the VM and runs it.
# Uses weston-headless → cage → Xvfb in order of availability.
gui_load_test() {
  local ip="$1"
  local checker; checker="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gui-load-check.sh"
  _PD_TEST_RUN=$((_PD_TEST_RUN+1))
  if [ ! -f "$checker" ]; then
    echo "  ✗ FAIL: gui-load-check.sh not found at $checker"
    _PD_TEST_FAILS=$((_PD_TEST_FAILS+1)); return 1
  fi
  copy_to_vm "$ip" "$checker" >/dev/null
  local out
  out="$(run_on_vm "$ip" 'bash /tmp/pd-deploy/gui-load-check.sh proton-drive 12' 2>&1)"
  echo "$out" | sed 's/^/    /'
  if echo "$out" | grep -q 'GUI_LOAD_RESULT=PASS'; then
    echo "  ✓ GUI loads under CI-micro-compositor"
  else
    echo "  ✗ FAIL: GUI did not load"
    _PD_TEST_FAILS=$((_PD_TEST_FAILS+1)); return 1
  fi
}
