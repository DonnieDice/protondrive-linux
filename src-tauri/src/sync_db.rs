use rusqlite::{params, Connection, OptionalExtension};
use sha2::{Digest, Sha256};
use std::fs::{self, OpenOptions};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

const SCHEMA_VERSION: i64 = 3;
const ERR_SYNC_DB_OPEN_FAILED: &str = "Failed to open sync metadata database";
const ERR_SYNC_DB_MIGRATE_FAILED: &str = "Failed to migrate sync metadata database";
const ERR_SYNC_DB_WRITE_FAILED: &str = "Failed to write sync metadata";
const ERR_SYNC_DB_READ_FAILED: &str = "Failed to read sync metadata";

pub const REMOTE_SCOPE_COMPUTERS: &str = "computers";
pub const REMOTE_SCOPE_MY_FILES: &str = "my_files";
pub const REMOTE_SCOPE_UNMAPPED: &str = "unmapped";

#[derive(Debug, Clone, Eq, PartialEq)]
pub enum SyncItemState {
    Synced,
    LocalPending,
    RemotePending,
    Conflict,
    Tombstone,
}

impl SyncItemState {
    fn as_str(&self) -> &'static str {
        match self {
            Self::Synced => "synced",
            Self::LocalPending => "local_pending",
            Self::RemotePending => "remote_pending",
            Self::Conflict => "conflict",
            Self::Tombstone => "tombstone",
        }
    }

    fn from_str(value: &str) -> Self {
        match value {
            "synced" => Self::Synced,
            "remote_pending" => Self::RemotePending,
            "conflict" => Self::Conflict,
            "tombstone" => Self::Tombstone,
            _ => Self::LocalPending,
        }
    }
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub struct SyncItemRecord {
    pub root_id: String,
    pub relative_path_hash: String,
    pub local_kind: String,
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

pub struct SyncDb {
    conn: Connection,
}

impl SyncDb {
    pub fn open(path: &Path) -> Result<Self, String> {
        ensure_private_parent(path)?;
        ensure_private_file(path)?;

        let conn = Connection::open(path).map_err(|e| {
            eprintln!("[SyncDb] open failed: {e}");
            ERR_SYNC_DB_OPEN_FAILED.to_string()
        })?;
        conn.pragma_update(None, "journal_mode", "WAL")
            .map_err(|e| {
                eprintln!("[SyncDb] journal mode setup failed: {e}");
                ERR_SYNC_DB_OPEN_FAILED.to_string()
            })?;
        conn.pragma_update(None, "foreign_keys", "ON")
            .map_err(|e| {
                eprintln!("[SyncDb] foreign key setup failed: {e}");
                ERR_SYNC_DB_OPEN_FAILED.to_string()
            })?;

        let db = Self { conn };
        db.migrate()?;
        Ok(db)
    }

    pub fn upsert_root(&self, root_path: &Path) -> Result<String, String> {
        let root_id = hash_sensitive(&root_path.to_string_lossy());
        let now = now_unix_ns();
        self.conn
            .execute(
                "INSERT INTO sync_roots (id, root_path_hash, remote_scope, created_at_ns, updated_at_ns)
                 VALUES (?1, ?2, ?3, ?4, ?4)
                 ON CONFLICT(id) DO UPDATE SET
                   root_path_hash = excluded.root_path_hash,
                   updated_at_ns = excluded.updated_at_ns",
                params![root_id, root_id, REMOTE_SCOPE_UNMAPPED, now],
            )
            .map_err(|e| {
                eprintln!("[SyncDb] root upsert failed: {e}");
                ERR_SYNC_DB_WRITE_FAILED.to_string()
            })?;
        Ok(root_id)
    }

    pub fn upsert_computers_root(
        &self,
        root_path: &Path,
        device_name: &str,
        device_type: &str,
    ) -> Result<String, String> {
        let root_id = hash_sensitive(&root_path.to_string_lossy());
        let device_name_hash = hash_sensitive(device_name);
        let now = now_unix_ns();
        self.conn
            .execute(
                "INSERT INTO sync_roots (
                   id, root_path_hash, remote_scope, device_type, device_name_hash,
                   remote_path_hash, created_at_ns, updated_at_ns
                 )
                 VALUES (?1, ?2, ?3, ?4, ?5, NULL, ?6, ?6)
                 ON CONFLICT(id) DO UPDATE SET
                   root_path_hash = excluded.root_path_hash,
                   remote_scope = excluded.remote_scope,
                   device_type = excluded.device_type,
                   device_name_hash = excluded.device_name_hash,
                   remote_path_hash = excluded.remote_path_hash,
                   updated_at_ns = excluded.updated_at_ns",
                params![
                    root_id,
                    root_id,
                    REMOTE_SCOPE_COMPUTERS,
                    device_type,
                    device_name_hash,
                    now
                ],
            )
            .map_err(|e| {
                eprintln!("[SyncDb] computers root upsert failed: {e}");
                ERR_SYNC_DB_WRITE_FAILED.to_string()
            })?;
        Ok(root_id)
    }

    pub fn upsert_my_files_mapping(
        &self,
        root_path: &Path,
        remote_path: &str,
    ) -> Result<String, String> {
        let root_id = hash_sensitive(&root_path.to_string_lossy());
        let remote_path_hash = hash_sensitive(remote_path);
        let now = now_unix_ns();
        self.conn
            .execute(
                "INSERT INTO sync_roots (
                   id, root_path_hash, remote_scope, device_type, device_name_hash,
                   remote_path_hash, created_at_ns, updated_at_ns
                 )
                 VALUES (?1, ?2, ?3, NULL, NULL, ?4, ?5, ?5)
                 ON CONFLICT(id) DO UPDATE SET
                   root_path_hash = excluded.root_path_hash,
                   remote_scope = excluded.remote_scope,
                   device_type = excluded.device_type,
                   device_name_hash = excluded.device_name_hash,
                   remote_path_hash = excluded.remote_path_hash,
                   updated_at_ns = excluded.updated_at_ns",
                params![
                    root_id,
                    root_id,
                    REMOTE_SCOPE_MY_FILES,
                    remote_path_hash,
                    now
                ],
            )
            .map_err(|e| {
                eprintln!("[SyncDb] My files mapping upsert failed: {e}");
                ERR_SYNC_DB_WRITE_FAILED.to_string()
            })?;
        Ok(root_id)
    }

    pub fn upsert_local_item(
        &self,
        root_id: &str,
        relative_path: &Path,
        local_kind: &str,
        local_size: Option<i64>,
        local_mtime_ns: Option<i64>,
        content_hash: Option<&str>,
        state: SyncItemState,
    ) -> Result<String, String> {
        let relative_path_hash = hash_sensitive(&relative_path.to_string_lossy());
        let now = now_unix_ns();
        self.conn
            .execute(
                "INSERT INTO sync_items (
                   root_id, relative_path_hash, local_kind, local_size, local_mtime_ns,
                   content_hash, state, last_seen_local_ns, updated_at_ns
                 )
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?8)
                 ON CONFLICT(root_id, relative_path_hash) DO UPDATE SET
                   local_kind = excluded.local_kind,
                   local_size = excluded.local_size,
                   local_mtime_ns = excluded.local_mtime_ns,
                   content_hash = excluded.content_hash,
                   state = excluded.state,
                   last_seen_local_ns = excluded.last_seen_local_ns,
                   updated_at_ns = excluded.updated_at_ns",
                params![
                    root_id,
                    relative_path_hash,
                    local_kind,
                    local_size,
                    local_mtime_ns,
                    content_hash,
                    state.as_str(),
                    now
                ],
            )
            .map_err(|e| {
                eprintln!("[SyncDb] local item upsert failed: {e}");
                ERR_SYNC_DB_WRITE_FAILED.to_string()
            })?;
        Ok(relative_path_hash)
    }

    pub fn link_remote_item(
        &self,
        root_id: &str,
        relative_path: &Path,
        remote: RemoteItemRef<'_>,
    ) -> Result<(), String> {
        let relative_path_hash = hash_sensitive(&relative_path.to_string_lossy());
        let now = now_unix_ns();
        self.conn
            .execute(
                "UPDATE sync_items SET
                   remote_volume_id_hash = ?3,
                   remote_share_id_hash = ?4,
                   remote_link_id_hash = ?5,
                   remote_parent_id_hash = ?6,
                   remote_revision_hash = ?7,
                   last_seen_remote_ns = ?8,
                   updated_at_ns = ?8
                 WHERE root_id = ?1 AND relative_path_hash = ?2",
                params![
                    root_id,
                    relative_path_hash,
                    remote.volume_id.map(hash_sensitive),
                    remote.share_id.map(hash_sensitive),
                    remote.link_id.map(hash_sensitive),
                    remote.parent_id.map(hash_sensitive),
                    remote.revision.map(hash_sensitive),
                    now
                ],
            )
            .map_err(|e| {
                eprintln!("[SyncDb] remote item link failed: {e}");
                ERR_SYNC_DB_WRITE_FAILED.to_string()
            })?;
        Ok(())
    }

    pub fn mark_tombstone(&self, root_id: &str, relative_path: &Path) -> Result<bool, String> {
        let relative_path_hash = hash_sensitive(&relative_path.to_string_lossy());
        let now = now_unix_ns();

        let updated = self
            .conn
            .execute(
                "UPDATE sync_items SET
                   state = ?3,
                   tombstoned_at_ns = ?4,
                   updated_at_ns = ?4
                 WHERE root_id = ?1
                   AND relative_path_hash = ?2
                   AND state IN ('synced', 'local_pending', 'remote_pending')",
                params![
                    root_id,
                    relative_path_hash,
                    SyncItemState::Tombstone.as_str(),
                    now
                ],
            )
            .map_err(|e| {
                eprintln!("[SyncDb] tombstone mark failed: {e}");
                ERR_SYNC_DB_WRITE_FAILED.to_string()
            })?;

        Ok(updated > 0)
    }

    pub fn get_item(
        &self,
        root_id: &str,
        relative_path: &Path,
    ) -> Result<Option<SyncItemRecord>, String> {
        let relative_path_hash = hash_sensitive(&relative_path.to_string_lossy());
        self.conn
            .query_row(
                "SELECT root_id, relative_path_hash, local_kind, local_size, local_mtime_ns,
                        content_hash, remote_volume_id_hash, remote_share_id_hash,
                        remote_link_id_hash, remote_parent_id_hash, remote_revision_hash,
                        state, retry_count, last_error_code
                 FROM sync_items
                 WHERE root_id = ?1 AND relative_path_hash = ?2",
                params![root_id, relative_path_hash],
                row_to_sync_item,
            )
            .optional()
            .map_err(|e| {
                eprintln!("[SyncDb] item read failed: {e}");
                ERR_SYNC_DB_READ_FAILED.to_string()
            })
    }

    pub fn pending_items(&self, root_id: &str) -> Result<Vec<SyncItemRecord>, String> {
        let mut stmt = self
            .conn
            .prepare(
                "SELECT root_id, relative_path_hash, local_kind, local_size, local_mtime_ns,
                        content_hash, remote_volume_id_hash, remote_share_id_hash,
                        remote_link_id_hash, remote_parent_id_hash, remote_revision_hash,
                        state, retry_count, last_error_code
                 FROM sync_items
                 WHERE root_id = ?1 AND state IN ('local_pending', 'remote_pending', 'conflict', 'tombstone')
                 ORDER BY updated_at_ns ASC",
            )
            .map_err(|e| {
                eprintln!("[SyncDb] pending query prepare failed: {e}");
                ERR_SYNC_DB_READ_FAILED.to_string()
            })?;

        let rows = stmt
            .query_map(params![root_id], row_to_sync_item)
            .map_err(|e| {
                eprintln!("[SyncDb] pending query failed: {e}");
                ERR_SYNC_DB_READ_FAILED.to_string()
            })?;

        rows.collect::<Result<Vec<_>, _>>().map_err(|e| {
            eprintln!("[SyncDb] pending row read failed: {e}");
            ERR_SYNC_DB_READ_FAILED.to_string()
        })
    }

    fn migrate(&self) -> Result<(), String> {
        self.conn
            .execute_batch(
                "
                CREATE TABLE IF NOT EXISTS sync_meta (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS sync_roots (
                    id TEXT PRIMARY KEY,
                    root_path_hash TEXT NOT NULL,
                    remote_scope TEXT NOT NULL DEFAULT 'unmapped',
                    device_type TEXT,
                    device_name_hash TEXT,
                    remote_device_uid_hash TEXT,
                    remote_root_folder_uid_hash TEXT,
                    remote_share_id_hash TEXT,
                    remote_path_hash TEXT,
                    created_at_ns INTEGER NOT NULL,
                    updated_at_ns INTEGER NOT NULL
                );

                CREATE TABLE IF NOT EXISTS sync_items (
                    root_id TEXT NOT NULL,
                    relative_path_hash TEXT NOT NULL,
                    local_kind TEXT NOT NULL,
                    local_size INTEGER,
                    local_mtime_ns INTEGER,
                    content_hash TEXT,
                    remote_volume_id_hash TEXT,
                    remote_share_id_hash TEXT,
                    remote_link_id_hash TEXT,
                    remote_parent_id_hash TEXT,
                    remote_revision_hash TEXT,
                    state TEXT NOT NULL,
                    last_seen_local_ns INTEGER,
                    last_seen_remote_ns INTEGER,
                    tombstoned_at_ns INTEGER,
                    retry_count INTEGER NOT NULL DEFAULT 0,
                    last_error_code TEXT,
                    created_at_ns INTEGER NOT NULL DEFAULT 0,
                    updated_at_ns INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY(root_id, relative_path_hash),
                    FOREIGN KEY(root_id) REFERENCES sync_roots(id) ON DELETE CASCADE
                );

                CREATE INDEX IF NOT EXISTS idx_sync_items_state
                    ON sync_items(root_id, state, updated_at_ns);
                ",
            )
            .map_err(|e| {
                eprintln!("[SyncDb] migration failed: {e}");
                ERR_SYNC_DB_MIGRATE_FAILED.to_string()
            })?;
        ensure_column(
            &self.conn,
            "sync_roots",
            "remote_scope",
            "TEXT NOT NULL DEFAULT 'unmapped'",
        )?;
        ensure_column(&self.conn, "sync_roots", "device_type", "TEXT")?;
        ensure_column(&self.conn, "sync_roots", "device_name_hash", "TEXT")?;
        ensure_column(&self.conn, "sync_roots", "remote_device_uid_hash", "TEXT")?;
        ensure_column(
            &self.conn,
            "sync_roots",
            "remote_root_folder_uid_hash",
            "TEXT",
        )?;
        ensure_column(&self.conn, "sync_roots", "remote_share_id_hash", "TEXT")?;
        ensure_column(&self.conn, "sync_roots", "remote_path_hash", "TEXT")?;

        self.conn
            .execute(
                "INSERT INTO sync_meta (key, value)
                 VALUES ('schema_version', ?1)
                 ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                params![SCHEMA_VERSION.to_string()],
            )
            .map_err(|e| {
                eprintln!("[SyncDb] schema version write failed: {e}");
                ERR_SYNC_DB_MIGRATE_FAILED.to_string()
            })?;
        Ok(())
    }
}

