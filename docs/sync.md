# Live Sync Architecture

> **Status:** Experimental — 2-way live file synchronization between a local folder and Proton Drive.
>
> **Source:** `src-tauri/src/live_sync.rs` (Rust backend) + `src-tauri/src/main.rs` (Tauri command handlers).
>
> **Internal reference:** See [`docs/live-sync-module.md`](./live-sync-module.md) for detailed internals (type definitions, worker thread mechanics, suppression cache internals).

---

## Overview

ProtonDrive Linux implements an experimental live sync mode that watches a local folder for filesystem changes and applies remote changes pushed from the Proton Drive web client. The sync is **bidirectional**:

- **Local → Remote:** Filesystem events (create, modify, delete) are detected via OS-level file watchers and emitted to the frontend, which forwards them to Proton Drive.
- **Remote → Local:** Remote changes (create/update/delete) are received from the frontend via Tauri commands and applied to the local filesystem.

Both directions enforce security validation (path traversal protection, origin checks) and use a suppression mechanism to avoid write-echo loops.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Tauri WebView                     │
│  (Proton Drive Web Client in WebKitGTK)             │
│                                                     │
│  ┌─────────────┐     live-sync://local-change       │
│  │  Sync UI    │◄──── Tauri Event (create/modify/   │
│  │             │      remove events)                 │
│  └──────┬──────┘                                    │
│         │ RemoteSyncChange                          │
│         │ (Tauri Command: handle_remote_update)     │
└─────────┼───────────────────────────────────────────┘
          │ Tauri IPC
┌─────────┼───────────────────────────────────────────┐
│  ┌──────▼──────┐   ┌──────────────────────────┐     │
│  │ Tauri State │   │  Tauri Commands           │     │
│  │  Arc<AppState│  │  - start_sync(path)       │     │
│  │  ├ client   │   │  - stop_sync()            │     │
│  │  └ sync_mgr │   │  - get_sync_status()      │     │
│  └──────┬──────┘   │  - handle_remote_update() │     │
│         │          └──────────────────────────┘     │
│  ┌──────▼──────────────────────────────────────┐   │
│  │           LiveSyncManager                    │   │
│  │                                              │   │
│  │  ┌──────────────┐  ┌─────────────────────┐   │   │
│  │  │ notify::     │  │ Worker Thread       │   │   │
│  │  │ Recommended  │  │ (live-sync-watcher) │   │   │
│  │  │ Watcher      │──│ reads mpsc channel  │   │   │
│  │  │ (recursive)  │  │ emits Tauri events  │   │   │
│  │  └──────────────┘  └─────────┬───────────┘   │   │
│  │                              │                │   │
│  │  ┌───────────────────────────▼────────────┐   │   │
│  │  │  Known Files Suppression Cache         │   │   │
│  │  │  (HashMap<PathBuf, Instant>)           │   │   │
│  │  │  TTL: 30s | Max: 4096 entries          │   │   │
│  │  └────────────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────┘   │
│                                                      │
│  ┌──────────────────────────────────────────────┐   │
│  │  Security Layer                              │   │
│  │  - Origin validation (ensure_sync_command)   │   │
│  │  - Path traversal check                      │   │
│  │  - Symlink rejection                         │   │
│  │  - Home directory scoping                    │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

### Components

| Component | File / Module | Role |
|---|---|---|
| `LiveSyncManager` | `live_sync.rs` | Core struct managing watcher, worker thread, sync root, and suppression cache |
| `LiveSyncEvent` | `live_sync.rs` | Event payload emitted to frontend on local filesystem changes |
| `LiveSyncStatus` | `live_sync.rs` | Status payload returned to frontend (enabled + folder path) |
| `RemoteSyncChange` | `live_sync.rs` | Deserialized remote action payload from frontend |
| `start_sync` | `main.rs` | Tauri command: validates path, starts watcher |
| `stop_sync` | `main.rs` | Tauri command: stops watcher and cleans up |
| `get_sync_status` | `main.rs` | Tauri command: returns current sync state |
| `handle_remote_update` | `main.rs` | Tauri command: applies a remote change to local filesystem |
| `ensure_sync_command_allowed` | `main.rs` | Origin-based command security guard |
| `validate_sync_root_path` | `main.rs` | Home-directory scoping validation |

---

## Lifecycle

### Starting Sync

1. Frontend calls `start_sync(path)` with an absolute directory path.
2. **`validate_sync_root_path`** canonicalizes the path and verifies it resides under the user's home directory — rejected otherwise (audit-logged).
3. **`ensure_sync_command_allowed`** checks the WebView is on `tauri://localhost` or `tauri://tauri.localhost` — rejected otherwise (audit-logged).
4. **`LiveSyncManager::start()`** takes the validated path, verifies it exists and is a directory, then:
   - A `notify::RecommendedWatcher` is created with `RecursiveMode::Recursive`.
   - A dedicated worker thread (`live-sync-watcher`) spawns to consume filesystem events from an mpsc channel.
