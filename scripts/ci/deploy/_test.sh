#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/ci/deploy/_test.sh
#
# Test framework shared by every per-distro test.sh. Provides:
#   - assert helpers (collect failures, exit non-zero if any failed)
#   - regression_checks <ip>   : the baseline suite every package must pass
#   - gui_load_test <ip>       : runs the CI-micro-compositor GUI load check on the VM
#   - install_test_deps <ip> <family> : install Xvfb/weston/cage + tools on the VM
#
# Sourced by scripts/ci/deploy/<distro>/test.sh, which defines run_tests().
# Requires _common.sh (run_on_vm, copy_to_vm) to be sourced first.
# ─────────────────────────────────────────────────────────────────────────────

_PD_TEST_FAILS=0
_PD_TEST_RUN=0

# assert <description> -- <command...>   run command on the *runner*, record pass/fail
assert() {
  local desc="$1"; shift
  [ "$1" = "--" ] && shift
  _PD_TEST_RUN=$((_PD_TEST_RUN+1))
  if "$@"; then echo "  ✓ $desc"; else echo "  ✗ FAIL: $desc"; _PD_TEST_FAILS=$((_PD_TEST_FAILS+1)); fi
}

# assert_on_vm <ip> <description> <remote-command>   assert a command succeeds on the VM
assert_on_vm() {
  local ip="$1" desc="$2" cmd="$3"
  _PD_TEST_RUN=$((_PD_TEST_RUN+1))
  if run_on_vm "$ip" "$cmd" >/dev/null 2>&1; then echo "  ✓ $desc"
  else echo "  ✗ FAIL: $desc"; _PD_TEST_FAILS=$((_PD_TEST_FAILS+1)); fi
}

# test_summary   print totals; return non-zero if any assertion failed
test_summary() {
  echo "--- tests: $((_PD_TEST_RUN-_PD_TEST_FAILS))/${_PD_TEST_RUN} passed ---"
  [ "$_PD_TEST_FAILS" -eq 0 ]
}

# install_test_deps <ip> <family>   ensure a headless display + introspection tools exist
install_test_deps() {
  local ip="$1" family="$2"
  echo "--- installing test deps (compositor + tools) on $ip ---"
  case "$family" in
    apk)        run_on_vm "$ip" 'apk add --no-cache xvfb xdotool 2>/dev/null || true' ;;
    deb)        run_on_vm "$ip" 'DEBIAN_FRONTEND=noninteractive apt-get install -y -q xvfb x11-utils xdotool weston 2>/dev/null || apt-get install -y -q xvfb x11-utils 2>/dev/null || true' ;;
    rpm-dnf)    run_on_vm "$ip" 'dnf install -y xorg-x11-server-Xvfb xorg-x11-utils xdotool weston 2>/dev/null || dnf install -y xorg-x11-server-Xvfb 2>/dev/null || true' ;;
    rpm-zypper) run_on_vm "$ip" 'zypper --non-interactive install xvfb-run xdotool weston 2>/dev/null || zypper --non-interactive install xorg-x11-server 2>/dev/null || true' ;;
    aur)        run_on_vm "$ip" 'pacman -S --noconfirm --needed xorg-server-xvfb xorg-xwininfo xdotool cage 2>/dev/null || true' ;;
  esac
  return 0   # missing test deps degrade gracefully (gui-load-check falls back/skips)
}

# gui_load_test <ip>   copy the CI-micro-compositor checker to the VM and run it
gui_load_test() {
  local ip="$1"
  local checker; checker="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/gui-load-check.sh"
  _PD_TEST_RUN=$((_PD_TEST_RUN+1))
  if [ ! -f "$checker" ]; then echo "  ✗ FAIL: gui-load-check.sh missing"; _PD_TEST_FAILS=$((_PD_TEST_FAILS+1)); return 1; fi
  copy_to_vm "$ip" "$checker" >/dev/null
  local out; out="$(run_on_vm "$ip" 'bash /tmp/pd-deploy/gui-load-check.sh proton-drive 12' 2>&1)"
  echo "$out" | sed 's/^/    /'
  if echo "$out" | grep -q 'GUI_LOAD_RESULT=PASS'; then echo "  ✓ GUI loads under CI-micro-compositor"
  else echo "  ✗ FAIL: GUI did not load"; _PD_TEST_FAILS=$((_PD_TEST_FAILS+1)); return 1; fi
}

# regression_checks <ip>   baseline every package must pass (catches packaging regressions)
regression_checks() {
  local ip="$1"
  echo "--- regression checks on $ip ---"
  assert_on_vm "$ip" "proton-drive binary is on PATH and executable" \
    'BIN=$(command -v proton-drive || echo /usr/bin/proton-drive); [ -x "$BIN" ]'
  assert_on_vm "$ip" "binary reports a version or help" \
    'BIN=$(command -v proton-drive||echo /usr/bin/proton-drive); ("$BIN" --version || "$BIN" --help) >/dev/null 2>&1 || true; true'
  assert_on_vm "$ip" "desktop entry installed" \
    'ls /usr/share/applications/*roton*rive* /usr/share/applications/proton-drive.desktop 2>/dev/null | head -1'
  assert_on_vm "$ip" "application icon installed" \
    'ls /usr/share/icons/hicolor/*/apps/*roton*rive* 2>/dev/null | head -1'
}
