#!/usr/bin/env bash
set -euo pipefail

require_pattern() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if ! grep -Eq "$pattern" "$file"; then
    echo "sync regression check failed: $message" >&2
    echo "missing pattern '$pattern' in $file" >&2
    exit 1
  fi
}

require_absent() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if grep -Eq "$pattern" "$file"; then
    echo "sync regression check failed: $message" >&2
    echo "forbidden pattern '$pattern' found in $file" >&2
    exit 1
  fi
}

require_pattern src-tauri/src/main.rs "start_sync" "start_sync command must stay registered"
require_pattern src-tauri/src/main.rs "stop_sync" "stop_sync command must stay registered"
require_pattern src-tauri/src/main.rs "get_sync_status" "get_sync_status command must stay registered"
require_pattern src-tauri/src/main.rs "set_sync_root" "future UI needs a selected sync root command"
require_pattern src-tauri/src/main.rs "handle_remote_update" "handle_remote_update command must stay registered"
require_pattern src-tauri/src/main.rs "docs/sync.md" "inline sync bridge comment must point maintainers to docs/sync.md"
require_pattern src-tauri/src/main.rs "PROTONDRIVE_AUTO_SYNC_PATH" "manual sync smoke tests need env auto-start hook"
require_pattern src-tauri/src/main.rs "SYNC_ROOT_CONFIG_FILE" "selected sync root must persist for passive startup"
require_pattern src-tauri/src/main.rs "read_selected_sync_root" "persisted sync root must auto-start without UI"
require_pattern src-tauri/src/main.rs "\\[Sync\\] auto-start active enabled=" "sync auto-start must log positive active status"

require_pattern src-tauri/src/live_sync.rs "live-sync://local-change" "frontend local-change event contract must not be renamed silently"
require_pattern src-tauri/src/live_sync.rs "\\[LiveSync\\] watcher active root=" "sync startup must have positive runtime logging"
require_pattern src-tauri/src/live_sync.rs "\\[LiveSync\\] poller active root=" "sync poll reconciliation must have positive runtime logging"
require_pattern src-tauri/src/live_sync.rs "\\[LiveSync\\] local-change kind=" "local filesystem changes must have positive runtime logging"
require_pattern src-tauri/src/live_sync.rs "\\[LiveSync\\]\\[AUDIT\\] remote action=.*result=success" "remote apply must have positive audit logging"
require_pattern src-tauri/src/live_sync.rs "DEFAULT_SYNC_POLL_INTERVAL" "sync poll rate must stay explicit"
require_pattern src-tauri/src/live_sync.rs "root_path" "local change events must expose root mapping"
require_pattern src-tauri/src/live_sync.rs "relative_paths" "local change events must expose root-relative mapping"
require_pattern src-tauri/src/live_sync.rs "source" "local change events must identify watcher or poller source"
require_pattern src-tauri/src/live_sync.rs "diff_snapshots" "poll reconciliation diff must stay implemented"
require_pattern src-tauri/src/live_sync.rs "relative_path" "remote relative path field must remain implemented"
require_pattern src-tauri/src/live_sync.rs "content_base64" "remote base64 content field must remain implemented"
require_pattern src-tauri/src/live_sync.rs "SUPPRESSION_CACHE_MAX" "remote write suppression must stay bounded"
require_pattern src-tauri/src/live_sync.rs "symlink traversal is not allowed" "remote path safety must reject symlink traversal"
require_pattern src-tauri/src/live_sync.rs "remote_change_serde_uses_frontend_camel_case_contract" "camelCase payload contract must have unit coverage"
require_pattern src-tauri/src/live_sync.rs "sync_target_rejects_symlink_traversal" "symlink traversal rejection must have unit coverage"
require_pattern src-tauri/src/live_sync.rs "relative_sync_path_is_root_relative_for_mapping" "relative path mapping must have unit coverage"
require_pattern src-tauri/src/live_sync.rs "poll_snapshot_diff_detects_create_modify_and_remove" "poll diffing must have unit coverage"
require_pattern src-tauri/src/live_sync.rs "suppression_cache_drops_remote_write_marker_once" "remote write ping-pong suppression must have unit coverage"
require_pattern src-tauri/src/live_sync.rs "suppression_cache_is_bounded" "suppression cache bound must have unit coverage"

require_pattern README.md "docs/sync.md" "README must link to sync operations documentation"
require_pattern docs/sync.md "Current Status" "sync documentation must describe current status"
require_pattern docs/sync.md "Weak Areas" "sync documentation must keep weak areas visible"
require_pattern docs/sync.md "~/Pictures" "sync documentation must keep Pictures test plan visible"
require_pattern docs/sync.md "live-sync://local-change" "sync documentation must record frontend event contract"
require_pattern docs/sync.md "handle_remote_update" "sync documentation must record remote apply contract"
require_pattern docs/sync.md "right-side Proton app rail" "future Linux settings UI target must stay documented"
require_pattern docs/sync.md "Drive quick-settings drawer" "initial Linux drawer target must stay documented"
require_pattern docs/sync.md "Do not start with the entire" "Pictures safety warning must remain documented"
require_pattern docs/login-sync-regression-runbook.md "Manual Sync Procedure" "manual sync procedure must stay documented"
require_pattern docs/login-sync-regression-runbook.md "PROTONDRIVE_AUTO_SYNC_PATH" "manual sync procedure must document env auto-start"
require_pattern docs/login-sync-regression-runbook.md "\\[LiveSync\\] watcher active root=" "manual sync procedure must document watcher marker"
require_pattern docs/login-sync-regression-runbook.md "No test may be considered a sync pass from Drive/Photos API traffic alone" "manual sync procedure must reject API-only false positives"
require_pattern docs/login-sync-regression-runbook.md "silent window where file changes occur but no .*\\[Sync\\].*\\[LiveSync\\]" "manual sync procedure must catch silent no-op sync"

require_pattern patches/common/add-drive-linux-drawer-rail.patch "protondrive-linux-drawer-app-button:linux-icon" "Linux drawer rail entry must stay patched into WebClients"
require_pattern patches/common/add-drive-linux-drawer-rail.patch "brand-linux" "Linux drawer rail entry must use the Linux icon"
require_pattern patches/common/add-drive-linux-drawer-rail.patch "Proton Drive Linux" "Linux drawer rail entry must expose a product label"
require_pattern patches/common/add-drive-linux-drawer-rail.patch "DRAWER_NATIVE_APPS\\.QUICK_SETTINGS" "Linux drawer rail entry must open the native Drive settings drawer until dedicated sync UI exists"
require_pattern docs/sync.md "collapsed on startup" "Linux drawer startup behavior must stay documented"
require_pattern scripts/build-webclients.sh "patches/common.*\\.patch" "WebClients build cache key must include every common patch"

require_absent src-tauri/src/live_sync.rs "emit\\([^\\n]*local-change" "event name must remain explicit, not rebuilt dynamically"

echo "Sync regression checks passed."
