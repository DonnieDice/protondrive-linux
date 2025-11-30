-- Migration: 001_initial_schema.sql
-- Description: Initial database schema for ProtonDrive Linux
-- Version: 1
-- Created: 2024-11-30

-- ============================================================================
-- USERS TABLE
-- ============================================================================
-- Stores authenticated user information
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  name TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  last_login_at INTEGER
);

-- ============================================================================
-- FILES TABLE
-- ============================================================================
-- Stores file metadata for synced files
CREATE TABLE IF NOT EXISTS files (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  parent_id TEXT,
  name TEXT NOT NULL,
  mime_type TEXT,
  size INTEGER NOT NULL DEFAULT 0,
  hash TEXT,
  local_path TEXT,
  remote_path TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'pending',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  modified_at INTEGER NOT NULL,
  synced_at INTEGER,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (parent_id) REFERENCES files(id) ON DELETE CASCADE
);

-- ============================================================================
-- FOLDERS TABLE
-- ============================================================================
-- Stores folder metadata
CREATE TABLE IF NOT EXISTS folders (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  parent_id TEXT,
  name TEXT NOT NULL,
  local_path TEXT,
  remote_path TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'synced',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  synced_at INTEGER,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (parent_id) REFERENCES folders(id) ON DELETE CASCADE
);

-- ============================================================================
-- SYNC_QUEUE TABLE
-- ============================================================================
-- Queue for pending sync operations
CREATE TABLE IF NOT EXISTS sync_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL,
  file_id TEXT,
  folder_id TEXT,
  operation TEXT NOT NULL,
  priority INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending',
  retry_count INTEGER NOT NULL DEFAULT 0,
  error_message TEXT,
  created_at INTEGER NOT NULL,
  started_at INTEGER,
  completed_at INTEGER,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE,
  FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE CASCADE
);

-- ============================================================================
-- CONFLICTS TABLE
-- ============================================================================
-- Stores sync conflicts that need resolution
CREATE TABLE IF NOT EXISTS conflicts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL,
  file_id TEXT NOT NULL,
  conflict_type TEXT NOT NULL,
  local_version TEXT,
  remote_version TEXT,
  resolution TEXT,
  resolved_at INTEGER,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE
);

-- ============================================================================
-- SETTINGS TABLE
-- ============================================================================
-- Application settings and preferences
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

-- ============================================================================
-- SYNC_HISTORY TABLE
-- ============================================================================
-- History of sync operations for debugging and analytics
CREATE TABLE IF NOT EXISTS sync_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL,
  operation TEXT NOT NULL,
  file_count INTEGER NOT NULL DEFAULT 0,
  bytes_transferred INTEGER NOT NULL DEFAULT 0,
  duration_ms INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL,
  error_message TEXT,
  started_at INTEGER NOT NULL,
  completed_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ============================================================================
-- INITIAL DATA
-- ============================================================================
-- Insert default settings
INSERT OR IGNORE INTO settings (key, value, updated_at) VALUES
  ('schema_version', '1', strftime('%s', 'now')),
  ('app_version', '1.0.0', strftime('%s', 'now')),
  ('sync_enabled', 'true', strftime('%s', 'now')),
  ('auto_sync_interval', '300', strftime('%s', 'now')),
  ('max_concurrent_uploads', '3', strftime('%s', 'now')),
  ('max_concurrent_downloads', '5', strftime('%s', 'now'));
