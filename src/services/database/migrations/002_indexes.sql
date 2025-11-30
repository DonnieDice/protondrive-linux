-- Migration: 002_indexes.sql
-- Description: Performance indexes for query optimization
-- Version: 2
-- Created: 2024-11-30

-- ============================================================================
-- USERS TABLE INDEXES
-- ============================================================================
-- Index for email lookups (login)
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- Index for last login tracking
CREATE INDEX IF NOT EXISTS idx_users_last_login ON users(last_login_at DESC);

-- ============================================================================
-- FILES TABLE INDEXES
-- ============================================================================
-- Index for user's files
CREATE INDEX IF NOT EXISTS idx_files_user_id ON files(user_id);

-- Index for parent folder lookups
CREATE INDEX IF NOT EXISTS idx_files_parent_id ON files(parent_id);

-- Index for file state filtering
CREATE INDEX IF NOT EXISTS idx_files_state ON files(state);

-- Index for file hash lookups (deduplication)
CREATE INDEX IF NOT EXISTS idx_files_hash ON files(hash) WHERE hash IS NOT NULL;

-- Index for local path lookups
CREATE INDEX IF NOT EXISTS idx_files_local_path ON files(local_path) WHERE local_path IS NOT NULL;

-- Index for remote path lookups
CREATE INDEX IF NOT EXISTS idx_files_remote_path ON files(remote_path);

-- Composite index for user's files by state
CREATE INDEX IF NOT EXISTS idx_files_user_state ON files(user_id, state);

-- Index for recently modified files
CREATE INDEX IF NOT EXISTS idx_files_modified_at ON files(modified_at DESC);

-- Index for sync status
CREATE INDEX IF NOT EXISTS idx_files_synced_at ON files(synced_at DESC) WHERE synced_at IS NOT NULL;

-- ============================================================================
-- FOLDERS TABLE INDEXES
-- ============================================================================
-- Index for user's folders
CREATE INDEX IF NOT EXISTS idx_folders_user_id ON folders(user_id);

-- Index for parent folder lookups
CREATE INDEX IF NOT EXISTS idx_folders_parent_id ON folders(parent_id);

-- Index for folder state filtering
CREATE INDEX IF NOT EXISTS idx_folders_state ON folders(state);

-- Index for local path lookups
CREATE INDEX IF NOT EXISTS idx_folders_local_path ON folders(local_path) WHERE local_path IS NOT NULL;

-- Index for remote path lookups
CREATE INDEX IF NOT EXISTS idx_folders_remote_path ON folders(remote_path);

-- Composite index for user's folders by state
CREATE INDEX IF NOT EXISTS idx_folders_user_state ON folders(user_id, state);

-- ============================================================================
-- SYNC_QUEUE TABLE INDEXES
-- ============================================================================
-- Index for user's sync queue
CREATE INDEX IF NOT EXISTS idx_sync_queue_user_id ON sync_queue(user_id);

-- Index for queue status filtering
CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue(status);

-- Index for priority ordering
CREATE INDEX IF NOT EXISTS idx_sync_queue_priority ON sync_queue(priority DESC, created_at ASC);

-- Composite index for pending items by priority
CREATE INDEX IF NOT EXISTS idx_sync_queue_pending ON sync_queue(status, priority DESC, created_at ASC) 
  WHERE status = 'pending';

-- Index for file sync operations
CREATE INDEX IF NOT EXISTS idx_sync_queue_file_id ON sync_queue(file_id) WHERE file_id IS NOT NULL;

-- Index for folder sync operations
CREATE INDEX IF NOT EXISTS idx_sync_queue_folder_id ON sync_queue(folder_id) WHERE folder_id IS NOT NULL;

-- Index for retry tracking
CREATE INDEX IF NOT EXISTS idx_sync_queue_retry ON sync_queue(retry_count, status);

-- ============================================================================
-- CONFLICTS TABLE INDEXES
-- ============================================================================
-- Index for user's conflicts
CREATE INDEX IF NOT EXISTS idx_conflicts_user_id ON conflicts(user_id);

-- Index for file conflicts
CREATE INDEX IF NOT EXISTS idx_conflicts_file_id ON conflicts(file_id);

-- Index for unresolved conflicts
CREATE INDEX IF NOT EXISTS idx_conflicts_unresolved ON conflicts(resolved_at) WHERE resolved_at IS NULL;

-- Index for conflict type filtering
CREATE INDEX IF NOT EXISTS idx_conflicts_type ON conflicts(conflict_type);

-- Composite index for user's unresolved conflicts
CREATE INDEX IF NOT EXISTS idx_conflicts_user_unresolved ON conflicts(user_id, resolved_at) 
  WHERE resolved_at IS NULL;

-- ============================================================================
-- SYNC_HISTORY TABLE INDEXES
-- ============================================================================
-- Index for user's sync history
CREATE INDEX IF NOT EXISTS idx_sync_history_user_id ON sync_history(user_id);

-- Index for recent sync operations
CREATE INDEX IF NOT EXISTS idx_sync_history_started_at ON sync_history(started_at DESC);

-- Index for sync status filtering
CREATE INDEX IF NOT EXISTS idx_sync_history_status ON sync_history(status);

-- Composite index for user's recent syncs
CREATE INDEX IF NOT EXISTS idx_sync_history_user_recent ON sync_history(user_id, started_at DESC);

-- Index for failed syncs
CREATE INDEX IF NOT EXISTS idx_sync_history_failed ON sync_history(status, started_at DESC) 
  WHERE status = 'failed';

-- ============================================================================
-- SETTINGS TABLE INDEXES
-- ============================================================================
-- Primary key on 'key' already provides index
-- No additional indexes needed for settings table
