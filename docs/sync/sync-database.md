# Sync Database

The sync database is a SQLite file at `{app_data_dir}/sync-state.sqlite3` that tracks every file in the sync root, its sync state, and its relationship to remote Proton Drive items. All sensitive data (paths, remote IDs, device names) is stored as SHA-256 hashes.

## Schema

```sql
-- Metadata key-value store for schema versioning
CREATE TABLE IF NOT EXISTS sync_meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- One row per sync root (folder being synced)
CREATE TABLE IF NOT EXISTS sync_roots (
    id                          TEXT PRIMARY KEY,         -- SHA-256 of root path
    root_path_hash              TEXT NOT NULL,             -- SHA-256 of root path (for verification)
    remote_scope                TEXT NOT NULL DEFAULT 'unmapped',  -- 'unmapped', 'computers', 'my_files'
    device_type                 TEXT,                      -- 'linux' for computers scope
    device_name_hash            TEXT,                      -- SHA-256 of sanitized hostname
    remote_device_uid_hash      TEXT,                      -- SHA-256 of Proton device UID
    remote_root_folder_uid_hash TEXT,                      -- SHA-256 of Proton root folder UID
    remote_share_id_hash        TEXT,                      -- SHA-256 of Proton share ID
    remote_path_hash            TEXT,                      -- SHA-256 of remote path (my_files only)
    created_at_ns               INTEGER NOT NULL,          -- Unix nanoseconds
    updated_at_ns               INTEGER NOT NULL
);

-- One row per file/folder in a sync root
CREATE TABLE IF NOT EXISTS sync_items (
    root_id              TEXT NOT NULL,         -- FK to sync_roots.id
    relative_path_hash   TEXT NOT NULL,         -- SHA-256 of relative path within root
    local_kind           TEXT NOT NULL,         -- 'file', 'dir', 'unknown'
    local_size           INTEGER,              -- File size in bytes (null for dirs)
    local_mtime_ns       INTEGER,              -- mtime in nanoseconds (null if unknown)
    content_hash         TEXT,                  -- Optional content fingerprint (not currently used)
    remote_volume_id_hash TEXT,                 -- SHA-256 of Proton volume ID
    remote_share_id_hash TEXT,                  -- SHA-256 of Proton share ID
    remote_link_id_hash  TEXT,                  -- SHA-256 of Proton link ID
    remote_parent_id_hash TEXT,                 -- SHA-256 of Proton parent folder ID
    remote_revision_hash TEXT,                  -- SHA-256 of Proton revision/etag
    state                TEXT NOT NULL,         -- See SyncItemState below
    last_seen_local_ns   INTEGER,              -- Last time file was observed locally
    last_seen_remote_ns  INTEGER,              -- Last time remote item was linked
    tombstoned_at_ns     INTEGER,              -- When item was deleted (for tombstone GC)
    retry_count          INTEGER NOT NULL DEFAULT 0,  -- For future retry logic
    last_error_code      TEXT,                 -- For future error tracking
    created_at_ns        INTEGER NOT NULL DEFAULT 0,
    updated_at_ns        INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(root_id, relative_path_hash),
    FOREIGN KEY(root_id) REFERENCES sync_roots(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_sync_items_state
    ON sync_items(root_id, state, updated_at_ns);
```

## Item states

The `SyncItemState` enum defines the lifecycle of a sync item:

```rust
enum SyncItemState {
    Synced,          // Matched with remote, no pending changes
    LocalPending,    // Local change detected, needs upload
    RemotePending,   // Remote change applied, frontend needs to acknowledge
    Tombstone,       // Local file was deleted, delete needs to be synced
    Conflict,        // Both local and remote changed
}
```

| State | Meaning | How entered | How exited |
|-------|---------|-------------|------------|
| `synced` | File matches remote | Initial state after remote link | Replaced by `local_pending` or `remote_pending` when change detected |
| `local_pending` | Upload needed | Watcher/poller detected local create/modify | (Frontend responsibility — upload, then update state) |
| `remote_pending` | Download/apply pending | Remote change received, file written locally | (Frontend responsibility — acknowledge, then update state) |
| `tombstone` | File was deleted | `record_local_change_metadata(kind="remove")` | (Frontend responsibility — delete remote, then remove row) |
| `conflict` | Both sides changed | (Not yet implemented in current code — reserved for future) | Resolution logic |

## Root scopes

There are three kinds of sync roots, identified by `remote_scope`:

| Scope | Values | Used for | Created by |
|-------|--------|----------|------------|
| `unmapped` | Default | Generic root before scope is assigned | `upsert_root()` |
| `computers` | Has `device_type` + `device_name_hash` | Default `~/ProtonDrive` sync | `upsert_computers_root()` |
| `my_files` | Has `remote_path_hash` | User-selected remote folder mapping | `upsert_my_files_mapping()` |

