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
require_pattern src-tauri/src/main.rs "handle_remote_update" "handle_remote_update command must stay registered"
require_pattern src-tauri/src/main.rs "docs/sync.md" "inline sync bridge comment must point maintainers to docs/sync.md"

require_pattern src-tauri/src/live_sync.rs "live-sync://local-change" "frontend local-change event contract must not be renamed silently"
require_pattern src-tauri/src/live_sync.rs "relative_path" "remote relative path field must remain implemented"
require_pattern src-tauri/src/live_sync.rs "content_base64" "remote base64 content field must remain implemented"
require_pattern src-tauri/src/live_sync.rs "SUPPRESSION_CACHE_MAX" "remote write suppression must stay bounded"
require_pattern src-tauri/src/live_sync.rs "symlink traversal is not allowed" "remote path safety must reject symlink traversal"
require_pattern src-tauri/src/live_sync.rs "remote_change_serde_uses_frontend_camel_case_contract" "camelCase payload contract must have unit coverage"
require_pattern src-tauri/src/live_sync.rs "sync_target_rejects_symlink_traversal" "symlink traversal rejection must have unit coverage"

require_pattern README.md "docs/sync.md" "README must link to sync operations documentation"
require_pattern docs/sync.md "Current Status" "sync documentation must describe current status"
require_pattern docs/sync.md "Weak Areas" "sync documentation must keep weak areas visible"
require_pattern docs/sync.md "~/Pictures" "sync documentation must keep Pictures test plan visible"
require_pattern docs/sync.md "live-sync://local-change" "sync documentation must record frontend event contract"
require_pattern docs/sync.md "handle_remote_update" "sync documentation must record remote apply contract"
require_pattern docs/sync.md "Do not start with the entire" "Pictures safety warning must remain documented"

require_absent src-tauri/src/live_sync.rs "emit\\([^\\n]*local-change" "event name must remain explicit, not rebuilt dynamically"

echo "Sync regression checks passed."
