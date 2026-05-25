# Two-Way Sync Notes

This document records the current sync contract, known weak areas, and the safe test plan for validating a real folder such as `~/Pictures`.

## Current Status

The repository contains the native Tauri sync bridge from PR #35:

- `set_sync_root(path)` persists a selected sync directory under app data and starts sync.
- `start_sync(path)` starts a recursive native watcher for an existing folder under `$HOME`.
- `PROTONDRIVE_AUTO_SYNC_PATH` designates the selected sync directory during smoke tests and
  overrides the default root for that test launch.
- On app launch, the primary local sync directory defaults to `~/ProtonDrive` and is created if
  missing.
- The default remote target is a device-scoped folder, `Computers/<PC name>`. The PC name is
  sanitized from the host name so multiple Linux machines do not collide at the same remote root.
- Extra path mappings will be layered on through CLI/config/UI instead of being copied into
  `~/ProtonDrive`, which would duplicate host data.
- The selected root is registered in a private SQLite metadata database for future reconciliation.
- `live-sync://local-change` is emitted for local create, modify, and remove events from both
  the watcher and the poll reconciler.
- `handle_remote_update(change)` applies remote create, update, and delete events into the watched folder.
- `get_sync_status()` reports whether a folder is currently being watched.
- `stop_sync()` stops the watcher and clears suppression state.

The native bridge is not the full sync engine by itself. The frontend integration is responsible for
choosing the folder, mapping local root-relative paths to Proton Drive node paths, uploading local
changes to Proton Drive, receiving remote Proton Drive events, and calling `handle_remote_update`.
The UI target is a Linux entry in the right-side Proton app rail where Contacts, Calendar, and
Referral currently live. The rail should follow WebClients behavior: collapsed on startup with the
existing expand/collapse chevron visible, then showing the Linux entry after expansion. The initial
rail patch opens the existing Drive quick-settings drawer as the Proton Drive Linux options surface.
The dedicated sync UI still needs to call `set_sync_root`, show `get_sync_status`, and manage future
remote-root mappings without coupling sync to whichever Drive folder is currently open.

## Native Contract

### Local To Remote

1. Frontend calls `start_sync(path)`.
2. Native validates that `path` exists, is a directory, and resolves under `$HOME`.
3. Native watches the folder recursively with `notify`.
4. Native also polls the selected directory at `DEFAULT_SYNC_POLL_INTERVAL` and reconciles file
   metadata snapshots. Watchers provide low-latency events; polling catches missed watcher events
   and drift after suspend/resume or filesystem backend quirks.
5. Native emits `live-sync://local-change` with:
   - `kind`: `create`, `modify`, or `remove`
   - `paths`: absolute local paths from the watcher event
   - `rootPath`: selected local sync root
   - `relativePaths`: paths relative to `rootPath`
   - `source`: `watcher` or `poller`
6. Frontend maps `relativePaths` to the configured Proton Drive remote root and uploads/deletes in Proton Drive.

### Remote To Local

1. Frontend receives or polls Proton Drive remote changes.
2. Frontend calls `handle_remote_update(change)` with:
   - `relativePath`
   - `action`: `create`, `update`, or `delete`
   - `contentBase64` for create/update
3. Native rejects root, prefix, and `..` path components.
4. Native rejects symlink traversal.
5. Native writes or deletes the target file under the sync root.
6. Native marks the file in the suppression cache so the resulting local watcher event does not immediately ping-pong back to remote.

## Regression Rules

Do not change these without updating tests, docs, and frontend integration together:

- Command names: `start_sync`, `stop_sync`, `get_sync_status`, `handle_remote_update`.
- Passive primary root/config: `DEFAULT_SYNC_ROOT_DIR`, `~/ProtonDrive`, `SYNC_ROOT_CONFIG_FILE`.
- Default remote device mapping: `DEFAULT_REMOTE_DEVICE_PARENT_DIR`, `Computers/<PC name>`.
- Test override hook: `PROTONDRIVE_AUTO_SYNC_PATH`.
- Event name: `live-sync://local-change`.
- Event payload shape: `{ kind, paths, rootPath, relativePaths, source }`.
- Remote update payload shape: `{ relativePath, action, contentBase64 }`.
- Poll rate: `DEFAULT_SYNC_POLL_INTERVAL`.
- Sync roots must stay constrained under `$HOME`.
- Remote relative paths must reject `..`, absolute paths, Windows prefixes, and symlink traversal.
- Remote-write suppression must stay bounded and short-lived.
- Sync metadata must stay zero-trust: local paths and remote IDs are stored as stable hashes, not
  raw names, paths, share IDs, link IDs, or file contents.

## Zero-Trust Metadata Database

The native sync engine now has a SQLite metadata foundation in `src-tauri/src/sync_db.rs`.
This follows the OneDrive Linux model at the architecture level: use a durable local database as a
last-known-synced metadata cache, then reconcile local scans, watcher events, and remote deltas
against that cache. It does not store file contents and it is not a source of truth.

Current guarantees:

- Database path: `sync-state.sqlite3` under the app data directory.
- File mode: `0600` on Unix; parent directory is tightened to `0700`.
- Sensitive values are SHA-256 hashed before storage: root paths, remote device folder paths,
  relative paths, volume IDs, share IDs, link IDs, parent IDs, and remote revisions.
- Rows track metadata only: local kind, size, mtime, optional content fingerprint, remote mapping
  hashes, sync state, retries, error code, and tombstone timestamps.
