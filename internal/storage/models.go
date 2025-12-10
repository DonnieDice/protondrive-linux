package storage

import (
	"time"
)

// SyncStatus represents the synchronization status of a file.
type SyncStatus int

const (
	SyncPending SyncStatus = iota // Waiting to be synced
	SyncInProgress                // Currently being uploaded/downloaded
	SyncComplete                  // Successfully synced
	SyncFailed                    // Failed to sync
	SyncSkipped                   // Skipped due to conflict or user action
	SyncDeleted                   // Marked for deletion on remote/local
)

// FileMetadata holds all the metadata for a file or folder in the sync directory.
type FileMetadata struct {
	ID          string     // Unique ID from ProtonDrive API
	Name        string     // Base name of the file/folder
	Size        int64      // Size in bytes
	ModTime     time.Time  // Last modification time
	IsDir       bool       // True if it's a directory
	Hash        string     // SHA-256 hash of the file content (for files)
	RemotePath  string     // Full path on ProtonDrive
	LocalPath   string     // Full path on local filesystem
	SyncStatus  SyncStatus // Current sync status
	CreatedAt   time.Time  // Timestamp when record was created in DB
	UpdatedAt   time.Time  // Timestamp when record was last updated in DB
}