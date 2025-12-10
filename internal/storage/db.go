package storage

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	_ "github.com/mutecomm/go-sqlcipher/v4" // SQLCipher driver
)

const (
	DBFileName = "state.db"
	AppName    = "protondrive-linux"
)

// DB represents the database connection and operations.
type DB struct {
	db *sql.DB
}

// dbPathResolver is a function type for resolving the database file path.
type dbPathResolver func() (string, error)

// defaultDBPathResolver is the default function for resolving the database file path.
// It uses os.UserCacheDir() as per FHS for state data.
var defaultDBPathResolver dbPathResolver = func() (string, error) {
	dataDir, err := os.UserCacheDir()
	if err != nil {
		return "", fmt.Errorf("failed to get user cache directory: %w", err)
	}
	appDataDir := filepath.Join(dataDir, AppName)
	return filepath.Join(appDataDir, DBFileName), nil
}

// GetDefaultDBPath returns the full path to the SQLite database file using the default resolver.
func GetDefaultDBPath() (string, error) {
	return defaultDBPathResolver()
}

// SetDBPathResolver allows injecting a custom database path resolver for testing.
func SetDBPathResolver(resolver dbPathResolver) {
	defaultDBPathResolver = resolver
}

// ResetDBPathResolver resets the database path resolver to its default implementation.
func ResetDBPathResolver() {
	defaultDBPathResolver = func() (string, error) {
		dataDir, err := os.UserCacheDir()
		if err != nil {
			return "", fmt.Errorf("failed to get user cache directory: %w", err)
		}
		appDataDir := filepath.Join(dataDir, AppName)
		return filepath.Join(appDataDir, DBFileName), nil
	}
}

// NewDB creates a new database connection and applies migrations.
// It now accepts an encryption key for SQLCipher. If the key is nil or empty, the database will not be encrypted.
func NewDB(schemaFilePath string, key []byte) (*DB, error) {
	dbPath, err := defaultDBPathResolver() // Use the resolver here
	if err != nil {
		return nil, fmt.Errorf("failed to get database path: %w", err)
	}

	// Ensure the database directory exists
	dbDir := filepath.Dir(dbPath)
	if err := os.MkdirAll(dbDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create database directory %s: %w", dbDir, err)
	}

	// Open the database connection
	// _pragma=foreign_keys(1) enables foreign key constraints.
	// _pragma=journal_mode(WAL) uses Write-Ahead Logging for better concurrency.
	connStr := fmt.Sprintf("file:%s?_pragma=foreign_keys(1)&_pragma=journal_mode(WAL)", dbPath)

	// SQLCipher specific PRAGMAs
	if len(key) > 0 {
		keyHex := ""
		for _, b := range key {
			keyHex += fmt.Sprintf("%02x", b)
		}
		connStr += fmt.Sprintf("&_pragma_key='x''%s''')&_pragma_cipher_page_size=4096&_pragma_kdf_iter=256000&_pragma_cipher='aes-256-gcm'", keyHex)
	}

	db, err := sql.Open("sqlite3", connStr) // Changed driver to "sqlite3"
	if err != nil {
		return nil, fmt.Errorf("failed to open database connection: %w", err)
	}

	// Ping to verify connection
	if err := db.Ping(); err != nil {
		db.Close()
		return nil, fmt.Errorf("failed to connect to database: %w", err)
	}

	// Read schema content from the schema.sql file
	schemaContent, err := os.ReadFile(schemaFilePath)
	if err != nil {
		db.Close()
		return nil, fmt.Errorf("failed to read schema file %s: %w", schemaFilePath, err)
	}

	// Apply schema (initial migration)
	if err := ApplyMigrations(db, string(schemaContent)); err != nil {
		db.Close()
		return nil, fmt.Errorf("failed to apply database schema: %w", err)
	}

	return &DB{db: db}, nil
}

// Close closes the database connection.
func (s *DB) Close() error {
	if s.db != nil {
		return s.db.Close()
	}
	return nil
}

// GetDB returns the underlying *sql.DB instance.
// This is primarily for testing or advanced usage where direct database access is required.
func (s *DB) GetDB() *sql.DB {
	return s.db
}

// ApplyMigrations executes the provided SQL schema content.
// It splits the content into individual statements and executes them one by one.
func ApplyMigrations(db *sql.DB, schemaContent string) error {
	statements := strings.Split(schemaContent, ";")

	for _, stmt := range statements {
		stmt = strings.TrimSpace(stmt)
		if stmt == "" {
			continue // Skip empty statements
		}
		_, err := db.Exec(stmt)
		if err != nil {
			return fmt.Errorf("failed to execute SQL statement '%s': %w", stmt, err)
		}
	}
	return nil
}

