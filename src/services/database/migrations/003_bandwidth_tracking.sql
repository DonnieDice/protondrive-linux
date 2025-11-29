-- Migration 003: Bandwidth Tracking

CREATE TABLE IF NOT EXISTS bandwidth_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    upload_bytes INTEGER DEFAULT 0,
    download_bytes INTEGER DEFAULT 0,
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
);

-- Index for quick lookup of usage by user and time
CREATE INDEX IF NOT EXISTS idx_bandwidth_usage_user_id_timestamp ON bandwidth_usage(user_id, timestamp);
