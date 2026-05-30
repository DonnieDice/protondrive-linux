# Live Sync System

The sync system watches a local folder for changes and synchronizes them with Proton Drive. It has two independent change detection mechanisms, a suppression cache to prevent feedback loops, a remote-apply pipeline, and a SQLite-backed state tracker.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    LiveSyncManager                       │
│                                                         │
│  ┌───────────────────┐    ┌─────────────────────────┐   │
│  │  inotify Watcher  │    │  Polling Comparator      │   │
│  │  (notify crate)   │    │  (scan + diff, 30s)     │   │
│  │  OS-level events  │    │  baseline snapshot diff  │   │
│  │  near-instant     │    │  fallback coverage       │   │
│  └───────┬───────────┘    └───────────┬─────────────┘   │
│          │                           │                  │
│          └───────────┬───────────────┘                  │
│                      ▼                                  │
│          ┌───────────────────────┐                      │
│          │  Suppression Cache    │                      │
│          │  (known_files)        │  ← Prevents feedback │
│          │  Arc<Mutex<HashMap>>  │    loops             │
│          │  TTL: 30s             │                      │
│          │  Max: 4096 entries    │                      │
│          └───────────┬───────────┘                      │
│                      ▼                                  │
│          ┌───────────────────────┐                      │
│          │  emit_local_change()  │                      │
│          │  - Records to sync DB │                      │
│          │  - Emits Tauri event  │                      │
│          └───────────┬───────────┘                      │
│                      │                                  │
│                      ▼                                  │
│          ┌───────────────────────┐                      │
│          │  Frontend receives    │                      │
│          │  live-sync://         │  → Proton SPA handles│
│          │  local-change event   │    upload            │
│          └───────────────────────┘                      │
│                                                         │
│  Remote change path (frontend → local):                 │
│                                                         │
│  ┌───────────────────────┐                              │
│  │  handle_remote_update │  ← Called by frontend        │
│  │  (Tauri command)      │    when Proton sends changes │
│  └───────────┬───────────┘                              │
│              ▼                                          │
│  ┌───────────────────────┐                              │
│  │  apply_remote_change  │                              │
│  │  - Validates paths    │                              │
│  │  - Marks known_file   │  ← Suppress watcher/poller   │
│  │  - Writes/deletes     │                              │
│  └───────────────────────┘                              │
└─────────────────────────────────────────────────────────┘
```

## Why two detection systems?

**The inotify watcher** (`notify` crate, `RecommendedWatcher`) gets near-instant events from the OS when files change. **But it's unreliable** — inotify can miss events under heavy I/O, when the watcher queue overflows, or with certain filesystem operations (atomic renames, network mounts).

**The polling comparator** runs every 30 seconds and does a full recursive scan of the sync root. It computes a `HashMap<PathBuf, FileFingerprint>` snapshot and diffs it against the previous snapshot. This catches any changes the watcher missed.

Together, they provide **near-instant detection with guaranteed coverage**.

## Dual change detection in detail

### Watcher thread (`live-sync-watcher`)

```rust
let mut watcher = RecommendedWatcher::new(tx, Config::default())?;
watcher.watch(&folder, RecursiveMode::Recursive)?;

let worker = std::thread::Builder::new()
    .name("live-sync-watcher")
    .spawn(move || {
        for res in rx {
            match res {
                Ok(event) => {
                    let kind = match event.kind {
                        EventKind::Create(_) => "create",
                        EventKind::Modify(_) => "modify",
                        EventKind::Remove(_) => "remove",
                        _ => continue,
                    };

                    let mut filtered_paths = Vec::new();
                    for path in event.paths {
                        if should_ignore_known_file(&known_files, &path) {
                            continue;
                        }
                        filtered_paths.push(path.to_string_lossy().to_string());
                    }

                    if !filtered_paths.is_empty() {
                        emit_local_change(app_handle, db_path, root_id, root,
                            kind, filtered_paths, "watcher");
                    }
                }
                Err(_) => eprintln!("[LiveSync] Watcher error occurred"),
            }
        }
    })?;
