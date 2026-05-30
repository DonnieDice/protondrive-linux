# Sync Database Module (`sync_db.rs`)

> **Source:** `src-tauri/src/sync_db.rs` — 839 lines. A SQLite-backed metadata store
> that tracks every synced file's local and remote state, with privacy-preserving
> SHA-256 hashing for all sensitive data.

---

## Overview

`sync_db.rs` is the **persistent metadata layer** for the live sync system. It records
every file in the sync root — its local fingerprint (size, mtime, kind), its remote
Proton Drive identity (volume, share, link, parent, revision), and its sync state
(synced, pending, conflicted, tombstoned). All sensitive data (paths, device names,
Proton remote IDs) is SHA-256 hashed before storage so the on-disk SQLite file
contains no plaintext user data.

The database lives at `{app_data_dir}/sync-state.sqlite3` (e.g.
`~/.local/share/protondrive-linux/sync-state.sqlite3`). It is opened with **WAL
journal mode** and **foreign keys ON** for concurrent-read safety and referential
integrity.

**This is not a proposed schema — it is the live implementation used in production.**

---

## Privacy Model

Every value that could identify a user's files or Proton account is **SHA-256 hashed**
before it touches the database:

| Plaintext | Hashed column | Stored as |
|-----------|---------------|-----------|
| Sync root path (`/home/alice/ProtonDrive`) | `root_path_hash` | `hash_sensitive(path)` → 64-char hex |
| Relative file path (`taxes/2024.pdf`) | `relative_path_hash` | `hash_sensitive(path)` → 64-char hex |
| Device name (`alice-laptop`) | `device_name_hash` | `hash_sensitive(name)` → 64-char hex |
| Proton volume/link/share/parent/revision IDs | `remote_*_hash` | `hash_sensitive(id)` → 64-char hex |
| Remote path mapping (`Pictures/Linux`) | `remote_path_hash` | `hash_sensitive(path)` → 64-char hex |

Tests verify this: `stores_metadata_without_raw_paths_or_remote_ids` reads the raw
SQLite bytes and asserts that no plaintext path, device name, or remote ID appears
anywhere in the file.

```rust
pub fn hash_sensitive(value: impl AsRef<str>) -> String {
    let mut hasher = Sha256::new();
    hasher.update(value.as_ref().as_bytes());
    hex::encode(hasher.finalize())
}
```

---

## Schema (Version 3)

The database has three tables, created via `migrate()` at open time.

### `sync_meta` — Schema version tracking

```sql
CREATE TABLE IF NOT EXISTS sync_meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
```

Currently stores a single row: `key='schema_version', value='3'`. Used by the
migration system to detect when the schema has changed.

### `sync_roots` — Per-folder sync configuration

```sql
CREATE TABLE IF NOT EXISTS sync_roots (
    id                        TEXT PRIMARY KEY,           -- hash_sensitive(root_path)
    root_path_hash            TEXT NOT NULL,
    remote_scope              TEXT NOT NULL DEFAULT 'unmapped',  -- 'computers' | 'my_files' | 'unmapped'
    device_type               TEXT,                       -- 'linux', null for my_files
    device_name_hash          TEXT,                       -- null for my_files
    remote_device_uid_hash    TEXT,
    remote_root_folder_uid_hash TEXT,
    remote_share_id_hash      TEXT,
    remote_path_hash          TEXT,                       -- remote path mapping for my_files
    created_at_ns             INTEGER NOT NULL,
    updated_at_ns             INTEGER NOT NULL
);
```

One row per sync root. The `id` is `hash_sensitive(root_path)` — opening the same
folder always resolves to the same row. Three remote scopes are supported:

| Scope | Meaning | Device fields? |
|-------|---------|---------------|
| `computers` | Syncs to Proton Drive's "Computers" section (default) | Yes (`device_type`, `device_name_hash`) |
| `my_files` | Syncs to a specific path under "My Files" | No (`device_name_hash` is NULL); uses `remote_path_hash` |
| `unmapped` | Root registered but no remote scope assigned yet | No |

### `sync_items` — Per-file state tracking

```sql
CREATE TABLE IF NOT EXISTS sync_items (
    root_id                 TEXT NOT NULL,          -- FK → sync_roots.id
    relative_path_hash      TEXT NOT NULL,
    local_kind              TEXT NOT NULL,          -- 'file' | 'dir' | 'unknown'
    local_size              INTEGER,                -- bytes (files only)
    local_mtime_ns          INTEGER,                -- mtime in nanoseconds since epoch
    content_hash            TEXT,                    -- SHA-256 of file content (future use)
    remote_volume_id_hash   TEXT,
    remote_share_id_hash    TEXT,
    remote_link_id_hash     TEXT,
    remote_parent_id_hash   TEXT,
    remote_revision_hash    TEXT,
    state                   TEXT NOT NULL,          -- 'synced' | 'local_pending' | 'remote_pending' | 'conflict' | 'tombstone'
    last_seen_local_ns      INTEGER,
    last_seen_remote_ns     INTEGER,
    tombstoned_at_ns        INTEGER,
    retry_count             INTEGER NOT NULL DEFAULT 0,
    last_error_code         TEXT,
    created_at_ns           INTEGER NOT NULL DEFAULT 0,
    updated_at_ns           INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (root_id, relative_path_hash),
    FOREIGN KEY (root_id) REFERENCES sync_roots(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_sync_items_state
    ON sync_items(root_id, state, updated_at_ns);
```