## Privacy model

**Every path, filename, and remote ID is stored as a SHA-256 hash.** The raw values never appear in the database file.

```rust
pub fn hash_sensitive(value: impl AsRef<str>) -> String {
    let mut hasher = Sha256::new();
    hasher.update(value.as_ref().as_bytes());
    hex::encode(hasher.finalize())
}
```

The test suite verifies this:

```rust
#[test]
fn stores_metadata_without_raw_paths_or_remote_ids() {
    // ...
    let bytes = fs::read(&db_path).unwrap();
    let db_file = String::from_utf8_lossy(&bytes);
    assert!(!db_file.contains("private-vacation"));
    assert!(!db_file.contains("/home/alice"));
    assert!(!db_file.contains("alice-laptop"));
    assert!(!db_file.contains("link-secret"));
    assert!(!db_file.contains("share-secret"));
}
```

### What's hashed vs. what isn't

| Column | Hashed? | Reason |
|--------|---------|--------|
| `root_path_hash` | Yes | Contains user's home directory path |
| `relative_path_hash` | Yes | Contains filenames and folder structure |
| `device_name_hash` | Yes | Contains hostname |
| `remote_volume_id_hash` | Yes | Proton internal ID |
| `remote_share_id_hash` | Yes | Proton internal ID |
| `remote_link_id_hash` | Yes | Proton internal ID |
| `remote_parent_id_hash` | Yes | Proton internal ID |
| `remote_revision_hash` | Yes | Proton revision/etag |
| `remote_path_hash` | Yes | Remote folder path |
| `remote_device_uid_hash` | Yes | Proton device UID |
| `remote_root_folder_uid_hash` | Yes | Proton root folder UID |
| `local_size` | No | Just a number |
| `local_mtime_ns` | No | Just a timestamp |
| `local_kind` | No | "file" or "dir" |
| `state` | No | Sync state enum |
| Timestamps (`*_ns`) | No | Metadata, not content-derived |

### File permissions

The database file and its parent directory are created with restrictive permissions:

```rust
// Directory: 0o700 (rwx------)
// Database file: 0o600 (rw-------)
// Sync root config file: 0o600
```

This prevents other users on the system from reading sync state.

## Database operations

### Root management

```rust
// Generic upsert — preserves existing scope if already set
db.upsert_root(path) -> root_id

// Computers scope — stores device info, no remote path
db.upsert_computers_root(path, device_name, device_type) -> root_id

// My Files mapping — stores remote path, no device info
db.upsert_my_files_mapping(path, remote_path) -> root_id
```

All three compute `root_id = hash_sensitive(path.to_string_lossy())`, so the same path always gets the same root ID.

### Item tracking

```rust
// Record local file metadata
db.upsert_local_item(root_id, relative_path, local_kind, local_size,
                     local_mtime_ns, content_hash, state) -> relative_path_hash

// Link a remote Proton item to a local file
db.link_remote_item(root_id, relative_path, RemoteItemRef {
    volume_id, share_id, link_id, parent_id, revision
})

// Mark an item as deleted (tombstone)
db.mark_tombstone(root_id, relative_path) -> bool  // true if item existed

// Read a single item
db.get_item(root_id, relative_path) -> Option<SyncItemRecord>

// List pending items (local_pending, remote_pending, conflict, tombstone)
db.pending_items(root_id) -> Vec<SyncItemRecord>
```

### Tombstone logic

A tombstone is only created if the item exists in a known state:

```sql
UPDATE sync_items SET
    state = 'tombstone',
    tombstoned_at_ns = ?,
    updated_at_ns = ?
WHERE root_id = ?
  AND relative_path_hash = ?
  AND state IN ('synced', 'local_pending', 'remote_pending')
```

The `WHERE state IN (...)` clause ensures we don't tombstone items that are already tombstones, or items in states that shouldn't produce a delete sync (`conflict`, etc.).

### Pending items query

```sql
SELECT ... FROM sync_items
WHERE root_id = ?
  AND state IN ('local_pending', 'remote_pending', 'conflict', 'tombstone')
ORDER BY updated_at_ns ASC
```

This is the query the frontend uses to find items that need syncing. The `ORDER BY updated_at_ns ASC` ensures FIFO processing.

## Schema migration

The `migrate()` method handles both initial creation and incremental upgrades:

