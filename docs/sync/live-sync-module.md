# `live_sync` Module — Real-Time Sync Engine

> **Status:** Experimental — 2-way live file synchronization between a local folder and Proton Drive.
>
> **Source:** `src-tauri/src/live_sync.rs` (941 lines, integrates with `sync_db.rs` for persistent metadata)
>
> **Broader architecture:** See [sync-system.md](sync-system.md) for the full live sync architecture overview,
> including Tauri command wiring, security origin validation, and lifecycle flows.

---

## Overview

`live_sync.rs` is the core Rust engine for real-time bidirectional file sync. It
operates three independent threads:

| Thread | Name | Trigger | Mechanism |
|--------|------|---------|-----------|
| **Watcher** | `live-sync-watcher` | OS-level filesystem events | `notify` crate (inotify/FSEvents) → mpsc channel → Tauri event emit |
| **Poller** | `live-sync-poller` | Timer (default 30s) | Full recursive scan → snapshot diff → Tauri event emit |
| **Remote Apply** | *(Tauri command thread)* | Frontend calls `handle_remote_update` | Validates, writes/deletes file on disk |

The dual detection (watcher + poller) provides **near-instant event reporting with
guaranteed coverage**: the watcher catches changes in milliseconds, and the poller
fills any gaps from inotify queue overflows, atomic renames, or missed events.

Every detected local change is persisted to the sync database ([`sync_db.rs`](sync-db-module.md))
as a `LocalPending` item before the event is emitted to the frontend. This means
sync state survives both `stop()`/`start()` cycles and can be queried for pending
items after restart.

---

## Key Types

### `LiveSyncManager`

The central stateful manager. All mutable state is behind `std::sync::Mutex`:

| Field | Type | Purpose |
|-------|------|---------|
| `watcher` | `Mutex<Option<RecommendedWatcher>>` | Active `notify` filesystem watcher handle |
| `folder` | `Mutex<Option<PathBuf>>` | User-selected sync root directory path |
| `root_canonical` | `Mutex<Option<PathBuf>>` | Canonicalized root (for path traversal checks) |
| `worker` | `Mutex<Option<JoinHandle<()>>>` | Watcher background thread handle |
| `poller` | `Mutex<Option<JoinHandle<()>>>` | Poller background thread handle |
| `poll_stop` | `Mutex<Option<mpsc::Sender<()>>>` | Channel to signal poller to stop |
| `known_files` | `Arc<Mutex<HashMap<PathBuf, Instant>>>` | Shared suppression cache (anti-echo) |

**Lifecycle:** `Default::default()` → `start(app, folder)` → (running) → `stop()`.
Only one sync root at a time — calling `start()` again stops the previous one and
starts fresh.

### `LiveSyncEvent`

Serialized as JSON and emitted on the `"live-sync://local-change"` Tauri event
channel. The frontend sync engine depends on this exact channel name — changing it
would break the sync contract.

```rust
pub struct LiveSyncEvent {
    pub kind: String,                // "create" | "modify" | "remove"
    pub paths: Vec<String>,          // Absolute paths (backward compat)
    pub root_path: String,           // Sync root path
    pub relative_paths: Vec<String>, // Root-relative paths (for path mapping)
    pub source: String,              // "watcher" or "poller"
}
```

### `LiveSyncStatus`

Returned to the frontend for UI binding (sync toggle, folder display, interval display).

```rust
pub struct LiveSyncStatus {
    pub enabled: bool,
    pub folder_path: Option<String>,
    pub poll_interval_seconds: u64,  // defaults to 30
}
```

### `RemoteSyncChange`

Deserialized from the frontend when it pushes a remote change received from Proton Drive.
Uses `#[serde(rename_all = "camelCase")]` so the frontend sends `relativePath`,
`contentBase64`, etc.

```rust
pub struct RemoteSyncChange {
    pub relative_path: String,            // e.g. "Documents/report.pdf"
    pub action: String,                   // "create" | "update" | "delete"
    pub content_base64: Option<String>,   // Base64 content; required for create/update
}
```

---

## Change Detection Systems

### Watcher Thread