fn ensure_column(
    conn: &Connection,
    table: &str,
    column: &str,
    column_type: &str,
) -> Result<(), String> {
    let mut stmt = conn
        .prepare(&format!("PRAGMA table_info({table})"))
        .map_err(|e| {
            eprintln!("[SyncDb] schema inspection failed: {e}");
            ERR_SYNC_DB_MIGRATE_FAILED.to_string()
        })?;
    let rows = stmt
        .query_map([], |row| row.get::<_, String>(1))
        .map_err(|e| {
            eprintln!("[SyncDb] schema inspection query failed: {e}");
            ERR_SYNC_DB_MIGRATE_FAILED.to_string()
        })?;
    let mut exists = false;
    for row in rows {
        if row.map_err(|e| {
            eprintln!("[SyncDb] schema inspection row failed: {e}");
            ERR_SYNC_DB_MIGRATE_FAILED.to_string()
        })? == column
        {
            exists = true;
            break;
        }
    }
    if !exists {
        conn.execute(
            &format!("ALTER TABLE {table} ADD COLUMN {column} {column_type}"),
            [],
        )
        .map_err(|e| {
            eprintln!("[SyncDb] schema alter failed: {e}");
            ERR_SYNC_DB_MIGRATE_FAILED.to_string()
        })?;
    }
    Ok(())
}

