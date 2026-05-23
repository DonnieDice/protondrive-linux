# Two-Way Sync Notes

This document records the current sync contract, known weak areas, and the safe test plan for validating a real folder such as `~/Pictures`.

## Current Status

The repository contains the native Tauri sync bridge from PR #35:

- `start_sync(path)` starts a recursive native watcher for an existing folder under `$HOME`.
- `live-sync://local-change` is emitted for local create, modify, and remove events.
- `handle_remote_update(change)` applies remote create, update, and delete events into the watched folder.
- `get_sync_status()` reports whether a folder is currently being watched.
- `stop_sync()` stops the watcher and clears suppression state.

The native bridge is not the full sync engine by itself. The frontend integration is responsible for choosing the folder, listening for `live-sync://local-change`, uploading local changes to Proton Drive, receiving remote Proton Drive events, and calling `handle_remote_update`.

## Native Contract

### Local To Remote

1. Frontend calls `start_sync(path)`.
2. Native validates that `path` exists, is a directory, and resolves under `$HOME`.
3. Native watches the folder recursively with `notify`.
4. Native emits `live-sync://local-change` with:
   - `kind`: `create`, `modify`, or `remove`
   - `paths`: absolute local paths from the watcher event
5. Frontend maps the absolute paths back to sync-root-relative paths and uploads/deletes in Proton Drive.

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
- Event name: `live-sync://local-change`.
- Event payload shape: `{ kind, paths }`.
- Remote update payload shape: `{ relativePath, action, contentBase64 }`.
- Sync roots must stay constrained under `$HOME`.
- Remote relative paths must reject `..`, absolute paths, Windows prefixes, and symlink traversal.
- Remote-write suppression must stay bounded and short-lived.

## Weak Areas

These are the areas to watch during real sync testing:

- There is no durable local sync database in the native layer.
- There is no native conflict resolver.
- There is no native retry queue or offline queue.
- There is no native checksum or mtime comparison.
- Rename and move are not modeled as first-class operations by the native bridge.
- Directory delete is not handled by `handle_remote_update`; delete removes files.
- Remote create/update writes full base64 file contents, so large-file streaming is frontend-owned.
- Local watcher events expose absolute paths, so frontend mapping to relative paths must be correct.
- Recursive watching of a large folder can produce high event volume.
- The suppression cache prevents immediate ping-pong but is not durable across app restarts.

## `~/Pictures` Test Plan

Use a staged folder before pointing at the full Pictures library:

1. Create `~/Pictures/protondrive-sync-smoke`.
2. Start sync on that staged folder from the app UI or frontend command path.
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

The current native bridge is present and unit-tested. In this checkout, the only checked-in references to the sync commands are the Tauri command definitions, README documentation, and this document. If sync is working from the app UI, that frontend path must come from the bundled WebClients integration, runtime code, or a branch/patch not represented by a checked-in source reference here. Capture that call path during testing so future regressions can be guarded at the exact integration point.

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
