# Sync Database Module

> **Status:** Not yet implemented — this document describes the current in-memory sync
> state architecture and outlines what a future database-backed persistence layer
> (`sync_db.rs`) should look like.
>
> **Current source:** `src-tauri/src/live_sync.rs` (all sync state is managed here).
>
> **Related:** [`docs/sync.md`](./sync.md) for the full live sync architecture overview.

---

## Overview

Unlike a cloud-sync client like Dropbox or Nextcloud, ProtonDrive Linux does **not**
currently use a local SQLite database or any persistent storage for sync state. Instead,
sync state is managed through two mechanisms:

| Mechanism | What it stores | Lifetime |
|---|---|---|
| **In-memory cache** (`KnownFiles`) | Suppression entries — paths + timestamps for echo prevention | Process lifetime only |
| **Filesystem** (sync root) | The actual file content being synced | Persistent (user's files) |

There is no record of:
- Which files have been synced vs. pending
- Remote file metadata (revision IDs, modification timestamps, checksums)
- Sync history or conflict logs
- Failed or pending operations for retry

This means every app restart starts with a clean state — no reconciliation, no
delta detection, no resumption of interrupted sync operations.

---

## Current State Architecture

### LiveSyncManager State Fields

All mutable sync state lives inside
[`LiveSyncManager`](../../src-tauri/src/live_sync.rs) and is guarded by
`std::sync::Mutex`:

```rust
pub struct LiveSyncManager {
    watcher: Mutex<Option<RecommendedWatcher>>,      // notify watcher handle
    folder: Mutex<Option<PathBuf>>,                   // user-chosen sync root
    root_canonical: Mutex<Option<PathBuf>>,            // canonicalized root (path security)
    worker: Mutex<Option<JoinHandle<()>>>,             // background watcher thread
    known_files: Arc<Mutex<HashMap<PathBuf, Instant>>>, // suppression cache
}
```

| Field | Type | Purpose | Persisted? |
|---|---|---|---|
| `watcher` | `Option<RecommendedWatcher>` | Active `notify` file watcher handle | No — ephemeral OS handle |
| `folder` | `Option<PathBuf>` | Path the user selected for sync | No — user re-selects on restart |
| `root_canonical` | `Option<PathBuf>` | Canonicalized root for path validation | No — derived from `folder` |
| `worker` | `Option<JoinHandle<()>>` | Background thread handle | No — ephemeral thread |
| `known_files` | `HashMap<PathBuf, Instant>` | Suppression cache (echo prevention) | No — TTL 30s, max 4096 |

### Suppression Cache Details

The `known_files` cache is the only sync-specific state. It prevents write-echo loops:

- **Key:** `PathBuf` — absolute path of a file written by a remote operation
- **Value:** `Instant` — timestamp of when the write was applied
- **TTL:** 30 seconds (`SUPPRESSION_TTL`)
- **Capacity:** 4096 entries (`SUPPRESSION_CACHE_MAX`)
- **Pruning:** Time-based on every access; capacity-based overflow evicts oldest

### State Lifecycle

```
┌─────────────────────────────────────────────────────┐
│  App Start                                           │
│  ┌─────────────────────────────────────────────────┐ │
│  │  LiveSyncManager::default()                     │ │
│  │  → All fields = None / empty HashMap            │ │
│  └──────────────────────┬──────────────────────────┘ │
│                         │                            │
│                         ▼                            │
│  ┌─────────────────────────────────────────────────┐ │
│  │  start(path) → sets watcher, folder, root,     │ │
│  │                  spawns worker thread           │ │
│  └──────────────────────┬──────────────────────────┘ │
│                         │                            │
│              ┌──────────┴──────────┐                 │
│              ▼                     ▼                 │
│  ┌────────────────────┐  ┌──────────────────────┐   │
│  │ Local changes:     │  │ Remote changes:      │   │
│  │ notify fires       │  │ handle_remote_update │   │
│  │ → suppress check   │  │ → write file         │   │
│  │ → emit Tauri event │  │ → mark known_file    │   │
│  └────────────────────┘  └──────────────────────┘   │
│                         │                            │
│                         ▼                            │
│  ┌─────────────────────────────────────────────────┐ │
│  │  stop() → drops watcher, joins thread,          │ │
│  │             clears known_files                   │ │
│  └─────────────────────────────────────────────────┘ │
│                         │                            │
│                         ▼                            │
│  ┌─────────────────────────────────────────────────┐ │
│  │  All state lost on process exit                 │ │
│  │  → No resumption on next start                  │ │
│  └─────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

---

## Why a Database Layer Is Needed

Without persistent sync state, the application has these limitations:

1. **No initial reconciliation** — Starting sync does not compare local files against
   remote state. Only changes that occur *after* the watcher starts are tracked.

2. **No progress tracking** — A large download interrupted by app restart must restart
   from scratch. There is no resume capability.

3. **No metadata cache** — File modification times and checksums cannot be compared.
   Every remote operation must decode and apply the full file content, even if the
   local copy is already current.

4. **No conflict history** — If the log shows a sync failure, there is no persisted
   record of the failure for diagnostic or retry purposes.

5. **No retry queue** — Transient failures (disk full, permission denied, network
   drop) return an error to the frontend immediately with no backend retry mechanism.

---

## Proposed Database Schema

A future `sync_db.rs` module should manage a local SQLite database stored at
a stable application data path (e.g. `~/.local/share/protondrive-linux/sync.db`).

### Tables

#### `sync_files` — Tracks synced file state

```sql
CREATE TABLE sync_files (
    relative_path TEXT NOT NULL,        -- path relative to sync root
    local_modified_at TEXT,             -- ISO 8601 of last local modification
    remote_modified_at TEXT,            -- ISO 8601 of last remote modification
    file_size INTEGER DEFAULT 0,        -- bytes
    content_hash TEXT,                  -- SHA-256 of file content (optional)
    revision_id TEXT,                   -- Proton Drive revision identifier
    sync_status TEXT NOT NULL DEFAULT 'pending',
        -- pending | synced | remote_changed | local_changed | conflict
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (relative_path)
);
```

#### `sync_events` — Audit log of sync operations

```sql
CREATE TABLE sync_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    relative_path TEXT,                  -- affected file, nullable (e.g. global)
    event_type TEXT NOT NULL,            -- local_create | local_modify | local_delete |
                                         -- remote_create | remote_update | remote_delete |
                                         -- conflict | error | retry
    details TEXT,                        -- JSON blob with extra context
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

#### `sync_config` — Per-sync-root settings

```sql
CREATE TABLE sync_config (
    key TEXT PRIMARY KEY,                -- setting name
    value TEXT NOT NULL                  -- setting value (JSON-encoded)
);
```

Default config entries:

| Key | Value | Purpose |
|---|---|---|
| `sync_root` | `"/home/user/ProtonDrive"` | Last-used sync directory path |
| `suppression_ttl_secs` | `30` | Override default suppression TTL |
| `max_retries` | `3` | Failed operation retry count |
| `sync_on_start` | `true` | Auto-start sync on app launch |

### Indexes

```sql
CREATE INDEX idx_sync_files_status ON sync_files(sync_status);
CREATE INDEX idx_sync_events_created ON sync_events(created_at);
CREATE INDEX idx_sync_events_path ON sync_events(relative_path);
```

---

## Proposed CRUD Operations

### Core Functions in `sync_db.rs`

```rust
/// Open or create the sync database at the given path.
/// Runs migrations if the schema is out of date.
pub fn open(path: &Path) -> Result<SyncDb, SyncDbError>

/// Insert or update a file record.
pub fn upsert_file(db: &SyncDb, file: &SyncFileRecord) -> Result<(), SyncDbError>

/// Batch insert/update multiple file records.
pub fn upsert_files(db: &SyncDb, files: &[SyncFileRecord]) -> Result<(), SyncDbError>

/// Get a single file record by relative path.
pub fn get_file(db: &SyncDb, relative_path: &str) -> Result<Option<SyncFileRecord>, SyncDbError>

/// Get all files with a given sync status (e.g. all pending files).
pub fn get_files_by_status(db: &SyncDb, status: SyncStatus) -> Result<Vec<SyncFileRecord>, SyncDbError>

/// Get all tracked files.
pub fn list_files(db: &SyncDb) -> Result<Vec<SyncFileRecord>, SyncDbError>

/// Delete a file record (when file is removed from sync).
pub fn delete_file(db: &SyncDb, relative_path: &str) -> Result<(), SyncDbError>

/// Log a sync event.
pub fn log_event(db: &SyncDb, event: &SyncEvent) -> Result<(), SyncDbError>

/// Get recent sync events for diagnostics.
pub fn recent_events(db: &SyncDb, limit: u32) -> Result<Vec<SyncEvent>, SyncDbError>

/// Get or set config values.
pub fn get_config(db: &SyncDb, key: &str) -> Result<Option<String>, SyncDbError>
pub fn set_config(db: &SyncDb, key: &str, value: &str) -> Result<(), SyncDbError>
```

### Data Types

```rust
pub enum SyncStatus {
    Pending,
    Synced,
    RemoteChanged,
    LocalChanged,
    Conflict,
}

pub struct SyncFileRecord {
    pub relative_path: String,
    pub local_modified_at: Option<String>,
    pub remote_modified_at: Option<String>,
    pub file_size: i64,
    pub content_hash: Option<String>,
    pub revision_id: Option<String>,
    pub sync_status: SyncStatus,
}

pub struct SyncEvent {
    pub relative_path: Option<String>,
    pub event_type: String,
    pub details: Option<String>,
}

pub struct SyncDb {
    conn: Connection,  // rusqlite::Connection
}
```

---

## How sync_db Would Interact with live_sync

The proposed producer/consumer pattern:

```
┌──────────────────────────────────────────────────────┐
│                   live_sync.rs                        │
│                                                      │
│  ┌─────────────────┐     ┌────────────────────────┐  │
│  │ File Watcher     │     │ Remote Change Handler │  │
│  │ (producer)       │     │ (consumer)            │  │
│  │                  │     │                        │  │
│  │ detect local     │     │ receive remote change │  │
│  │ file change      │     │ from frontend         │  │
│  └────────┬─────────┘     └───────────┬────────────┘  │
│           │                           │               │
│           ▼                           ▼               │
│  ┌──────────────────────────────────────────────┐    │
│  │             sync_db.rs                       │    │
│  │                                              │    │
│  │  ┌──────────────────────────────────────┐   │    │
│  │  │  sync_files table                   │   │    │
│  │  │                                      │   │    │
│  │  │  On local change:                    │   │    │
│  │  │    → UPDATE sync_status='local_changed'│   │    │
│  │  │    → INSERT sync_event               │   │    │
│  │  │                                      │   │    │
│  │  │  On remote change:                   │   │    │
│  │  │    → UPSERT file metadata            │   │    │
│  │  │    → UPDATE sync_status='synced'     │   │    │
│  │  │    → INSERT sync_event               │   │    │
│  │  └──────────────────────────────────────┘   │    │
│  └──────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────┘
```

### Startup Flow (with database)

```
App starts
  → sync_db::open(path) → creates/migrates schema
  → sync_db::get_config("sync_root")
     ↓
  If sync_root is set:
    → sync_db::get_files_by_status("pending")
    → For each pending file: retry or flag as failed
    → sync_db::log_event("app_start", ...)
    → live_sync::start(sync_root)
```

### Shutdown Flow (with database)

```
App closes
  → live_sync::stop()
  → sync_db::close() (connection dropped)
```

---

## Migration Strategy

Since there is currently **no** persistent sync database, the migration is a
one-time bootstrapping:

| Step | Action | Backward Compat? |
|---|---|---|
| 1 | Add `src-tauri/src/sync_db.rs` module | Yes — no existing DB to migrate |
| 2 | Declare `mod sync_db;` in `main.rs` | Yes |
| 3 | Add `sync_db` to `AppState` alongside `sync_manager` | Yes — new field, old state unaffected |
| 4 | On first `start_sync()`, call `sync_db::open()` at app data path | Yes — creates fresh DB |
| 5 | On each file write, upsert file record in `sync_files` | Yes — pure additive logging |
| 6 | On each remote change, log `sync_events` entry | Yes |
| 7 | Future: add reconciliation pass at startup | Yes — opt-in enhancement |

### Dependency

Add to `Cargo.toml`:

```toml
[dependencies]
rusqlite = { version = "0.31", features = ["bundled"] }
```

The `bundled` feature compiles SQLite from source, avoiding a system library
dependency — important for AppImage and static-linked distro packages.

---

## Associated Types Summary

| Type | Module | Persisted? | Description |
|---|---|---|---|
| `LiveSyncManager` | `live_sync.rs` | No | Runtime state: watcher handle, worker thread, suppression cache |
| `LiveSyncEvent` | `live_sync.rs` | No | Event sent to frontend on local change |
| `LiveSyncStatus` | `live_sync.rs` | No | Status returned to frontend (enabled + path) |
| `RemoteSyncChange` | `live_sync.rs` | No | Remote action payload from frontend |
| `SyncFileRecord` | *(proposed: sync_db.rs)* | Yes | Per-file sync state and metadata |
| `SyncEvent` | *(proposed: sync_db.rs)* | Yes | Audit log of sync operations |
| `SyncDb` | *(proposed: sync_db.rs)* | Yes | Database connection and query methods |

---

## Current State Summary (No Database)

```
All sync state        ───> in memory (HashMap + Mutex fields)
                        ───> dies with process

Filesystem state      ───> user's sync directory
                        ───> persistent, but no metadata about sync progress

Recommended next step ───> add sync_db.rs with SQLite-backed persistence
                        ───> enables reconciliation, retry, audit, and resume
```
