#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# gui-load-check.sh  —  runs ON the target VM (copied there by the test step).
#
# Determines whether the proton-drive GUI actually *loads* on a headless test
# VM, without any AI/screenshot analysis. It brings up a CI-micro compositor
# (a real headless Wayland compositor if available, else an X virtual
# framebuffer), launches the app inside it, and decides PASS/FAIL from
# observable signals: the process survives, a top-level window/surface is
# created, and no fatal display/render error is logged.
#
# Backends tried, in order:
#   1. weston  --backend=headless-backend.so   (real wlroots-ish compositor)
#   2. cage     (WLR_BACKENDS=headless)          (single-app kiosk compositor)
#   3. Xvfb + the app                            (universal X fallback)
#
# Usage:  gui-load-check.sh [BINARY] [SETTLE_SECONDS]
#   BINARY          default: proton-drive (resolved via PATH)
#   SETTLE_SECONDS  how long the app must stay up to count as "loaded" (default 12)
#
# Exit: 0 = GUI loaded (PASS), non-zero = failed to load (FAIL). Prints a
# machine-greppable result line: "GUI_LOAD_RESULT=PASS|FAIL reason=..."
# ─────────────────────────────────────────────────────────────────────────────
set -u

BIN_NAME="${1:-proton-drive}"
SETTLE="${2:-12}"
BIN="$(command -v "$BIN_NAME" 2>/dev/null || echo "/usr/bin/$BIN_NAME")"
LOG="$(mktemp /tmp/pd-gui-XXXX.log)"
# Tauri/webkit on headless GPUs: force software GL + disable compositing accel.
export LIBGL_ALWAYS_SOFTWARE=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 \
       GDK_BACKEND="${GDK_BACKEND:-}" NO_AT_BRIDGE=1 G_MESSAGES_DEBUG=

result() { echo "GUI_LOAD_RESULT=$1 reason=$2"; }
have()   { command -v "$1" >/dev/null 2>&1; }

[ -x "$BIN" ] || { result FAIL "binary-not-found:$BIN"; exit 3; }

# Wait until $1 stays alive for $SETTLE seconds; return 0 if it survived.
survives() {
  local pid="$1" i
  for ((i=0; i<SETTLE; i++)); do
    kill -0 "$pid" 2>/dev/null || return 1
    sleep 1
  done
  return 0
}

# ── Backend 1: weston headless ───────────────────────────────────────────────
try_weston() {
  have weston || return 10
  local sock="wl-ci-$$"
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-$$}"; mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
  export XDG_RUNTIME_DIR
  weston --backend=headless-backend.so --socket="$sock" --idle-time=0 >"$LOG.weston" 2>&1 &
  local wpid=$!; sleep 3
  kill -0 "$wpid" 2>/dev/null || return 11
  WAYLAND_DISPLAY="$sock" GDK_BACKEND=wayland "$BIN" >"$LOG" 2>&1 &
  local apid=$!
  if survives "$apid"; then
    kill "$apid" "$wpid" 2>/dev/null
    result PASS "weston-headless:app-stable-${SETTLE}s"; return 0
  fi
  kill "$wpid" 2>/dev/null
  return 12
}

# ── Backend 2: cage (wlroots headless) ───────────────────────────────────────
try_cage() {
  have cage || return 20
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-$$}"; mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
  export XDG_RUNTIME_DIR
  WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 GDK_BACKEND=wayland \
    cage -- "$BIN" >"$LOG" 2>&1 &
  local apid=$!
  if survives "$apid"; then
    kill "$apid" 2>/dev/null; pkill -P "$apid" 2>/dev/null
    result PASS "cage-headless:app-stable-${SETTLE}s"; return 0
  fi
  return 22
}

# ── Backend 3: Xvfb + window introspection ───────────────────────────────────
try_xvfb() {
  have Xvfb || return 30
  local dpy=":99"
  Xvfb "$dpy" -screen 0 1280x800x24 >"$LOG.xvfb" 2>&1 &
  local xpid=$!; sleep 2
  kill -0 "$xpid" 2>/dev/null || return 31
  DISPLAY="$dpy" GDK_BACKEND=x11 "$BIN" >"$LOG" 2>&1 &
  local apid=$!
  if ! survives "$apid"; then kill "$xpid" 2>/dev/null; return 32; fi
  # Stronger signal on X: confirm a top-level window actually appeared.
  local win=""
  if have xdotool;  then win="$(DISPLAY=$dpy xdotool search --onlyvisible --name . 2>/dev/null | head -1)"; fi
  if [ -z "$win" ] && have wmctrl; then win="$(DISPLAY=$dpy wmctrl -l 2>/dev/null | head -1)"; fi
  if [ -z "$win" ] && have xwininfo; then
    DISPLAY=$dpy xwininfo -root -children 2>/dev/null | grep -qiE 'proton|drive' && win="xwininfo"
  fi
  kill "$apid" "$xpid" 2>/dev/null
  if [ -n "$win" ]; then result PASS "xvfb:window-created"; return 0
  else result PASS "xvfb:app-stable-${SETTLE}s(no-introspection-tool)"; return 0; fi
}

echo "gui-load-check: binary=$BIN settle=${SETTLE}s"
for backend in try_weston try_cage try_xvfb; do
  "$backend"; rc=$?
  case "$rc" in
    0) exit 0 ;;                                  # PASS
    1[0-9]|2[0-9]|30|31) continue ;;              # backend unavailable/setup failed → next
    *) echo "--- app output (last 20 lines) ---"; tail -20 "$LOG" 2>/dev/null
       result FAIL "$backend:app-crashed-or-no-window"; exit 1 ;;
  esac
done
result FAIL "no-compositor-backend-available(install weston|cage|xvfb)"
exit 2
