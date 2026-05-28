# live_sync Module — Real-Time Sync Engine

> **Status:** Experimental — 2-way live file synchronization between a local folder and Proton Drive.
>
> **Source:** `src-tauri/src/live_sync.rs` (425 lines — self-contained, no separate persistence layer)
>
> **Broader architecture:** See [docs/sync.md](sync.md) for system-level diagrams, Tauri command wiring, security origin validation, and lifecycle flows.

---

## Overview

`live_sync.rs` implements the core Rust engine for real-time bidirectional file sync. It handles two directions of data flow:

| Direction | Trigger | Mechanism |
|-----------|---------|-----------|
| **Local → Remote** | OS-level filesystem events (`notify` crate) | File watcher detects create/modify/remove → emits Tauri event to frontend → frontend uploads to Proton API |
| **Remote → Local** | Frontend receives Proton API push | Frontend calls `handle_remote_update` Tauri command → Rust decodes and writes/deletes file on disk |

The module is self-contained with no external database or persistence layer — all state is in-memory and managed via `Mutex`-guarded fields on `LiveSyncManager`.

---

## Key Types

### `LiveSyncManager`
The central stateful manager. Owns all mutable sync state behind `std::sync::Mutex`:

| Field | Type | Purpose |
|-------|------|---------|
| `watcher` | `Option<RecommendedWatcher>` | The `notify` filesystem watcher handle |
| `folder` | `Option<PathBuf>` | The sync root directory path |
| `root_canonical` | `Option<PathBuf>` | Canonicalized root (for path traversal checks) |
| `worker` | `Option<JoinHandle<()>>` | Background thread handle (`live-sync-watcher`) |
| `known_files` | `Arc<Mutex<HashMap<PathBuf, Instant>>>` | Shared suppression cache (anti-echo) |

**Lifecycle:** `Default::default()` → `start(app, folder)` → (running) → `stop()`.
Only one sync root at a time — calling `start()` again stops the previous one.

### `LiveSyncEvent`
Serialized as JSON and emitted on the `"live-sync://local-change"` Tauri event channel when the file watcher detects a local change.

```rust
pub struct LiveSyncEvent {
    pub kind: String,       // "create" | "modify" | "remove"
    pub paths: Vec<String>, // Absolute paths, filtered through suppression cache
}
```

### `LiveSyncStatus`
Returned to the frontend for UI binding (e.g. displaying current sync state).

```rust
pub struct LiveSyncStatus {
    pub enabled: bool,
    pub folder_path: Option<String>,
}
```

### `RemoteSyncChange`
Deserialized from the frontend when it pushes a remote change received from Proton Drive.

```rust
#[serde(rename_all = "camelCase")]
pub struct RemoteSyncChange {
    pub relative_path: String,     // e.g. "Documents/report.pdf"
    pub action: String,            // "create" | "update" | "delete"
    pub content_base64: Option<String>, // Base64 content; required for create/update
}
```

---

## Sync Flow

### Local Change (Create/Modify/Remove)

```
User writes file in sync folder
  → notify::RecommendedWatcher (RecursiveMode::Recursive)
    → mpsc channel delivers event to worker thread
      → Worker maps EventKind: Create→"create", Modify→"modify", Remove→"remove"
      → Worker filters paths through should_ignore_known_file() (anti-echo)
      → Worker emits Tauri event "live-sync://local-change"
        → Frontend receives LiveSyncEvent and uploads to Proton API
```

**Unidirectional at this point:** The Rust engine does not upload files. It emits events and the frontend decides whether/how to upload.

### Remote Change (Create/Update/Delete)

```
Frontend receives remote change from Proton Drive
  → Calls handle_remote_update Tauri command
    → ensure_sync_command_allowed() (origin check)
    → apply_remote_change(RemoteSyncChange)
      → Reject "create"/"update" without content_base64
      → Validate relative_path: no "..", "/", or "Prefix" components
      → Validate target within canonical root (symlink traversal check)
      → For create/update: fs::create_dir_all(parent) → mark_known_file(path) → fs::write(path, data)
      → For delete: mark_known_file(path) → fs::remove_file(path)
```

---

## Anti-Echo / Self-Suppression

A critical challenge in bidirectional sync is the **write-echo loop**: a remote change triggers a local write, which the file watcher detects and re-emits as a local change, which the frontend sends back to Proton as a remote change — looping indefinitely.

### Known Files Cache

| Property | Value |
|----------|-------|
| **Storage** | `HashMap<PathBuf, Instant>` behind `Arc<Mutex<...>>` |
| **TTL** | 30 seconds (`SUPPRESSION_TTL`) |
| **Max entries** | 4096 (`SUPPRESSION_CACHE_MAX`) |
| **Pruning** | Time-based on every access; capacity-based overflow evicts oldest |

### Flow

```
apply_remote_change()
  → mark_known_file(path)    ← inserts path + now
  → fs::write / fs::remove_file
  → notify watcher fires event (same path)
    → should_ignore_known_file(path)
      → If found AND age ≤ 30s → SUPPRESS (don't emit)
      → Otherwise → emit live-sync://local-change
```

### Pruning Logic

1. **Time-based:** On every cache read/write, entries older than `SUPPRESSION_TTL` (30s) are evicted.
2. **Capacity-based:** If after time-based pruning the cache still exceeds 4096 entries, the oldest entries are sorted by timestamp and removed until under the cap.