```rust
fn migrate(&self) -> Result<(), String> {
    // 1. Create tables if they don't exist (IF NOT EXISTS)
    self.conn.execute_batch("CREATE TABLE IF NOT EXISTS ...");

    // 2. Add columns that may have been added in newer versions
    ensure_column(&self.conn, "sync_roots", "remote_scope", "TEXT NOT NULL DEFAULT 'unmapped'")?;
    ensure_column(&self.conn, "sync_roots", "device_type", "TEXT")?;
    ensure_column(&self.conn, "sync_roots", "device_name_hash", "TEXT")?;
    ensure_column(&self.conn, "sync_roots", "remote_device_uid_hash", "TEXT")?;
    ensure_column(&self.conn, "sync_roots", "remote_root_folder_uid_hash", "TEXT")?;
    ensure_column(&self.conn, "sync_roots", "remote_share_id_hash", "TEXT")?;
    ensure_column(&self.conn, "sync_roots", "remote_path_hash", "TEXT")?;

    // 3. Upsert schema version
    self.conn.execute("INSERT INTO sync_meta (key, value) VALUES ('schema_version', ?)
                       ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                      params![SCHEMA_VERSION])?;
    Ok(())
}
```

The `ensure_column()` helper uses `PRAGMA table_info()` to check if a column exists before adding it:

```rust
fn ensure_column(conn: &Connection, table: &str, column: &str, column_type: &str) {
    let mut stmt = conn.prepare(&format!("PRAGMA table_info({table})"))?;
    // Check if column exists in pragma output
    if !exists {
        conn.execute(&format!("ALTER TABLE {table} ADD COLUMN {column} {column_type}"), [])?;
    }
}
```

### Current schema version

The schema version is stored in the `sync_meta` table. The current version is:

```rust
const SCHEMA_VERSION: i64 = 3;
```

## Remote item reference

The `RemoteItemRef` struct carries Proton identifiers for linking:

```rust
pub struct RemoteItemRef<'a> {
    pub volume_id: Option<&'a str>,
    pub share_id: Option<&'a str>,
    pub link_id: Option<&'a str>,
    pub parent_id: Option<&'a str>,
    pub revision: Option<&'a str>,
}
```

Each field is independently optional — a remote item might have some IDs but not others depending on what stage of the sync pipeline it's in.

## WAL mode

The database opens with WAL (Write-Ahead Logging) enabled:

```rust
conn.execute_batch("PRAGMA journal_mode=WAL")?;
```

WAL mode allows concurrent reads while a write is in progress, which is important because both the watcher thread and the poller thread write to the database.

## Troubleshooting

### "Failed to open sync metadata database"

**Symptoms:** Sync never starts. Console shows `ERR_SYNC_DB_OPEN_FAILED`.

**Causes:**
- `app_data_dir` is on a read-only filesystem
- Another process holds an exclusive lock on `sync-state.sqlite3`
- Permission denied on the app data directory

**Fix:**
```bash
# Check file permissions
ls -la ~/.local/share/com.proton.drive/sync-state.sqlite3

# Check for stale WAL/SHM files (leftover from crashed process)
ls -la ~/.local/share/com.proton.drive/sync-state.sqlite3-wal
ls -la ~/.local/share/com.proton.drive/sync-state.sqlite3-shm

# Remove stale WAL artifacts if the app is not running
rm ~/.local/share/com.proton.drive/sync-state.sqlite3-wal
rm ~/.local/share/com.proton.drive/sync-state.sqlite3-shm
```

### WAL Checkpoint Growth

**Symptoms:** `sync-state.sqlite3-wal` grows to hundreds of MB. Sync operations slow down.

**Cause:** The WAL file accumulates un-checkpointed frames when the app crashes or is killed without clean shutdown. WAL mode checkpoints on close, but SIGKILL bypasses this.

**Fix:** Close the app cleanly (use the tray icon > Quit, or SIGTERM). On next start, SQLite auto-checkpoints the WAL. If the WAL is extreme (>500MB), delete the WAL and SHM files while the app is **not running** — you lose the most recent sync state but the DB is intact.

### Schema Version Mismatch

**Symptoms:** `ERR_SYNC_DB_MIGRATE_FAILED` on startup after upgrading from an older version.

**Cause:** The `SCHEMA_VERSION` has changed (currently 3) and the old DB has a lower version. The migration code should handle this, but if you're on a very old version (schema 1), the upgrade path may be incomplete.

**Fix:** Delete the database and let it rebuild:
```bash
rm ~/.local/share/com.proton.drive/sync-state.sqlite3*
```
This resets all sync state — files will re-sync from scratch on next launch.

## See Also

- **[Sync DB Module](sync-db-module.md)** — How `sync_db.rs` integrates into AppState, SyncKeyring decryption, persistence constants
- **[Sync System](sync-system.md)** — Full architecture: change detection, remote apply, startup path
- **[Live Sync Module](live-sync-module.md)** — Core engine: watcher/poller threads, suppression cache
