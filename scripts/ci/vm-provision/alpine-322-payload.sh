#!/usr/bin/env bash
# scripts/ci/vm-provision/alpine-322-payload.sh
# Emits the base64 payload consumed by alpine-322-console.expect:
#   <live-install script> __SPLIT__ <chroot-config script>
# Single-line base64 (-w0) so the expect driver can send it as one line.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVE="$HERE/guest/alpine-322-live-install.sh"
CHROOT="$HERE/guest/alpine-322-chroot-config.sh"
[ -r "$LIVE" ]   || { echo "missing $LIVE" >&2; exit 1; }
[ -r "$CHROOT" ] || { echo "missing $CHROOT" >&2; exit 1; }
{ cat "$LIVE"; echo "__SPLIT__"; cat "$CHROOT"; } | base64 -w0