pub struct RemoteItemRef<'a> {
    pub volume_id: Option<&'a str>,
    pub share_id: Option<&'a str>,
    pub link_id: Option<&'a str>,
    pub parent_id: Option<&'a str>,
    pub revision: Option<&'a str>,
}

pub fn sync_db_path(app_data_dir: &Path) -> PathBuf {
    app_data_dir.join("sync-state.sqlite3")
}

pub fn hash_sensitive(value: impl AsRef<str>) -> String {
    let mut hasher = Sha256::new();
    hasher.update(value.as_ref().as_bytes());
    hex::encode(hasher.finalize())
}

fn row_to_sync_item(row: &rusqlite::Row<'_>) -> rusqlite::Result<SyncItemRecord> {
    Ok(SyncItemRecord {
        root_id: row.get(0)?,
        relative_path_hash: row.get(1)?,
        local_kind: row.get(2)?,
        local_size: row.get(3)?,
        local_mtime_ns: row.get(4)?,
        content_hash: row.get(5)?,
        remote_volume_id_hash: row.get(6)?,
        remote_share_id_hash: row.get(7)?,
        remote_link_id_hash: row.get(8)?,
        remote_parent_id_hash: row.get(9)?,
        remote_revision_hash: row.get(10)?,
        state: SyncItemState::from_str(row.get::<_, String>(11)?.as_str()),
        retry_count: row.get(12)?,
        last_error_code: row.get(13)?,
    })
}