Uses the `notify` crate's `RecommendedWatcher` with `RecursiveMode::Recursive`:

```rust
let (tx, rx) = mpsc::channel();
let mut watcher = RecommendedWatcher::new(tx, Config::default())?;
watcher.watch(&folder, RecursiveMode::Recursive)?;
```

The worker thread (`live-sync-watcher`) blocks on `rx` and processes each event:
1. Maps `EventKind::Create(_)` → `"create"`, `Modify(_)` → `"modify"`, `Remove(_)` → `"remove"`
2. Filters paths through `should_ignore_known_file()` (anti-echo suppression)
3. Calls `emit_local_change()` which writes to the sync DB then emits the Tauri event

### Poller Thread

Acts as a safety net for events the watcher might miss:

1. Takes an initial baseline snapshot (`scan_sync_root()`)
2. Blocks on `poll_stop_rx.recv_timeout(poll_interval)` — this serves as both the stop signal and the timer
3. When the timeout fires (no stop signal received), takes a new snapshot
4. Calls `diff_snapshots(previous, next)` to find creates, modifies, and removes
5. Filters through the suppression cache
6. Calls `emit_local_change()` for each change
7. Replaces the baseline with the new snapshot and loops

```rust
let poller = std::thread::Builder::new()
    .name("live-sync-poller")
    .spawn(move || loop {
        if poll_stop_rx.recv_timeout(poll_interval).is_ok() { break; }
        scan_sync_root(&poller_root)
            .and_then(|next| diff_snapshots(&snapshot, &next))
            .map(|changes| emit_filtered_changes(...));
        snapshot = next_snapshot;
    })?;
```

### Snapshot Structure

```rust
struct FileFingerprint {
    len: u64,                       // File size in bytes
    modified: Option<u128>,         // mtime in nanoseconds since epoch
}

type SyncSnapshot = HashMap<PathBuf, FileFingerprint>;
```

The recursive scan walks the entire sync root tree, skipping symlinks, and records
`(size, mtime_ns)` for every file. The diff compares two snapshots using set
operations on the path keys:

- **Creates:** paths in `next` but not in `previous`
- **Modifies:** paths in both but fingerprint changed
- **Removes:** paths in `previous` but not in `next`

---

## Anti-Echo / Self-Suppression

When a remote change is applied to the local filesystem, the local watcher immediately
detects the write. Without suppression, this would trigger an upload back to Proton,
creating an infinite loop.

### Known Files Cache

| Property | Value |
|----------|-------|
| **Storage** | `HashMap<PathBuf, Instant>` behind `Arc<Mutex<...>>` |
| **TTL** | 30 seconds (`SUPPRESSION_TTL`) |
| **Max entries** | 4096 (`SUPPRESSION_CACHE_MAX`) |
| **Pruning** | Time-based on every access; capacity-based overflow evicts oldest |
| **Consumed on read** | `cache.remove(path)` — one suppression per mark |

### Flow

```
apply_remote_change()
  → mark_known_file(path)           ← inserts path + Instant::now()
  → fs::write / fs::remove_file
  → notify watcher fires (same path)
    → should_ignore_known_file(path)
      → If found AND age ≤ 30s → SUPPRESS (remove entry, return true)
      → Otherwise → return false → emit event
```

The entry is **consumed on first lookup** (`cache.remove()`), not on a timer. This
means one remote write suppresses exactly one detection event. If the file watcher
fires multiple times (e.g., create + modify events for the same write), only the
first is suppressed — but in practice these arrive in the same batch and the
suppression covers both since the entry has already been consumed.

---

## Metadata Persistence

Every local change is recorded in the sync database via `record_local_change_metadata()`:

```rust
fn record_local_change_metadata(
    db_path: &Path, root_id: &str, root: &Path, kind: &str, paths: &[String]
) -> Result<(), String> {
    for path in paths {
        if kind == "remove" {
            db.mark_tombstone(root_id, &relative)?;  // soft-delete, preserves remote ID
        } else {
            let metadata = fs::symlink_metadata(path).ok();
            db.upsert_local_item(root_id, &relative, local_kind, local_size,
                local_mtime_ns, None, SyncItemState::LocalPending)?;
        }
    }
}
```