This prevents memory leaks during burst operations while keeping suppression effective.

---

## State Reconciliation

**Last-write-wins.** The current implementation has no conflict resolution:

| Scenario | Behavior |
|----------|----------|
| File modified locally AND remotely simultaneously | Remote action overwrites local state |
| File deleted locally while being updated remotely | Remote create/update writes the file |
| File created locally and remotely at the same path | Remote write overwrites local content |
| Remove of non-existent file | Silently succeeds (only removes if `target.exists()`) |

The anti-echo cache prevents infinite loops but does not detect or resolve true conflicts. Remote changes always take precedence over concurrent local changes.

---

## Security Model (within the module)

The module implements two security checks directly:

### 1. Path Traversal (`validate_path_within_root`)

- Rejects explicit traversal: `..`, `/`, and `Prefix` components in `relative_path`
- Rejects symlinks: iterates every component in the target path, checks `symlink_metadata()` for symlinks
- Canonical root check: resolves the target (or its nearest existing ancestor) to a canonical path and verifies it starts with the sync root
- For non-existent targets, walks ancestors to find one that exists for canonical comparison

### 2. Audit Logging

All security events log with `[LiveSync][AUDIT]` prefix:
- Rejected remote write: `action={} path={} reason={}`
- Rejected remote delete: `path={} reason={}`
- Successful remote action: `action={} result=success path={}`

The origin validation (`ensure_sync_command_allowed`) and home-directory scoping (`validate_sync_root_path`) live in `main.rs`, not in this module.

---

## Error Handling

All user-facing error strings are compile-time constants:

| Constant | Value | Triggers |
|----------|-------|----------|
| `ERR_SYNC_SETUP_FAILED` | `"Failed to start live sync"` | Watcher init, path canonicalization, thread spawn |
| `ERR_SYNC_STATE_UNAVAILABLE` | `"Live sync is temporarily unavailable"` | Any mutex lock failure |
| `ERR_SYNC_NOT_ACTIVE` | `"Live sync is not active"` | Remote change while sync not running |
| `ERR_SYNC_INVALID_REMOTE_CONTENT` | `"Invalid remote file content"` | Base64 decode failure |
| `ERR_SYNC_WRITE_FAILED` | `"Failed to apply remote file update"` | `fs::write` or `fs::create_dir_all` failure |
| `ERR_SYNC_DELETE_FAILED` | `"Failed to apply remote file deletion"` | `fs::remove_file` failure |
| `ERR_SYNC_INVALID_TARGET` | `"Invalid sync target path"` | Path traversal or symlink in path |

All errors are logged with `[LiveSync]` prefix via `eprintln!`. Mutex poisoning is handled by mapping to error constants rather than panicking.

---

## Relationship to Persistence Layer

**There is no separate `sync_db.rs` or persistence layer.** The `live_sync` module writes directly to the filesystem via `std::fs`:

- `apply_remote_change` calls `fs::create_dir_all`, `fs::write`, and `fs::remove_file` directly
- No database, no journal, no write-ahead log
- No retry queue — failures are returned to the frontend immediately

This means:
- All sync state is ephemeral — if the app restarts, sync must be re-enabled and no in-flight changes are queued
- No conflict history — last write wins without any record of what was overwritten
- No offline queue — remote changes can only be applied while the app is running with sync active

---

## Helper Functions

### `should_ignore_known_file(known_files, path) -> bool`
Checks the suppression cache. If the path was recently written by `apply_remote_change` (within `SUPPRESSION_TTL`), returns `true` so the worker thread skips emitting a Tauri event. Prunes expired entries on access.

### `prune_known_files(cache, now)`
Removes entries older than `SUPPRESSION_TTL`. Then, if the cache still exceeds `SUPPRESSION_CACHE_MAX`, sorts remaining entries by timestamp and drops the oldest.

### `validate_path_within_root(root_canonical, target) -> Result<(), String>`
Performs three-layer path traversal protection:
1. Walks every component checking for symlinks (using `symlink_metadata`)
2. Canonicalizes the target (or its nearest existing ancestor) 
3. Verifies the canonical path starts with the canonical sync root

### `find_existing_ancestor(path) -> Option<PathBuf>`
Walks up the directory tree from `path` until it finds a component that exists on disk. Used by `validate_path_within_root` when the target file doesn't exist yet (e.g., pending a remote create).

---

## Configuration Constants

All hardcoded at the top of `live_sync.rs`:

| Constant | Value | Purpose |
|----------|-------|---------|
| `SUPPRESSION_TTL` | `Duration::from_secs(30)` | How long to suppress echo events after remote write |
| `SUPPRESSION_CACHE_MAX` | `4096` | Maximum suppression cache entries |

No runtime configuration is exposed — these are compile-time constants.

---

## Limitations

1. **No conflict resolution** — last-write-wins, remote always overrides local
2. **No retry queue** — transient write/decode failures are surfaced immediately
3. **No partial sync** — entire folder is watched recursively, no exclusion patterns
4. **No file size limits** — large files block the Tauri command thread during base64 decode and write
5. **Unidirectional local events** — Rust emits events but doesn't upload; frontend must handle upload
6. **Blocking Mutex** — `std::sync::Mutex` can block the async Tauri runtime under contention
7. **No initial reconciliation** — sync only tracks changes after `start()`; existing files are not compared
8. **Single sync root** — only one folder at a time
9. **No persistence** — all state is in-memory; restart loses any in-flight sync state