The composite primary key `(root_id, relative_path_hash)` means that the same
relative path across different sync roots is tracked independently. The index on
`(root_id, state, updated_at_ns)` makes `pending_items()` queries fast — it's the
hot path for the poller and watcher.

### Migration system

Column additions use a safe `ensure_column()` helper that reads `PRAGMA table_info`
before running `ALTER TABLE ADD COLUMN`:

```rust
fn ensure_column(conn: &Connection, table: &str, column: &str, column_type: &str) -> Result<(), String>
```

This is idempotent — running it against a database that already has the column is a
no-op. This means the schema can evolve across releases without manual migration steps.

Current schema version: **3**.

---

## Key Types

### `SyncItemState`

```rust
pub enum SyncItemState {
    Synced,          // Local and remote are identical
    LocalPending,    // Local change detected, not yet uploaded
    RemotePending,   // Remote change received, not yet applied locally
    Conflict,        // Both local and remote changed simultaneously
    Tombstone,       // File was deleted locally; pending remote deletion
}
```

Serialized as strings: `"synced"`, `"local_pending"`, `"remote_pending"`,
`"conflict"`, `"tombstone"`. Any unrecognized string defaults to `LocalPending`.

### `SyncItemRecord`

```rust
pub struct SyncItemRecord {
    pub root_id: String,
    pub relative_path_hash: String,
    pub local_kind: String,              // "file" | "dir" | "unknown"
    pub local_size: Option<i64>,
    pub local_mtime_ns: Option<i64>,
    pub content_hash: Option<String>,
    pub remote_volume_id_hash: Option<String>,
    pub remote_share_id_hash: Option<String>,
    pub remote_link_id_hash: Option<String>,
    pub remote_parent_id_hash: Option<String>,
    pub remote_revision_hash: Option<String>,
    pub state: SyncItemState,
    pub retry_count: i64,
    pub last_error_code: Option<String>,
}
```

### `RemoteItemRef`

A borrowed reference struct for linking a local item to its Proton Drive remote
identity. All fields are hashed before storage:

```rust
pub struct RemoteItemRef<'a> {
    pub volume_id: Option<&'a str>,
    pub share_id: Option<&'a str>,
    pub link_id: Option<&'a str>,
    pub parent_id: Option<&'a str>,
    pub revision: Option<&'a str>,
}
```

---

## Operations

### Opening the database

```rust
pub fn open(path: &Path) -> Result<Self, String>
```

1. Creates parent directory with `0o700` permissions (owner-only)
2. Creates the SQLite file with `0o600` permissions if it doesn't exist
3. Opens the connection
4. Sets WAL journal mode (`PRAGMA journal_mode=WAL`)
5. Enables foreign keys (`PRAGMA foreign_keys=ON`)
6. Runs `migrate()` to create/update the schema

**Why WAL?** The live sync poller reads while the watcher writes. WAL mode allows
concurrent reads during a write, preventing `SQLITE_BUSY` errors. Foreign keys with
`ON DELETE CASCADE` ensure deleting a sync root automatically removes all its tracked
items.

### Registering a sync root

Three variants depending on the remote scope:

| Method | Scope | Sets |
|--------|-------|------|
| `upsert_root(path)` | `unmapped` | Just the path hash |
| `upsert_computers_root(path, device_name, device_type)` | `computers` | Path hash + device name hash + "linux" |
| `upsert_my_files_mapping(path, remote_path)` | `my_files` | Path hash + remote path hash (no device) |

All use `INSERT ... ON CONFLICT(id) DO UPDATE` so calling them on an existing root
is a safe upsert — the existing scope is preserved if the method doesn't override it.

### Recording local file changes

```rust
pub fn upsert_local_item(
    &self,
    root_id: &str,
    relative_path: &Path,
    local_kind: &str,      // "file" | "dir"
    local_size: Option<i64>,
    local_mtime_ns: Option<i64>,
    content_hash: Option<&str>,
    state: SyncItemState,
) -> Result<String, String>
```

Called by the live sync engine (`record_local_change_metadata()`) whenever the
watcher or poller detects a local create or modify. Uses `INSERT ... ON CONFLICT
DO UPDATE` — the first detection inserts, subsequent detections update the metadata
without creating duplicates.

