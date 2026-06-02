---
title: "Two-Way Sync Notes"
created: 2026-05-28
updated: 2026-05-28
type: architecture
tags: [sync]
sources:
  - []
---


# Two-Way Sync Notes

> **⚠️ Legacy document.** This was the original sync design document written during initial implementation. For the current, comprehensive documentation, see:

- **[Sync System](sync-system.md)** — Full architecture: dual-change detection (inotify + polling), suppression cache, remote apply, path validation
- **[Sync Database](sync-database.md)** — Complete SQLite schema, item states, privacy hashing model, migrations

## Current Status

The repository contains the native Tauri sync bridge from PR #35:

- `set_sync_root(path)` persists a selected sync directory under app data and starts sync.
- `start_sync(path)` starts a dual-change detection system: an inotify watcher for near-instant events + a 30-second polling comparator for guaranteed coverage.
- `get_sync_status()` returns the current sync state (enabled, folder path, poll interval).
- `stop_sync()` stops the watcher and poller threads, clears state.
- `handle_remote_update(change)` applies remote changes (create/update/delete) to the local filesystem with path validation and echo suppression.
- `read_sync_file(root, relative)` reads a file for upload as base64-encoded payload.
- `get_sync_device_name()` returns the sanitized local hostname for Proton device registration.
- `PROTONDRIVE_AUTO_SYNC_PATH` designates the selected sync directory during smoke tests and
  overrides the default root for that test launch.
- On app launch, the primary local sync directory defaults to `~/ProtonDrive` and is created if
  missing. A persisted extra sync root is used if one was previously configured.
- The default remote target is the Proton Drive SDK device model under the Web UI's `Computers`
  section, not a folder path under `My files`. The local `~/ProtonDrive` root maps to a Linux
  device named from the sanitized host name via `createDevice(name, DeviceType.Linux)`.
- The device API returns `rootFolderUid` and `shareId`; those are the remote root identifiers the
  future upload worker must use when mapping root-relative local paths into the Computers section.
- Extra path mappings will be layered on through CLI/config/UI instead of being copied into
  a monolithic config file.

## Sync command contract

The full set of Tauri commands exposed by the sync bridge:

| Command | Purpose | Auth required |
|---------|---------|---------------|
| `start_sync` | Start watcher + poller on a path | `tauri://` origin only |
| `stop_sync` | Stop watcher + poller, clear state | `tauri://` origin only |
| `get_sync_status` | Return current sync state | `tauri://` origin only |
| `set_sync_root` | Persist + start a new sync root | `tauri://` origin only |
| `handle_remote_update` | Apply remote change to local filesystem | `tauri://` origin only |
| `read_sync_file` | Read local file for upload (base64) | `tauri://` origin only |
| `get_sync_device_name` | Return sanitized hostname | `tauri://` origin only |

## Event contract

The sync bridge emits a single Tauri event:

- `live-sync://local-change` — emitted when either the watcher or poller detects a local change

Payload shape:
```json
{
    "kind": "create|modify|remove",
    "paths": ["/absolute/path/to/file"],
    "root_path": "/absolute/sync/root",
    "relative_paths": ["relative/path/to/file"],
    "source": "watcher|poller"
}
```

## Known weak areas

1. **Upload bridge is pending.** `read_sync_file` handles reading local files for upload, and `handle_remote_update` handles applying remote changes locally. The upload path (local change → detect → upload to Proton) still relies on the frontend sync engine (WebClients `syncRootListener`). The Rust side provides the detection and file reading; the frontend owns the upload semantics.

2. **Symlink handling.** Symlinks are detected and rejected by `validate_path_within_root`. This is intentional — allowing symlinks would create a path traversal vector. The trade-off is that symlinked folders inside the sync root won't sync.

3. **Large file uploads.** `read_sync_file` has a `MAX_SYNC_BRIDGE_FILE_BYTES` limit. Very large files need chunking at the frontend level before reaching the bridge.

4. **Polling interval.** The current 30-second poll interval is a trade-off between responsiveness and I/O load. Very active sync roots with thousands of files may benefit from a longer interval.

5. **Echo suppression TTL.** The 30-second `SUPPRESSION_TTL` works well for typical use but could suppress legitimate local changes if a user edits a file immediately after a remote sync writes it.

## Safe test plan

For validating against a real folder such as `~/Pictures`:

1. Create a dedicated test folder (`~/Pictures/protondrive-sync-smoke`) rather than syncing the entire Pictures directory
2. Set `PROTONDRIVE_AUTO_SYNC_PATH=~/Pictures/protondrive-sync-smoke` and launch the app
3. Verify `get_sync_status()` returns `enabled: true` with the correct folder
4. Create a test file in the folder and verify the `live-sync://local-change` event fires
5. Modify the file and verify a `modify` event fires
6. Delete the file and verify a `remove` event fires
7. Use `handle_remote_update` to push a file and verify it appears on disk
8. Verify the watcher does NOT fire when writing a file that was just applied via `handle_remote_update` (echo suppression)