// SaveFile saves or updates a FileMetadata record.
func (s *DB) SaveFile(file FileMetadata) error {
	// Convert time.Time to Unix timestamp for storage
	modTimeUnix := file.ModTime.Unix()
	createdAtUnix := file.CreatedAt.Unix()
	updatedAtUnix := time.Now().Unix() // Update updated_at on save

	stmt, err := s.db.Prepare(`
		INSERT INTO files (id, name, size, mod_time, is_dir, hash, remote_path, local_path, sync_status, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET
			name = EXCLUDED.name,
			size = EXCLUDED.size,
			mod_time = EXCLUDED.mod_time,
			is_dir = EXCLUDED.is_dir,
			hash = EXCLUDED.hash,
			remote_path = EXCLUDED.remote_path,
			local_path = EXCLUDED.local_path,
			sync_status = EXCLUDED.sync_status,
			updated_at = EXCLUDED.updated_at;
	`)
	if err != nil {
		return fmt.Errorf("failed to prepare save file statement: %w", err)
	}
	defer stmt.Close()

	_, err = stmt.Exec(
		file.ID, file.Name, file.Size, modTimeUnix, file.IsDir, file.Hash,
		file.RemotePath, file.LocalPath, file.SyncStatus, createdAtUnix, updatedAtUnix,
	)
	if err != nil {
		return fmt.Errorf("failed to execute save file statement: %w", err)
	}
	return nil
}

// GetFile retrieves a FileMetadata record by ID.
func (s *DB) GetFile(id string) (*FileMetadata, error) {
	row := s.db.QueryRow(`
		SELECT id, name, size, mod_time, is_dir, hash, remote_path, local_path, sync_status, created_at, updated_at
		FROM files WHERE id = ?;
	`, id)

	var file FileMetadata
	var modTimeUnix, createdAtUnix, updatedAtUnix int64
	err := row.Scan(
		&file.ID, &file.Name, &file.Size, &modTimeUnix, &file.IsDir, &file.Hash,
		&file.RemotePath, &file.LocalPath, &file.SyncStatus, &createdAtUnix, &updatedAtUnix,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // File not found
		}
		return nil, fmt.Errorf("failed to scan file metadata: %w", err)
	}

	file.ModTime = time.Unix(modTimeUnix, 0)
	file.CreatedAt = time.Unix(createdAtUnix, 0)
	file.UpdatedAt = time.Unix(updatedAtUnix, 0)

	return &file, nil
}

// ListFiles lists all FileMetadata records.
func (s *DB) ListFiles() ([]FileMetadata, error) {
	rows, err := s.db.Query(`
		SELECT id, name, size, mod_time, is_dir, hash, remote_path, local_path, sync_status, created_at, updated_at
		FROM files;
	`)
	if err != nil {
		return nil, fmt.Errorf("failed to query files: %w", err)
	}
	defer rows.Close()

	var files []FileMetadata
	for rows.Next() {
		var file FileMetadata
		var modTimeUnix, createdAtUnix, updatedAtUnix int64
		err := rows.Scan(
			&file.ID, &file.Name, &file.Size, &modTimeUnix, &file.IsDir, &file.Hash,
			&file.RemotePath, &file.LocalPath, &file.SyncStatus, &createdAtUnix, &updatedAtUnix,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan file metadata in ListFiles: %w", err)
		}
		file.ModTime = time.Unix(modTimeUnix, 0)
		file.CreatedAt = time.Unix(createdAtUnix, 0)
		file.UpdatedAt = time.Unix(updatedAtUnix, 0)
		files = append(files, file)
	}

	if err = rows.Err(); err != nil {
		return nil, fmt.Errorf("error during rows iteration in ListFiles: %w", err)
	}

	return files, nil
}

// DeleteFile deletes a FileMetadata record by ID.
func (s *DB) DeleteFile(id string) error {
	res, err := s.db.Exec(`DELETE FROM files WHERE id = ?;`, id)
	if err != nil {
		return fmt.Errorf("failed to execute delete file statement: %w", err)
	}

	rowsAffected, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected after delete: %w", err)
	}
	if rowsAffected == 0 {
		return fmt.Errorf("file with ID %s not found for deletion", id)
	}
	return nil
}