5. Watcher + folder + canonical root + worker handle are stored in `LiveSyncManager`'s mutex-guarded fields.

### Running Sync

- **Local changes:** The `notify` watcher fires events → worker thread filters paths through the suppression cache → emits `live-sync://local-change` Tauri events to frontend.
- **Remote changes:** Frontend calls `handle_remote_update(RemoteSyncChange)` → manager validates the path and action → applies the change to disk → marks the path in the suppression cache to prevent echo.

### Stopping Sync

1. Frontend calls `stop_sync()`.
2. Watcher is dropped (stops filesystem monitoring).
3. Worker thread is joined (waits for current event to finish).
4. Suppression cache is cleared.
5. All mutex-guarded fields are reset to `None`.

---

## Error Handling

### Error Constants

All user-facing error strings are defined as named constants at the top of `live_sync.rs`:

| Constant | Value | Trigger |
|---|---|---|
| `ERR_SYNC_SETUP_FAILED` | `"Failed to start live sync"` | Watcher init failure, path canonicalization failure, thread spawn failure |
| `ERR_SYNC_STATE_UNAVAILABLE` | `"Live sync is temporarily unavailable"` | Any mutex lock failure on internal state |
| `ERR_SYNC_NOT_ACTIVE` | `"Live sync is not active"` | Remote change applied while sync is not running |
| `ERR_SYNC_INVALID_REMOTE_CONTENT` | `"Invalid remote file content"` | Base64 decode failure on remote content payload |
| `ERR_SYNC_WRITE_FAILED` | `"Failed to apply remote file update"` | `fs::write` or `fs::create_dir_all` failure |
| `ERR_SYNC_DELETE_FAILED` | `"Failed to apply remote file deletion"` | `fs::remove_file` failure |
| `ERR_SYNC_INVALID_TARGET` | `"Invalid sync target path"` | Path traversal attempt or symlink found in path |

### Error Flow

1. All errors are logged with `[LiveSync]` prefix via `eprintln!` with detailed context (path, error message).
2. Security violations are additionally logged with `[LiveSync][AUDIT]` prefix for security monitoring.
3. Tauri commands return `Result<T, String>` — errors propagate to the frontend as string error messages.
4. Mutex poisoning is handled: if a mutex lock fails, the operation returns the appropriate `ERR_SYNC_*` constant rather than panicking.

### Mutex Strategy

`LiveSyncManager` uses `std::sync::Mutex` (not `parking_lot`) for all mutable fields:
- `watcher`: The `notify` watcher handle
- `folder`: The sync root directory path
- `root_canonical`: The canonicalized root (for path validation)
- `worker`: The worker thread `JoinHandle`
- `known_files`: Shared suppression cache (`Arc<Mutex<HashMap>>`)

Each lock operation maps errors to `ERR_SYNC_STATE_UNAVAILABLE` — never panics.

---

## Suppression / Anti-Echo Logic

A critical challenge in bidirectional sync is the **write-echo loop**: a remote change triggers a local write, which the file watcher detects and re-emits as a local change, which the frontend sends back to Proton as a remote change, and so on.

### Known Files Cache

| Parameter | Value |
|---|---|
| **TTL** | 30 seconds (`SUPPRESSION_TTL`) |
| **Max entries** | 4096 (`SUPPRESSION_CACHE_MAX`) |
| **Storage** | `HashMap<PathBuf, Instant>` behind `Arc<Mutex<...>>` |
| **Pruning** | On every read/write, expired entries are evicted |

### Flow

```
Remote change received
  → apply_remote_change() called
     → mark_known_file(path)   ← inserts path with current timestamp
     → fs::write / fs::remove_file
  → file watcher fires event
     → should_ignore_known_file(path) checks cache
        → If path found AND age ≤ 30s → skip (suppress)
        → Otherwise → emit live-sync://local-change
```

### Pruning

- **Time-based:** On every cache access, entries older than `SUPPRESSION_TTL` are evicted.
- **Capacity-based:** If the cache exceeds `SUPPRESSION_CACHE_MAX` after time-based pruning, the oldest entries are evicted first (sorted by timestamp, oldest removed).

This prevents memory leaks during burst operations while keeping suppression effective.

---

## Security Model

### Origin Validation (`ensure_sync_command_allowed`)

All sync commands (`start_sync`, `stop_sync`, `get_sync_status`, `handle_remote_update`) require the calling WebView's URL to match `tauri://localhost` or `tauri://tauri.localhost`. Any other origin (including Proton Drive's actual domain) is rejected with `ERR_SYNC_NOT_ALLOWED` and audit-logged.

This prevents Proton Drive's web client scripts from directly manipulating the local filesystem — only the Tauri shell's own frontend code can issue sync commands.