fn ensure_private_parent(path: &Path) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| {
            eprintln!("[SyncDb] parent directory create failed: {e}");
            ERR_SYNC_DB_OPEN_FAILED.to_string()
        })?;
        set_private_dir_permissions(parent)?;
    }
    Ok(())
}

fn ensure_private_file(path: &Path) -> Result<(), String> {
    if !path.exists() {
        OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(path)
            .map_err(|e| {
                eprintln!("[SyncDb] private DB file create failed: {e}");
                ERR_SYNC_DB_OPEN_FAILED.to_string()
            })?;
    }
    set_private_file_permissions(path)
}

#[cfg(unix)]
fn set_private_dir_permissions(path: &Path) -> Result<(), String> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(0o700)).map_err(|e| {
        eprintln!("[SyncDb] private dir permission setup failed: {e}");
        ERR_SYNC_DB_OPEN_FAILED.to_string()
    })
}

#[cfg(not(unix))]
fn set_private_dir_permissions(_path: &Path) -> Result<(), String> {
    Ok(())
}

#[cfg(unix)]
fn set_private_file_permissions(path: &Path) -> Result<(), String> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600)).map_err(|e| {
        eprintln!("[SyncDb] private file permission setup failed: {e}");
        ERR_SYNC_DB_OPEN_FAILED.to_string()
    })
}

