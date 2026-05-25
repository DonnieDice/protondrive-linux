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
require_pattern src-tauri/src/main.rs "register_sync_root_metadata" "selected sync root must be registered in the zero-trust metadata DB"
require_pattern src-tauri/src/main.rs "DEFAULT_SYNC_ROOT_DIR" "primary sync root must default to ~/ProtonDrive"
require_pattern src-tauri/src/main.rs "DEFAULT_REMOTE_SCOPE_COMPUTERS" "primary root must target Proton Drive Computers device scope"
require_pattern src-tauri/src/main.rs "DEFAULT_DEVICE_TYPE_LINUX" "primary root must register as a Linux device"
require_pattern src-tauri/src/main.rs "default_sync_device_name" "default device name must stay explicit"
require_pattern src-tauri/src/main.rs "sanitize_sync_device_name" "hostnames must be sanitized before becoming remote folder names"
require_pattern src-tauri/src/main.rs "\\[Sync\\] auto-start active enabled=" "sync auto-start must log positive active status"

require_pattern src-tauri/src/sync_db.rs "sync-state\\.sqlite3" "sync metadata DB path must remain explicit"
require_pattern src-tauri/src/sync_db.rs "hash_sensitive" "sync metadata must hash sensitive paths and remote IDs"
require_pattern src-tauri/src/sync_db.rs "REMOTE_SCOPE_COMPUTERS" "sync metadata must model Computers as a device scope"
require_pattern src-tauri/src/sync_db.rs "REMOTE_SCOPE_MY_FILES" "sync metadata must model extra mappings as My files scope"
require_pattern src-tauri/src/sync_db.rs "device_name_hash" "sync metadata must hash local device names"
require_pattern src-tauri/src/sync_db.rs "remote_root_folder_uid_hash" "sync metadata must be ready to hash Proton Drive device rootFolderUid"
require_pattern src-tauri/src/sync_db.rs "remote_share_id_hash" "sync metadata must be ready to hash Proton Drive device shareId"
require_pattern src-tauri/src/sync_db.rs "remote_path_hash" "sync metadata must store hashed My files mapping paths"
require_pattern src-tauri/src/sync_db.rs "relative_path_hash" "sync metadata must store hashed relative paths"
require_pattern src-tauri/src/sync_db.rs "remote_link_id_hash" "sync metadata must store hashed remote link IDs"
require_pattern src-tauri/src/sync_db.rs "SyncItemState::Tombstone" "sync metadata must model safe tombstones"
require_pattern src-tauri/src/sync_db.rs "0o600" "sync metadata DB must be private on Unix"
require_pattern src-tauri/src/sync_db.rs "stores_metadata_without_raw_paths_or_remote_ids" "sync DB privacy behavior must have unit coverage"
require_pattern src-tauri/src/sync_db.rs "computers_root_stores_device_scope_without_remote_path" "Computers device mapping must have unit coverage"
require_pattern src-tauri/src/sync_db.rs "my_files_mapping_stores_remote_path_hash_without_device_name" "My files mapping must have unit coverage"
require_pattern src-tauri/src/sync_db.rs "tombstone_requires_existing_known_item" "sync DB destructive delete safety must have unit coverage"

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
require_pattern src-tauri/src/live_sync.rs "record_local_change_metadata" "local changes must be persisted into the sync metadata queue"
require_pattern src-tauri/src/live_sync.rs "SyncItemState::LocalPending" "local changes must become pending sync metadata"
require_pattern src-tauri/src/live_sync.rs "relative_path" "remote relative path field must remain implemented"
require_pattern src-tauri/src/live_sync.rs "content_base64" "remote base64 content field must remain implemented"
require_pattern src-tauri/src/live_sync.rs "SUPPRESSION_CACHE_MAX" "remote write suppression must stay bounded"
require_pattern src-tauri/src/live_sync.rs "symlink traversal is not allowed" "remote path safety must reject symlink traversal"
require_pattern src-tauri/src/live_sync.rs "remote_change_serde_uses_frontend_camel_case_contract" "camelCase payload contract must have unit coverage"
require_pattern src-tauri/src/live_sync.rs "sync_target_rejects_symlink_traversal" "symlink traversal rejection must have unit coverage"
require_pattern src-tauri/src/live_sync.rs "relative_sync_path_is_root_relative_for_mapping" "relative path mapping must have unit coverage"
require_pattern src-tauri/src/live_sync.rs "poll_snapshot_diff_detects_create_modify_and_remove" "poll diffing must have unit coverage"
require_pattern src-tauri/src/live_sync.rs "local_change_metadata_records_pending_items_and_safe_tombstones" "local change metadata queueing must have unit coverage"
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
require_pattern docs/sync.md "Zero-Trust Metadata Database" "zero-trust sync metadata model must stay documented"
require_pattern docs/sync.md "last-known-synced metadata cache" "sync architecture must track OneDrive-style reconciliation model"
require_pattern docs/sync.md "Tombstones only apply to previously known items" "sync docs must preserve conservative delete semantics"
require_pattern docs/sync.md "createDevice\\(name, DeviceType\\.Linux\\)" "default remote device API model must stay documented"
require_pattern docs/sync.md "rootFolderUid" "Proton Drive device rootFolderUid mapping must stay documented"
require_pattern docs/sync.md "shareId" "Proton Drive device shareId mapping must stay documented"
require_pattern docs/sync.md "My files" "extra mappings must target My files, not Computers"
require_pattern docs/sync.md "duplicate host data" "extra mappings must not duplicate data into the primary root"
require_pattern docs/sync.md "Do not start with the entire" "Pictures safety warning must remain documented"
require_pattern docs/login-sync-regression-runbook.md "Manual Sync Procedure" "manual sync procedure must stay documented"
require_pattern docs/login-sync-regression-runbook.md "~/ProtonDrive" "manual sync procedure must use the default drive root"
require_pattern docs/login-sync-regression-runbook.md "PROTONDRIVE_AUTO_SYNC_PATH" "manual sync procedure must document env override for extra mapping tests"
require_pattern docs/login-sync-regression-runbook.md "\\[LiveSync\\] watcher active root=" "manual sync procedure must document watcher marker"
require_pattern docs/login-sync-regression-runbook.md "source=default" "manual sync procedure must document normal default root startup marker"
require_pattern docs/login-sync-regression-runbook.md "No test may be considered a sync pass from Drive/Photos API traffic alone" "manual sync procedure must reject API-only false positives"
require_pattern docs/login-sync-regression-runbook.md "silent window where file changes occur but no .*\\[Sync\\].*\\[LiveSync\\]" "manual sync procedure must catch silent no-op sync"