The `state` is typically `SyncItemState::LocalPending` ("I changed this, please
upload to Proton").

### Linking remote identity

```rust
pub fn link_remote_item(
    &self,
    root_id: &str,
    relative_path: &Path,
    remote: RemoteItemRef<'_>,
) -> Result<(), String>
```

After the frontend uploads a file to Proton Drive and gets back remote IDs
(volume, share, link, parent, revision), it calls this to link the local item to
its remote counterpart. Updates the `last_seen_remote_ns` timestamp.

### Tombstones (soft-delete tracking)

```rust
pub fn mark_tombstone(&self, root_id: &str, relative_path: &Path) -> Result<bool, String>
```

When a local file is deleted, the watcher calls this instead of deleting the row.
The row's `state` is set to `Tombstone` and `tombstoned_at_ns` is recorded. This
preserves the remote identity so the frontend knows which remote file to delete.

**Guard clause:** Only items in `synced`, `local_pending`, or `remote_pending` state
can be tombstoned. An item that doesn't exist yet in the DB returns `false`.

### Querying pending items

```rust
pub fn pending_items(&self, root_id: &str) -> Result<Vec<SyncItemRecord>, String>
```

Returns all items in a non-final state: `local_pending`, `remote_pending`,
`conflict`, or `tombstone`. Ordered by `updated_at_ns ASC` (oldest first). Items in
`synced` state are excluded — they need no action.

This is the query the frontend uses to decide what needs to be uploaded/downloaded.

### Looking up a single item

```rust
pub fn get_item(&self, root_id: &str, relative_path: &Path) -> Result<Option<SyncItemRecord>, String>
```

Returns `None` if no record exists for that path. Used for per-file status checks
and conflict detection.

---

## Security Hardening

### Filesystem permissions

```
Parent directory: 0o700 (rwx------) — only the app's user can enter
SQLite file:      0o600 (rw-------) — only the app's user can read/write
```

These are enforced unconditionally on `open()` via `set_private_dir_permissions()`
and `set_private_file_permissions()`. On non-Unix platforms, these are no-ops.

### Privacy by construction

- All paths, device names, and Proton remote IDs are SHA-256 hashed before storage
- The database file on disk contains no plaintext user data — verified by tests
- Access to the SQLite file is the only attack surface; the file itself is safe at rest

---

## Error Handling

All public methods return `Result<T, String>` with user-safe error messages. The
internal error constants are:

| Constant | Message | When |
|----------|---------|------|
| `ERR_SYNC_DB_OPEN_FAILED` | "Failed to open sync metadata database" | File I/O, permission, connection |
| `ERR_SYNC_DB_MIGRATE_FAILED` | "Failed to migrate sync metadata database" | Schema creation or ALTER TABLE |
| `ERR_SYNC_DB_WRITE_FAILED` | "Failed to write sync metadata" | INSERT/UPDATE failure |
| `ERR_SYNC_DB_READ_FAILED` | "Failed to read sync metadata" | SELECT failure |

All errors are logged with `[SyncDb]` prefix via `eprintln!` before being returned
to the caller.

---

## Integration with the Live Sync Engine

The sync database is opened once at app startup (via `start_sync` or
`set_sync_root`) and shared with the live sync engine's watcher and poller threads:

```
main.rs: start_sync()
  → validate_sync_root_path()
  → register_sync_root_metadata()     ← opens DB, upserts sync_roots row
  → sync_manager.start(app, folder)
      → SyncDb::open(&sync_db_path)   ← opens again in start_with_poll_interval
      → db.upsert_root(&folder)       ← registers/unmapped root (preserves existing scope)
      → watcher thread spawns, holds db_path + root_id
      → poller thread spawns, holds db_path + root_id
```

Both threads call `record_local_change_metadata()` on every detected change, which
opens the DB fresh, writes `upsert_local_item()` or `mark_tombstone()`, then drops
the connection. This is safe because WAL mode allows concurrent readers and the
writes are quick single-row inserts.

The frontend accesses the database indirectly through Tauri commands
(`start_sync`, `stop_sync`, `get_sync_status`, `handle_remote_update`,
`read_sync_file`). It does not call database methods directly — all access is
mediated by the Rust backend.

---

## Limitations

1. **No content hashing yet** — The `content_hash` column exists but is not
   currently populated. When it is, it will enable detecting when a file's
   content has changed without an mtime update.

2. **No conflict resolution logic** — The `Conflict` state exists as an enum
   variant but there is no automatic merge or user-prompt flow. Conflicts are
   flagged but not resolved.

3. **Retry is tracked but not automated** — The `retry_count` and
   `last_error_code` columns track failures, but the backend does not currently
   retry failed uploads. The frontend is responsible for retry logic.

4. **Single-user** — The database assumes one user per app instance. There is
   no multi-user or multi-account support.

## See Also

- **[Sync Database](sync-database.md)** — SQLite schema, item states, privacy hashing, migration strategy
- **[Sync System](sync-system.md)** — Full sync architecture, change detection, Tauri command wiring
- **[Live Sync Module](live-sync-module.md)** — Core engine: watcher/poller threads, event contract
- **[Architecture](../architecture/architecture.md)** — How `sync_db` fits into the overall AppState