#[cfg(not(unix))]
fn set_private_file_permissions(_path: &Path) -> Result<(), String> {
    Ok(())
}

fn now_unix_ns() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos().min(i64::MAX as u128) as i64)
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_db_path(name: &str) -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir()
            .join(format!("proton-drive-sync-db-{name}-{nonce}"))
            .join("sync-state.sqlite3")
    }

    #[test]
    fn hashes_are_stable_and_do_not_expose_raw_values() {
        let first = hash_sensitive("/home/user/Pictures/private.jpg");
        let second = hash_sensitive("/home/user/Pictures/private.jpg");

        assert_eq!(first, second);
        assert_eq!(first.len(), 64);
        assert!(!first.contains("private"));
    }

    #[test]
    fn opens_database_with_schema_and_private_permissions() {
        let path = temp_db_path("schema");
        let db = SyncDb::open(&path).unwrap();
        let version: String = db
            .conn
            .query_row(
                "SELECT value FROM sync_meta WHERE key = 'schema_version'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(version, SCHEMA_VERSION.to_string());

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = fs::metadata(&path).unwrap().permissions().mode() & 0o777;
            assert_eq!(mode, 0o600);
        }

        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }

    #[test]
    fn stores_metadata_without_raw_paths_or_remote_ids() {
        let path = temp_db_path("privacy");
        let db = SyncDb::open(&path).unwrap();
        let root = Path::new("/home/alice/Pictures/protondrive-sync-smoke");
        let relative = Path::new("family/private-vacation.jpg");
        let root_id = db
            .upsert_computers_root(root, "alice-laptop", "linux")
            .unwrap();

        db.upsert_local_item(
            &root_id,
            relative,
            "file",
            Some(42),
            Some(123),
            Some("content-fingerprint"),
            SyncItemState::LocalPending,
        )
        .unwrap();
        db.link_remote_item(
            &root_id,
            relative,
            RemoteItemRef {
                volume_id: Some("volume-secret"),
                share_id: Some("share-secret"),
                link_id: Some("link-secret"),
                parent_id: Some("parent-secret"),
                revision: Some("etag-secret"),
            },
        )
        .unwrap();

        let item = db.get_item(&root_id, relative).unwrap().unwrap();
        assert_eq!(item.state, SyncItemState::LocalPending);
        assert_eq!(item.local_size, Some(42));
        assert_ne!(item.relative_path_hash, relative.to_string_lossy());
        assert_ne!(item.remote_link_id_hash.as_deref(), Some("link-secret"));
        drop(db);

        let bytes = fs::read(&path).unwrap();
        let db_file = String::from_utf8_lossy(&bytes);
        assert!(!db_file.contains("private-vacation"));
        assert!(!db_file.contains("/home/alice"));
        assert!(!db_file.contains("alice-laptop"));
        assert!(!db_file.contains("link-secret"));
        assert!(!db_file.contains("share-secret"));

        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }

    #[test]
    fn computers_root_stores_device_scope_without_remote_path() {
        let path = temp_db_path("computers-root");
        let db = SyncDb::open(&path).unwrap();
        let root_id = db
            .upsert_computers_root(
                Path::new("/home/alice/ProtonDrive"),
                "alice-laptop",
                "linux",
            )
            .unwrap();

        let (remote_scope, device_type, device_name_hash, remote_path_hash): (
            String,
            Option<String>,
            Option<String>,
            Option<String>,
        ) = db
            .conn
            .query_row(
                "SELECT remote_scope, device_type, device_name_hash, remote_path_hash
                 FROM sync_roots WHERE id = ?1",
                params![root_id],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .unwrap();

        assert_eq!(remote_scope, REMOTE_SCOPE_COMPUTERS);
        assert_eq!(device_type.as_deref(), Some("linux"));
        assert_eq!(
            device_name_hash.as_deref(),
            Some(hash_sensitive("alice-laptop").as_str())
        );
        assert!(remote_path_hash.is_none());

        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }

    #[test]
    fn my_files_mapping_stores_remote_path_hash_without_device_name() {
        let path = temp_db_path("my-files-root");
        let db = SyncDb::open(&path).unwrap();
        let root_id = db
            .upsert_my_files_mapping(Path::new("/home/alice/Pictures"), "Pictures/Linux")
            .unwrap();

        let (remote_scope, device_name_hash, remote_path_hash): (
            String,
            Option<String>,
            Option<String>,
        ) = db
            .conn
            .query_row(
                "SELECT remote_scope, device_name_hash, remote_path_hash
                 FROM sync_roots WHERE id = ?1",
                params![root_id],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .unwrap();

        assert_eq!(remote_scope, REMOTE_SCOPE_MY_FILES);
        assert!(device_name_hash.is_none());
        assert_eq!(
            remote_path_hash.as_deref(),
            Some(hash_sensitive("Pictures/Linux").as_str())
        );

        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }

    #[test]
    fn generic_root_upsert_preserves_existing_remote_mapping() {
        let path = temp_db_path("preserve-root-mapping");
        let db = SyncDb::open(&path).unwrap();
        let root = Path::new("/home/alice/ProtonDrive");
        let root_id = db
            .upsert_computers_root(root, "alice-laptop", "linux")
            .unwrap();

        assert_eq!(db.upsert_root(root).unwrap(), root_id);

        let remote_scope: String = db
            .conn
            .query_row(
                "SELECT remote_scope FROM sync_roots WHERE id = ?1",
                params![root_id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(remote_scope, REMOTE_SCOPE_COMPUTERS);

        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }

    #[test]
    fn tombstone_requires_existing_known_item() {
        let path = temp_db_path("tombstone");
        let db = SyncDb::open(&path).unwrap();
        let root_id = db
            .upsert_root(Path::new("/home/alice/ProtonDrive"))
            .unwrap();
        let relative = Path::new("delete-me.txt");

        assert!(!db.mark_tombstone(&root_id, relative).unwrap());

        db.upsert_local_item(
            &root_id,
            relative,
            "file",
            Some(1),
            Some(2),
            None,
            SyncItemState::Synced,
        )
        .unwrap();
        assert!(db.mark_tombstone(&root_id, relative).unwrap());
        let item = db.get_item(&root_id, relative).unwrap().unwrap();
        assert_eq!(item.state, SyncItemState::Tombstone);

        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }

    #[test]
    fn pending_items_returns_actionable_states_only() {
        let path = temp_db_path("pending");
        let db = SyncDb::open(&path).unwrap();
        let root_id = db
            .upsert_root(Path::new("/home/alice/ProtonDrive"))
            .unwrap();

        db.upsert_local_item(
            &root_id,
            Path::new("synced.txt"),
            "file",
            Some(1),
            Some(1),
            None,
            SyncItemState::Synced,
        )
        .unwrap();
        db.upsert_local_item(
            &root_id,
            Path::new("pending.txt"),
            "file",
            Some(1),
            Some(1),
            None,
            SyncItemState::LocalPending,
        )
        .unwrap();

        let pending = db.pending_items(&root_id).unwrap();
        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].state, SyncItemState::LocalPending);

        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }
}