```

### Poller thread (`live-sync-poller`)

```rust
let poller = std::thread::Builder::new()
    .name("live-sync-poller")
    .spawn(move || loop {
        if poll_stop_rx.recv_timeout(poll_interval).is_ok() {
            break;
        }

        match scan_sync_root(&poller_root) {
            Ok(next_snapshot) => {
                for (kind, paths) in diff_snapshots(&snapshot, &next_snapshot) {
                    let filtered_paths = paths
                        .into_iter()
                        .filter(|path| !should_ignore_known_file(&known_files, path))
                        .collect();

                    if !filtered_paths.is_empty() {
                        emit_local_change(app_handle, db_path, root_id, root,
                            kind, filtered_paths, "poller");
                    }
                }
                snapshot = next_snapshot;
            }
            Err(e) => eprintln!("[LiveSync] poller scan failed: {e}"),
        }
    })?;
```

The poller uses `recv_timeout(poll_interval)` as its timer — it blocks waiting for a stop signal, but if none arrives within the interval, it runs a scan. This is cleaner than separate sleep+timer logic.

### Snapshot structure

```rust
struct FileFingerprint {
    len: u64,                           // File size in bytes
    modified: Option<u128>,             // mtime in nanoseconds since epoch
}

type SyncSnapshot = HashMap<PathBuf, FileFingerprint>;
```

The recursive scan walks the entire sync root tree, skipping symlinks, and records `(size, mtime_ns)` for every file:

```rust
fn scan_sync_dir(dir: &Path, snapshot: &mut SyncSnapshot) -> io::Result<()> {
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        let meta = fs::symlink_metadata(&path)?;

        if meta.file_type().is_symlink() { continue; }
        if meta.is_dir() { scan_sync_dir(&path, snapshot)?; }
        else if meta.is_file() {
            snapshot.insert(path, FileFingerprint {
                len: meta.len(),
                modified: meta.modified().ok().and_then(system_time_nanos),
            });
        }
    }
    Ok(())
}
```

### Snapshot diffing

```rust
fn diff_snapshots(previous: &SyncSnapshot, next: &SyncSnapshot)
    -> Vec<(&'static str, Vec<PathBuf>)>
{
    let prev_paths: HashSet<&PathBuf> = previous.keys().collect();
    let next_paths: HashSet<&PathBuf> = next.keys().collect();

    // Creates: in next but not in previous
    for path in next_paths.difference(&prev_paths) {
        creates.push((*path).clone());
    }

    // Modifies: in both but fingerprint changed
    for path in prev_paths.intersection(&next_paths) {
        if previous.get(*path) != next.get(*path) {
            modifies.push((*path).clone());
        }
    }

    // Removes: in previous but not in next
    for path in prev_paths.difference(&next_paths) {
        removes.push((*path).clone());
    }
}
```

## Suppression cache (feedback loop prevention)

The biggest challenge in a local sync system is the **echo problem**: when you write a file the remote sent, the local watcher fires and tries to upload it back. The suppression cache prevents this.

### How it works

1. Before writing a file from a remote change, `mark_known_file(path)` adds it to the cache with the current `Instant`
2. When the watcher or poller detects a change, `should_ignore_known_file(path)` checks if it's in the cache
3. If it IS in the cache and was added within the last `SUPPRESSION_TTL` (30 seconds), the change is suppressed
4. The entry is **consumed** on lookup (`.remove(path)`) — it suppresses exactly one detection per marked write

```rust
fn should_ignore_known_file(
    known_files: &Arc<Mutex<HashMap<PathBuf, Instant>>>,
    path: &Path,
) -> bool {
    if let Ok(mut cache) = known_files.lock() {
        let now = Instant::now();
        prune_known_files(&mut cache, now);
        if let Some(marked_at) = cache.remove(path) {
            return now.saturating_duration_since(marked_at) <= SUPPRESSION_TTL;
        }
        false
    } else {
        false
    }
}
```

### Bounds & pruning

The cache has two safety mechanisms:

```rust
const SUPPRESSION_TTL: Duration = Duration::from_secs(30);
const SUPPRESSION_CACHE_MAX: usize = 4096;

fn prune_known_files(cache: &mut HashMap<PathBuf, Instant>, now: Instant) {
    // 1. Remove expired entries
    cache.retain(|_, marked_at| now.saturating_duration_since(*marked_at) <= SUPPRESSION_TTL);

    // 2. If still over capacity, drop oldest
    if cache.len() > SUPPRESSION_CACHE_MAX {
        let mut by_age: Vec<(PathBuf, Instant)> = cache.iter()
            .map(|(p, t)| (p.clone(), *t)).collect();
        by_age.sort_by_key(|(_, t)| *t);
        let overflow = by_age.len() - SUPPRESSION_CACHE_MAX;
        for (path, _) in by_age.into_iter().take(overflow) {
            cache.remove(&path);
        }
    }
}
```

## Remote change application

The frontend calls `handle_remote_update` when Proton pushes a file change:

```rust
#[tauri::command]
fn handle_remote_update(
    window: WebviewWindow,
    state: State<'_, Arc<AppState>>,
    change: RemoteSyncChange,
) -> Result<String, String> {
    ensure_sync_command_allowed(&window)?;
    state.sync_manager.apply_remote_change(change)
}
```

### The `RemoteSyncChange` struct

```rust
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteSyncChange {
    pub relative_path: String,      // e.g., "Pictures/photo.jpg"
    pub action: String,             // "create", "update", "delete"
    pub content_base64: Option<String>,  // Base64-encoded file content
}
```

The `#[serde(rename_all = "camelCase")]` means the frontend sends JSON like:

```json
{
    "relativePath": "Documents/report.pdf",
    "action": "update",
    "contentBase64": "JVBERi0xLjQK..."
}
```

### Apply logic

```rust
pub fn apply_remote_change(&self, change: RemoteSyncChange) -> Result<String, String> {
    // Validate: no empty paths, no path traversal, no symlinks
    let relative = Path::new(&change.relative_path);
    validate_path_within_root(&canonical_root, &target)?;

    match change.action.as_str() {
        "create" | "update" => {
            // Decode base64 content
            let data = base64::engine::general_purpose::STANDARD
                .decode(change.content_base64.ok_or("Invalid remote update payload")?)?;

            // Create parent directories
            if let Some(parent) = target.parent() {
                fs::create_dir_all(parent)?;
            }

            // Mark to suppress local watcher + write
            self.mark_known_file(&target)?;
            fs::write(&target, data)?;
        }
        "delete" => {
            if target.exists() {
                self.mark_known_file(&target)?;
                fs::remove_file(&target)?;
            }
        }
        _ => return Err("Unknown action".into()),
    }
    Ok(target.to_string_lossy().to_string())
}
```

## Path validation

### Sync root validation

The sync root must be under the user's home directory:

```rust
fn validate_sync_root_path(path: &str) -> Result<PathBuf, String> {
    let canonical = PathBuf::from(path).canonicalize()?;
    let home = dirs::home_dir().ok_or("Invalid sync folder")?;
    if !canonical.starts_with(&home) {
        return Err("Invalid sync folder".to_string());
    }
    Ok(canonical)
}
```

### Relative path validation

```rust
fn validate_sync_relative_path(path: &str) -> Result<PathBuf, String> {
    let relative = Path::new(path);
    if relative.as_os_str().is_empty() || relative.is_absolute() {
        return Err("Invalid sync path".into());
    }

    let mut clean = PathBuf::new();
    for component in relative.components() {
        match component {
            Component::Normal(part) => clean.push(part),
            _ => return Err("Invalid sync path".into()), // No RootDir, ParentDir, Prefix
        }
    }
    Ok(clean)
}
```

### Symlink traversal prevention

The `validate_path_within_root` function walks each path component and rejects any symlink:

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

This is a defense-in-depth measure — even if path traversal checks pass, a symlink could still point outside the sync root. The component-level symlink check catches this.

### For non-existent paths

When applying a remote "create" change, the target file doesn't exist yet. The validation walks up to the nearest existing ancestor and checks that it's inside the sync root:

```rust
if !target.exists() {
    let existing_ancestor = find_existing_ancestor(target)?;
    let canonical_ancestor = existing_ancestor.canonicalize()?;
    if !canonical_ancestor.starts_with(root_canonical) {
        return Err("target escapes sync root".into());
    }
    return Ok(());
}
```

## Tauri event bridge

Local changes are emitted as Tauri events for the frontend to consume:

```rust
#[derive(Serialize)]
pub struct LiveSyncEvent {
    pub kind: String,              // "create", "modify", "remove"
    pub paths: Vec<String>,        // Absolute paths (backward compat)
    pub root_path: String,         // Sync root path
    pub relative_paths: Vec<String>, // Root-relative paths (for mapping)
    pub source: String,            // "watcher" or "poller"
}

app_handle.emit("live-sync://local-change", LiveSyncEvent { ... })?;
```

The event name `live-sync://local-change` is part of a contract with the frontend sync engine — changing it would break the connection.

## Sync command authorization

All sync commands (start, stop, status, remote update, file read) are gated behind an origin check:

```rust
fn ensure_sync_command_allowed(window: &WebviewWindow) -> Result<(), String> {
    let current_url = window.url()?;
    let host = current_url.host_str().unwrap_or_default();
    let is_allowed = current_url.scheme() == "tauri"
        && (host == "localhost" || host == "tauri.localhost");

    if !is_allowed {
        return Err("Live sync is unavailable from this page".into());
    }
    Ok(())
}
```

This prevents external pages (like `verify.proton.me`) from accessing sync commands.

## Sync root lifecycle

### Default sync root

```rust
const DEFAULT_SYNC_ROOT_DIR: &str = "ProtonDrive";
// Resolves to ~/ProtonDrive
```

### Startup auto-start

```rust
// Priority 1: PROTONDRIVE_AUTO_SYNC_PATH env var (for CI/testing)
if let Ok(path) = std::env::var("PROTONDRIVE_AUTO_SYNC_PATH") {
    validate_sync_root_path(&path)
        .and_then(|sync_root| {
            persist_selected_sync_root(&app_data_dir, &sync_root)?;
            start_selected_sync_root(app.handle(), &state, &sync_root.to_string_lossy(), "env")
        })
} else {
    // Priority 2: Default ~/ProtonDrive
    ensure_default_sync_root()
        .and_then(|sync_root| {
            persist_selected_sync_root(&app_data_dir, &sync_root)?;
            start_selected_sync_root(app.handle(), &state, &sync_root.to_string_lossy(), "default")
        })
}
```

### Persistence

The selected sync root is stored in `{app_data_dir}/sync-root.txt` with `0o600` permissions. The root is also registered in the sync database as a `computers` scope root with device metadata.

### Stop sequence

```rust
pub fn stop(&self) -> Result<(), String> {
    // 1. Send stop signal to poller
    if let Some(poll_stop) = self.poll_stop.lock()?.take() {
        let _ = poll_stop.send(());
    }

    // 2. Drop watcher (joins watcher thread on drop)
    *self.watcher.lock()? = None;

    // 3. Clear folder state
    *self.folder.lock()? = None;
    *self.root_canonical.lock()? = None;

    // 4. Join worker thread
    if let Some(worker) = self.worker.lock()?.take() {
        let _ = worker.join();
    }

    // 5. Join poller thread
    if let Some(poller) = self.poller.lock()?.take() {
        let _ = poller.join();
    }

    // 6. Clear suppression cache
    self.known_files.lock()?.clear();

    Ok(())
}
```

## Device name resolution

```rust
fn machine_name_for_sync() -> String {
    std::env::var("HOSTNAME")
        .ok()
        .filter(|v| !v.trim().is_empty())
        .or_else(|| fs::read_to_string("/etc/hostname").ok())
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty())
        .unwrap_or_else(|| "Linux-PC".to_string())
}
```

The device name is sanitized to 64 characters of `[a-zA-Z0-9\-_.]`.

## File read for upload bridge

The `read_sync_file` command is the **zero-trust local-to-remote bridge**. When the Proton SPA wants to upload a local file to the cloud, it calls this command instead of reading the file directly:

```rust
#[tauri::command]
fn read_sync_file(
    window: WebviewWindow,
    state: State<'_, Arc<AppState>>,
    root_path: String,
    relative_path: String,
) -> Result<SyncFilePayload, String> {
    // 1. Verify sync is active
    // 2. Verify root_path matches active sync root (canonical comparison)
    // 3. Validate relative path (no traversal)
    // 4. Verify path is within sync root
    // 5. Verify file exists, is a regular file (not symlink)
    // 6. Verify size <= MAX_SYNC_BRIDGE_FILE_BYTES
    // 7. Read file, base64-encode, return as SyncFilePayload
}
```

The returned `SyncFilePayload` contains `relative_path`, `name`, `size`, `modified_ms`, and `content_base64`.

## Troubleshooting

### `Invalid sync folder` Error

**Symptoms:** Console shows `[Sync] Invalid sync folder` when trying to set a sync root.

**Causes:**
- Path doesn't exist or isn't a directory
- Path is a symlink to a non-existent target
- Path is outside `$HOME` (the validator rejects paths not under `$HOME`)
- Path is on a network mount (NFS, CIFS) that tricks `is_dir()` into returning false

**Fix:**
```bash
# Verify the path exists and is a real directory
ls -ld /path/to/sync/root

# Resolve any symlinks
readlink -f /path/to/sync/root

# Must be under $HOME
echo $HOME
```

### `sync-root.txt` Not Persisting

**Symptoms:** Sync root resets to `~/ProtonDrive` after restart despite setting a custom path.

**Causes:**
- `app_data_dir` doesn't exist or isn't writable
- File permissions on `sync-root.txt` were set too restrictive and `read_selected_sync_root` returns `None`
- The `set_sync_root` command was called but the write to `sync-root.txt` silently failed

**Fix:**
```bash
# Check the file
cat ~/.local/share/com.proton.drive/sync-root.txt

# Verify permissions
ls -la ~/.local/share/com.proton.drive/sync-root.txt
# Should be -rw------- (0600)

# If missing, create it manually
echo "/home/user/custom/path" > ~/.local/share/com.proton.drive/sync-root.txt
chmod 600 ~/.local/share/com.proton.drive/sync-root.txt
```

### Sync Bridge File Too Large

**Symptoms:** Console shows a file rejected with size > 100MB. File never uploads.

**Cause:** `MAX_SYNC_BRIDGE_FILE_BYTES` (100 MiB) is exceeded. The sync bridge between WebView and Rust has a size limit for files passed through IPC.

**Fix:** The file must be under 100 MiB. This is a hard compile-time limit. For larger files, use the Proton Drive web interface directly, or rebuild with a higher `MAX_SYNC_BRIDGE_FILE_BYTES` constant.

## See Also

- **[Live Sync Module](live-sync-module.md)** — Core engine: watcher/poller threads, suppression cache, event contract
- **[Sync Database](sync-database.md)** — SQLite schema, item states, privacy hashing
- **[Sync DB Module](sync-db-module.md)** — `sync_db.rs` integration, SyncKeyring, AppState wiring
- **[WebView Integration](../webview/webview-integration.md)** — Frontend sync command wiring, origin gating