### Path Traversal Protection (`validate_path_within_root`)

All remote change operations validate the target path against three checks:

1. **Explicit traversal:** Rejects `..`, `/`, and `Prefix` components in relative paths.
2. **Symlink traversal:** Iterates every component in the target path and rejects any that is a symlink — prevents symlink-based jailbreak.
3. **Canonical root check:** Resolves the target to its canonical path (or its nearest existing ancestor's canonical path) and verifies it starts with the sync root.

### Home Directory Scoping (`validate_sync_root_path`)

The sync root directory must canonicalize to a path under the user's home directory. This prevents sync to system paths.

### Audit Logging

All security-relevant events are logged with `[LiveSync][AUDIT]` prefix:
- Rejected remote write actions (action + path + reason)
- Rejected remote delete actions (path + reason)
- Successful remote actions (action + path + result)

---

## Retry Logic

The current implementation does **not** include explicit retry logic for transient failures:

| Scenario | Behavior | Improvement Needed |
|---|---|---|
| Mutex lock contention | Returns error immediately | Could retry with backoff in high-contention scenarios |
| File write failure (disk full, permission) | Returns error immediately | Frontend could retry; backend could queue failed writes |
| Network/API failures | Handled by frontend | Remote change operations are synchronous — no retry queue |
| Watcher channel errors | Logged and skipped | `notify::Event` errors are silently dropped |

### Recommended Retry Improvements

1. **Write queue:** Buffer failed remote changes for retry with exponential backoff (3 attempts, 1s/4s/15s intervals).
2. **Mutex retry:** Use `try_lock` with spin-wait instead of immediate failure during normal (non-security) operations.
3. **Event deduplication:** The `known_files` cache is event-level; a write-retry-reemit pattern could be improved with sequence counters per file.

---

## Event Flow Diagrams

### Local Change (Create/Modify/Delete)

```
User edits file in sync folder
         │
         ▼
notify::RecommendedWatcher fires event
         │
         ▼
Worker thread (live-sync-watcher)
  ┌─────────────────────────┐
  │ Map EventKind to string:│
  │ Create → "create"       │
  │ Modify → "modify"       │
  │ Remove → "remove"       │
  │ Others → continue (skip)│
  └─────────┬───────────────┘
            │
            ▼
  ┌─────────────────────────┐
  │ Filter through          │
  │ should_ignore_known_file│
  │  → Skip if in cache     │
  │    and TTL not expired  │
  └─────────┬───────────────┘
            │
            ▼
  ┌─────────────────────────┐
  │ Emit Tauri event        │
  │ "live-sync://local-     │
  │  change" with           │
  │ LiveSyncEvent{kind,paths}│
  └─────────────────────────┘
```

### Remote Change (Create/Update/Delete)

```
Frontend receives remote change from Proton Drive
         │
         ▼
Tauri command: handle_remote_update(RemoteSyncChange)
         │
         ▼
ensure_sync_command_allowed() → reject if wrong origin
         │
         ▼
apply_remote_change(RemoteSyncChange)
         │
         ├──> validate path components (no .., /, symlinks)
         ├──> validate target is within canonical root
         │
         ├── Action "create" | "update":
         │      ├── Decode base64 content
         │      ├── fs::create_dir_all(parent)
         │      ├── mark_known_file(path) ← suppress echo
         │      └── fs::write(path, data)
         │
         └── Action "delete":
                ├── validate path within root
                ├── mark_known_file(path) ← suppress echo
                └── fs::remove_file(path)
```

---

## Configuration

All sync parameters are hardcoded constants in `live_sync.rs`:

| Constant | Value | Purpose |
|---|---|---|
| `SUPPRESSION_TTL` | `Duration::from_secs(30)` | How long a file is suppressed after a remote write |
| `SUPPRESSION_CACHE_MAX` | `4096` | Maximum entries in suppression cache |
| `PROTON_API_BASE` | `"https://mail.proton.me"` | Proton API base URL (in `main.rs`) |

These are compile-time constants — no runtime configuration is exposed.

---

## Limitations

1. **No conflict resolution:** If a file is modified locally and remotely simultaneously, the last write wins (remote action overwrites local state).
2. **No explicit retry:** Transient write failures are surfaced to the frontend immediately, with no backend retry queue.
3. **No partial sync:** The entire configured folder is watched recursively — no exclusion patterns (`.git/`, `node_modules/`).
4. **No file size limits:** Large files block the Tauri command thread during base64 decode and write.
5. **Unidirectional event model:** Local changes are emitted as events but the frontend must decide whether and how to upload them.
6. **Thread safety:** Uses `std::sync::Mutex` (not async-aware) — can block the async Tauri runtime under contention.
7. **No initial sync:** Starting sync does not reconcile existing files — only new changes after start are tracked.
8. **Single sync root:** Only one folder can be synced at a time — starting a new sync stops the previous one.
