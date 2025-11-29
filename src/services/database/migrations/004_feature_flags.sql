-- Migration 004: Feature Flags

CREATE TABLE IF NOT EXISTS feature_flags (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    flag_name TEXT UNIQUE NOT NULL,
    is_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    description TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Trigger to update 'updated_at' column automatically
CREATE TRIGGER IF NOT EXISTS update_feature_flags_updated_at
AFTER UPDATE ON feature_flags
FOR EACH ROW
BEGIN
    UPDATE feature_flags SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;
