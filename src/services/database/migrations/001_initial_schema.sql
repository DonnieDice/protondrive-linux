-- Migration 001: Initial Schema

CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    proton_id TEXT UNIQUE NOT NULL,
    email TEXT UNIQUE NOT NULL,
    display_name TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    file_id TEXT UNIQUE NOT NULL, -- ProtonDrive's internal file ID
    parent_id TEXT,             -- ProtonDrive's internal parent folder ID
    name TEXT NOT NULL,
    path TEXT NOT NULL,         -- Local path
    type TEXT NOT NULL,         -- 'file' or 'folder'
    size INTEGER,               -- Size in bytes for files
    etag TEXT,                  -- ETag for optimistic concurrency
    checksum TEXT,              -- Checksum for integrity verification
    last_modified TEXT,         -- Last modified timestamp from ProtonDrive
    local_last_modified TEXT,   -- Last modified timestamp of local file
    status TEXT NOT NULL,       -- 'syncing', 'synced', 'conflict', 'deleted'
    is_trashed BOOLEAN DEFAULT FALSE,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS sync_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    file_id TEXT,               -- Can be null for directory operations
    operation TEXT NOT NULL,    -- 'upload', 'download', 'delete', 'mkdir', 'rmdir'
    status TEXT NOT NULL,       -- 'success', 'failure', 'pending'
    message TEXT,
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
);

-- Index on file_id for faster lookups
CREATE INDEX IF NOT EXISTS idx_files_file_id ON files(file_id);
-- Index on parent_id for faster lookups of directory contents
CREATE INDEX IF NOT EXISTS idx_files_parent_id ON files(parent_id);
-- Index on user_id and path for efficient file system traversal
CREATE INDEX IF NOT EXISTS idx_files_user_id_path ON files(user_id, path);

-- Trigger to update 'updated_at' column automatically
CREATE TRIGGER IF NOT EXISTS update_files_updated_at
AFTER UPDATE ON files
FOR EACH ROW
BEGIN
    UPDATE files SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;