- Tombstones only apply to previously known items; a missing row cannot create a destructive delete.
- The DB is treated as untrusted cache. Future upload/download workers must validate destructive
  operations against the filesystem and Proton Drive API before applying them.

The existing `sync-root.txt` file still stores the active local path because the native process
must know which directory to watch before the UI exists. On normal startup the primary local root is
`~/ProtonDrive` and the remote mapping is `Computers/<PC name>`; non-default roots are treated as
future extra mappings, not replacements for the primary drive root. The config file is restricted to
`0600` on Unix. It is operational config, not sync history.

## Weak Areas

These are the areas to watch during real sync testing:

- There is a passive primary-root config and a zero-trust metadata database, but no native
  reconciliation worker consumes pending DB rows yet.
- There is no native conflict resolver beyond DB state placeholders.
- There is no native retry queue or offline queue.
- There is no native checksum or mtime comparison.
- Rename and move are not modeled as first-class operations by the native bridge.
- Directory delete is not handled by `handle_remote_update`; delete removes files.
- Remote create/update writes full base64 file contents, so large-file streaming is frontend-owned.
- Local events expose absolute and root-relative paths, but frontend mapping to Proton Drive remote
  roots is still future work.
- Recursive watching of a large folder can produce high event volume.
- Poll reconciliation scans the selected root every 30 seconds by default; full `~/Pictures` should
  not be enabled until staged-folder event volume is acceptable.
- The suppression cache prevents immediate ping-pong but is not durable across app restarts.

## `~/ProtonDrive` Test Plan

Use the default drive root for normal testing, and a staged folder only when intentionally testing
extra path mappings:

1. Confirm `~/ProtonDrive` exists after app startup.
2. Create `~/ProtonDrive/protondrive-sync-smoke`.
3. Confirm logs show the sync root in `get_sync_status()`.
4. Create a small local file in the staged folder.
5. Confirm a `live-sync://local-change` event appears and the frontend uploads it.
6. Modify the file locally.
7. Confirm a modify event appears and remote content changes.
8. Delete the file locally.
9. Confirm a remove event appears and remote delete is applied.
10. Create or update a small remote file under the synced folder.
11. Confirm frontend calls `handle_remote_update` and native writes the file locally.
12. Delete the remote file.
13. Confirm native removes the local file.
14. Repeat with a nested subdirectory.
15. Only after the staged folder passes should `~/Pictures` be considered.

Do not start with the entire `~/Pictures` directory. It is too large and too valuable for first-pass sync verification. The safe path is to prove the full local-to-remote and remote-to-local loop in a disposable subfolder first.

## Monitoring Checklist

While testing, monitor:

- App log: `~/Documents/Development/Apps/protondrive-linux/proton-drive.log`
- Native sync markers: `[LiveSync]`, `[LiveSync][AUDIT]`, and `[Sync]`
- Frontend event handling for `live-sync://local-change`
- Proton Drive API calls related to file create/update/delete
- Local filesystem changes under the staged folder
- Unexpected duplicate events after remote writes
- Any watcher errors, rejected paths, or failed writes/deletes

## Current Audit Finding

The current native bridge is present and unit-tested. In this checkout, the sync command names and event contract are also guarded by:

- the Tauri command definitions in `src-tauri/src/main.rs`
- the native watcher implementation in `src-tauri/src/live_sync.rs`
- `scripts/ci/check-sync-regressions.sh`
- `docs/login-sync-regression-runbook.md`
- this document

If sync is working from the app UI, the frontend call path still does not appear as a normal checked-in app source file in this repo tree. That path may come from the bundled WebClients integration, runtime assets, or a branch/patch not represented by a direct source reference here. Capture that call path during testing so future regressions can be guarded at the exact integration point.

## Live Test Notes

### 2026-05-23 AUR Test Build

Installed artifact:

- Branch: `fix/90-login-session-routing`
- Commit: `914f06ef`
- Binary: `/usr/bin/proton-drive`
- Binary md5: `abe9b3c315acc659f78a0ae9b29b67f6`

Session persistence:

- `Keep me signed in` was selected during login.
- Local storage contained `default-persistent`.
- Local storage contained a `ps-0` session entry.
- After login, `GET /api/auth/v4/sessions/local/key` returned `200`.
- Earlier stale-session startup produced expected `401` and `422` responses before re-login; those did not persist after login.

Pictures test target:

- Folder: `~/Pictures`
- Observed size: about `52G`
- Observed file count at maxdepth 2: `3697`
- Smoke folder created: `~/Pictures/protondrive-sync-smoke`

Observed Drive/Photos activity:

- `POST /api/drive/v2/volumes/.../links` returned `200`.
- `GET /api/drive/v2/shares/photos` returned `200`.
- `POST /api/drive/photos/volumes/.../links` returned `200`.
- `GET /api/drive/volumes` returned `200`.
- `GET /api/drive/devices` returned `200`.

Observed gap:

- No `start_sync`, `get_sync_status`, `handle_remote_update`, `[Sync]`, `[LiveSync]`, or `live-sync://local-change` log entries were observed during the initial Pictures/Photos test window.
- That means the test confirmed authenticated Drive/Photos API activity, but it did not yet prove that the native recursive watcher bridge was active for `~/Pictures`.

Monitoring files from this test:

- App log: `~/Documents/Development/Apps/protondrive-linux/proton-drive.log`
- Sync monitor: `/tmp/protondrive-sync-monitor.log`
- Pictures/filesystem monitor: `/tmp/protondrive-picture-sync-watch.log`
