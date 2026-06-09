#!/usr/bin/env bash
# Sidebar regression checks — guards all four drawer entries:
#   1. Contacts          (native React, always-true permission)
#   2. Calendar          (iframe, local /calendar/ build, Tauri URL patch)
#   3. Referral          (native React, canShowDrawerApp from feature flags)
#   4. Linux options     (DriveLinuxPanel, sync IPC, replaces DriveQuickSettings)
#
# Every check here is a "never silently break" invariant.  Add new checks when
# new sidebar features are added; never delete a check without a replacement.
set -euo pipefail

require_pattern() {
  local file="$1" pattern="$2" message="$3"
  if ! grep -Eq "$pattern" "$file"; then
    echo "sidebar regression check failed: $message" >&2
    echo "  missing pattern '$pattern' in $file" >&2
    exit 1
  fi
}

require_absent() {
  local file="$1" pattern="$2" message="$3"
  if grep -Eq "$pattern" "$file"; then
    echo "sidebar regression check failed: $message" >&2
    echo "  forbidden pattern '$pattern' found in $file" >&2
    exit 1
  fi
}

# ── 1. Contacts ───────────────────────────────────────────────────────────────
# ContactDrawerAppButton is upstream code; the patch context must include it so
# we notice if upstream removes it from the drawerSidebarButtons array.

require_pattern \
  patches/common/add-drive-linux-drawer-rail.patch \
  "ContactDrawerAppButton" \
  "Contacts button must remain visible in the drawer rail patch context lines"

# ── 2. Calendar ───────────────────────────────────────────────────────────────

require_pattern \
  patches/common/add-drive-linux-drawer-rail.patch \
  "CalendarDrawerAppButton" \
  "CalendarDrawerAppButton must remain in the drawer rail patch context"

require_pattern \
  scripts/patch_drive_linux_calendar.py \
  "__TAURI__" \
  "calendar Tauri URL patch must detect the Tauri runtime"

require_pattern \
  scripts/patch_drive_linux_calendar.py \
  "getAppHrefBundle" \
  "calendar Tauri URL patch must use the bundle (local) path helper"

require_pattern \
  scripts/patch_drive_linux_calendar.py \
  "isAppReachable || isTauri" \
  "calendar must load in Tauri even before API reachability is confirmed"

require_pattern \
  scripts/build-webclients.sh \
  "proton-calendar build:web" \
  "calendar app must be built as part of the WebClients build pipeline"

require_pattern \
  scripts/build-webclients.sh \
  "applications/drive/dist/calendar" \
  "calendar dist must be copied into the drive dist for Tauri asset serving"

require_pattern \
  scripts/build-webclients.sh \
  "patch_drive_linux_calendar\\.py" \
  "calendar Tauri URL patch script must run during every WebClients build"

require_pattern \
  scripts/build-webclients.sh \
  'base href="/calendar/"' \
  "calendar dist must have its base href rewritten for nested deployment"

# ── 3. Referral / Promotion ───────────────────────────────────────────────────
# ReferralAppButton and DrawerReferralView are upstream React components; no local
# build is needed. The Linux patch only PREPENDS to the drawerSidebarButtons array,
# so referral (which follows) is never disturbed. Guard by verifying the prepend
# anchor is still in place (if it shifts, our button would land in the wrong spot).

require_pattern \
  scripts/patch_drive_linux_drawer.py \
  "drawerSidebarButtons" \
  "drawer patch must target the drawerSidebarButtons array to prepend the Linux entry"

require_pattern \
  scripts/patch_drive_linux_drawer.py \
  "ReferralAppButton" \
  "drawer patch script must document the upstream ReferralAppButton in its inline comments"

# ── 4. Linux panel ────────────────────────────────────────────────────────────

require_pattern \
  scripts/patch_drive_linux_panel.py \
  "DriveLinuxPanel" \
  "patch_drive_linux_panel.py must create and wire DriveLinuxPanel"

require_pattern \
  scripts/patch_drive_linux_panel.py \
  "get_sync_status" \
  "Linux panel must call get_sync_status Tauri IPC on mount"

require_pattern \
  scripts/patch_drive_linux_panel.py \
  "stop_sync" \
  "Linux panel must expose a stop_sync action"

require_pattern \
  scripts/patch_drive_linux_panel.py \
  "DriveQuickSettings" \
  "Linux panel must preserve existing DriveQuickSettings below the sync header"

require_pattern \
  scripts/patch_drive_linux_panel.py \
  "customAppSettings" \
  "patch_drive_linux_panel.py must patch the customAppSettings prop in DriveWindow"

require_pattern \
  scripts/patch_drive_linux_panel.py \
  "DriveLinuxPanel" \
  "patch_drive_linux_panel.py must reference DriveLinuxPanel in the customAppSettings replacement"

require_pattern \
  scripts/build-webclients.sh \
  "patch_drive_linux_panel\\.py" \
  "Linux panel patch must run during every WebClients build"

require_pattern \
  scripts/build-webclients.sh \
  "patch_drive_linux_panel\\.py" \
  "Linux panel patch must be included in the WebClients cache key"

require_pattern \
  patches/common/add-drive-linux-drawer-rail.patch \
  "DRAWER_NATIVE_APPS\\.QUICK_SETTINGS" \
  "Linux button must use QUICK_SETTINGS slot (DriveLinuxPanel is the customAppSettings)"

require_pattern \
  scripts/patch_drive_linux_drawer.py \
  "DRAWER_NATIVE_APPS\.QUICK_SETTINGS" \
  "Linux button Python fallback must also use QUICK_SETTINGS slot"

# ── 5. Build pipeline integrity ───────────────────────────────────────────────

require_pattern \
  scripts/build-webclients.sh \
  "patch_drive_linux_calendar\\.py" \
  "calendar patch must be in the WebClients cache key hash"

require_pattern \
  scripts/build-webclients.sh \
  "patch_drive_linux_panel\\.py" \
  "Linux panel patch must be in the WebClients cache key hash"

# Absence: the calendar patch must use the local bundle path, not a remote hostname,
# in the actual URL construction (getAppHrefBundle, not a hard-coded external URL).
require_absent \
  scripts/patch_drive_linux_calendar.py \
  "iframeSrc.*calendar\\.proton\\.me\|setIframeSrcMap.*calendar\\.proton\\.me" \
  "calendar iframeSrc must not be set to calendar.proton.me — use getAppHrefBundle instead"

echo "Sidebar regression checks passed."