require_pattern patches/common/add-drive-linux-drawer-rail.patch "protondrive-linux-drawer-app-button:linux-icon" "Linux drawer rail entry must stay patched into WebClients"
require_pattern patches/common/add-drive-linux-drawer-rail.patch "applications/drive/src/app/legacy/components/layout/DriveWindow\\.tsx" "Linux drawer patch must target current DriveWindow location"
require_pattern patches/common/add-drive-linux-drawer-rail.patch "brand-linux" "Linux drawer rail entry must use the Linux icon"
require_pattern patches/common/add-drive-linux-drawer-rail.patch "Proton Drive Linux" "Linux drawer rail entry must expose a product label"
require_pattern patches/common/add-drive-linux-drawer-rail.patch "DRAWER_NATIVE_APPS\\.QUICK_SETTINGS" "Linux drawer rail entry must open the native Drive settings drawer until dedicated sync UI exists"
require_pattern patches/common/show-drive-drawer-rail-in-desktop-shell.patch "drawer-visibility-control flex" "drawer chevron must be visible in the desktop shell"
require_pattern patches/common/show-drive-drawer-rail-in-desktop-shell.patch "drawer-sidebar inline" "drawer rail must not be hidden by responsive web breakpoints in the desktop shell"
require_pattern docs/sync.md "collapsed on startup" "Linux drawer startup behavior must stay documented"
require_pattern scripts/build-webclients.sh "patches/common.*\\.patch" "WebClients build cache key must include every common patch"

require_absent src-tauri/src/live_sync.rs "emit\\([^\\n]*local-change" "event name must remain explicit, not rebuilt dynamically"
require_absent src-tauri/src/main.rs "DEFAULT_REMOTE_DEVICE_PARENT_DIR|default_remote_device_folder_path" "Computers must not be modeled as a My files path prefix"
require_absent docs/sync.md "Computers/<PC name>" "docs must not describe Computers as a path prefix"

echo "Sync regression checks passed."