This is what connects the live sync engine to the persistent metadata layer. Without
it, changes would be ephemeral — the frontend would receive events but there'd be no
record of what needs uploading.

---

## Remote Change Application

The frontend calls `handle_remote_update` (a Tauri command) when Proton pushes a
file change:

```
Frontend receives remote change from Proton
  → invoke('handle_remote_update', { change: RemoteSyncChange })
    → ensure_sync_command_allowed()    (origin check: must be tauri://localhost)
    → apply_remote_change(change)
      → Reject "create"/"update" without content_base64
      → Validate relative_path: no "..", "/", or Prefix components
      → Validate target within canonical root (symlink traversal check)
      → For create/update: fs::create_dir_all(parent) → mark_known_file → fs::write
      → For delete: mark_known_file → fs::remove_file (if exists)
```

### Path Validation

`validate_path_within_root` provides three-layer protection:

1. **Component-level symlink check** — walks each path component and rejects any symlink
2. **Canonicalization** — resolves the target (or nearest ancestor) and checks it starts with the sync root
3. **Non-existent path handling** — when the target doesn't exist (pending remote create), walks ancestors to find one for canonical comparison

```rust
pub fn validate_path_within_root(root_canonical: &Path, target: &Path) -> Result<(), String> {
    let mut cur = PathBuf::new();
    for component in target.components() {
        cur.push(component.as_os_str());
        if let Ok(meta) = fs::symlink_metadata(&cur) {
            if meta.file_type().is_symlink() {
                return Err("symlink traversal is not allowed".into());
            }
        }
    }
    // ... canonicalization check for root escape ...
}
```

---

## Sync Command Authorization

All sync commands (`start_sync`, `stop_sync`, `get_sync_status`,
`handle_remote_update`, `read_sync_file`, `set_sync_root`) are gated behind an
origin check in `main.rs`:

```rust
fn ensure_sync_command_allowed(window: &tauri::WebviewWindow) -> Result<(), String> {
    let current_url = window.url().map_err(|e| {
        eprintln!("[Sync] failed to read window URL: {e}");
        ERR_SYNC_NOT_ALLOWED.to_string()
    })?;

    let host = current_url.host_str().unwrap_or_default();
    let is_allowed =
        current_url.scheme() == "tauri" && (host == "localhost" || host == "tauri.localhost");

    if !is_allowed {
        eprintln!(
            "[Sync] rejected command from origin scheme={} host={}",
            current_url.scheme(),
            host
        );
        return Err(ERR_SYNC_NOT_ALLOWED.to_string());
    }

    Ok(())
}
```

This prevents the CAPTCHA verification page (`verify.proton.me`) from invoking sync
commands while the user is mid-authentication.

---

## Error Handling

All user-facing error strings are compile-time constants with `[LiveSync]` log prefixes:

| Constant | Message | Triggers |
|----------|---------|----------|
| `ERR_SYNC_SETUP_FAILED` | "Failed to start live sync" | Watcher init, path canonicalization, thread spawn |
| `ERR_SYNC_STATE_UNAVAILABLE` | "Live sync is temporarily unavailable" | Any mutex lock failure |
| `ERR_SYNC_NOT_ACTIVE` | "Live sync is not active" | Remote change while sync not running |
| `ERR_SYNC_INVALID_REMOTE_CONTENT` | "Invalid remote file content" | Base64 decode failure |
| `ERR_SYNC_WRITE_FAILED` | "Failed to apply remote file update" | fs::write or fs::create_dir_all failure |
| `ERR_SYNC_DELETE_FAILED` | "Failed to apply remote file deletion" | fs::remove_file failure |
| `ERR_SYNC_INVALID_TARGET` | "Invalid sync target path" | Path traversal or symlink in path |

All audit-relevant events (remote write/delete accepted or rejected) are logged with
`[LiveSync][AUDIT]` prefix.

---

## Configuration Constants

Hardcoded at the top of `live_sync.rs`:

| Constant | Value | Purpose |
|----------|-------|---------|
| `SUPPRESSION_TTL` | `Duration::from_secs(30)` | Suppression window after remote write |
| `SUPPRESSION_CACHE_MAX` | `4096` | Maximum entries before oldest evicted |
| `DEFAULT_SYNC_POLL_INTERVAL` | `Duration::from_secs(30)` | Poller check interval |

No runtime configuration is exposed — these are compile-time constants.

## Troubleshooting

### Sync Never Starts (Poller Not Running)

**Symptoms:** Console shows `[Sync] active enabled=true` but no poll cycles appear. Files never sync.

**Causes:**
- Watcher thread panicked during event processing and the `JoinHandle` was dropped
- Sync root path validation failed (path doesn't exist, is a symlink to nowhere, or is on a network mount)
- Disk is full — inotify can't create watches

**Fix:**
1. Check the console for `[Sync]` prefixed errors
2. Verify the sync root exists: `ls -d ~/ProtonDrive/`
3. Check disk space: `df -h ~/ProtonDrive/`
4. Check inotify watch limit (Linux): `cat /proc/sys/fs/inotify/max_user_watches` — if you have many files, increase it: `echo 524288 | sudo tee /proc/sys/fs/inotify/max_user_watches`

### Files Not Appearing After Remote Changes

**Symptoms:** Files added via the Proton Drive web app never appear locally.

**Causes:**
- Poller interval hasn't elapsed yet (30s default)
- Network connectivity to `drive-api.proton.me` is broken
- The remote scope changed (e.g. file moved from "My Files" to "Computers")

**Fix:**
1. Wait 30+ seconds for the next poll cycle
2. Check network: `curl -I https://drive-api.proton.me`
3. Verify the file is in the same scope your sync root tracks (check the Proton web UI)

### Suppression Cache Prevents Local Changes

**Symptoms:** You modify a file locally, but it doesn't upload. Console shows no `ChangeDetected` event.

**Causes:**
- The suppression cache still holds the file's hash from the last remote download
- The file was downloaded <60s ago and the suppression window hasn't expired
- The file content hasn't actually changed (same hash)

**Fix:**
1. Wait 60s for the suppression cache entry to expire
2. Force a change: `touch` the file and append a byte: `echo " " >> file.txt`
3. Restart the app to flush the suppression cache

### Poller Reports Stale Events

**Symptoms:** The same file syncs repeatedly. Console shows repeated `RemoteChange` for the same file.

**Causes:**
- The file's modification time is in the future (Proton API returns future timestamps)
- The suppression cache hash calculation is non-deterministic
- The file is being modified by an external process at the same time the poller reads it

**Fix:**
1. Check file timestamp: `stat file.txt` — if it's in the future, fix with `touch file.txt`
2. Exclude the file from the sync root if it's being modified by another process (logs, caches, etc.)

## See Also

- **[Sync System](sync-system.md)** — Full sync architecture: Tauri command wiring, lifecycle flows, startup path, device name resolution
- **[Sync Database](sync-database.md)** — SQLite schema, item states, privacy hashing, migration strategy
- **[Sync DB Module](sync-db-module.md)** — The `sync_db.rs` integration: AppState wiring, SyncKeyring decryption, debounce/persistence constants
- **[WebView Integration](webview-integration.md)** — How the frontend connects to sync commands, origin gating

---

## Limitations

1. **No conflict resolution** — last-write-wins, remote always overrides local when both change
2. **No retry queue** — transient write/decode failures are returned to the frontend immediately
3. **No file exclusion patterns** — entire folder is watched recursively
4. **No initial state reconciliation at start** — sync only tracks changes after `start()`. The persistent DB records changes but the engine does not yet compare local files against remote on startup.
5. **Blocking Mutex** — `std::sync::Mutex` can block the async Tauri runtime under contention
6. **Single sync root** — only one folder at a time
7. **Unidirectional local events** — Rust emits events and records metadata; the frontend is responsible for upload
8. **File size limit for sync bridge** — Files over 100 MB (`MAX_SYNC_BRIDGE_FILE_BYTES`) are rejected by `read_sync_file` (the Tauri command that reads local files for upload)
