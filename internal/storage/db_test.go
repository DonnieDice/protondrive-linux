package storage_test

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"
	"crypto/rand" // Added for key generation

	"github.com/stretchr/testify/assert"

	"github.com/yourusername/protondrive-linux/internal/encryption" // Added for encryption constants
	"github.com/yourusername/protondrive-linux/internal/storage" // Import the storage package
)

// Helper function to get the absolute path to schema.sql
func getAbsolutePathToSchemaSQL(t *testing.T) string {
	t.Helper()
	// Get the directory of the current test file
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatalf("failed to get current file information")
	}
	currentDir := filepath.Dir(filename)

	// schema.sql is always in the same directory as db.go and db_test.go (i.e., internal/storage)
	schemaPath := filepath.Join(currentDir, "schema.sql")

	// Verify it exists
	if _, err := os.Stat(schemaPath); os.IsNotExist(err) {
		t.Fatalf("schema.sql not found at %s", schemaPath)
	}
	return schemaPath
}

// Helper function to create a temporary database for testing
func setupTestDB(t *testing.T, encryptionKey []byte) (*storage.DB, string, []byte, func()) {
	t.Helper()
	tempDir := t.TempDir()
	dbFilePath := filepath.Join(tempDir, storage.DBFileName)

	// Determine the path to schema.sql reliably
	schemaFilePath := getAbsolutePathToSchemaSQL(t)
	t.Logf("DEBUG: schemaFilePath: %s", schemaFilePath)
	
	// Inject a custom DB path resolver for this test
	storage.SetDBPathResolver(func() (string, error) {
		return dbFilePath, nil
	})

	// Read schema content
	schemaContent, err := os.ReadFile(schemaFilePath)
	assert.NoError(t, err)
	// t.Logf("DEBUG: schemaContent (first 100 chars): %s...", schemaContent[:100]) // Removed due to potential truncation issues in log

	// If no encryption key is provided, generate a random one for encrypted tests
	if len(encryptionKey) == 0 {
		encryptionKey = make([]byte, encryption.KeySize)
		_, err := rand.Read(encryptionKey)
		assert.NoError(t, err, "failed to generate random encryption key")
	}

	db, err := storage.NewDB(schemaFilePath, encryptionKey) // Pass the schema file path and key
	t.Logf("DEBUG: NewDB returned db: %v, err: %v", db, err)
	assert.NoError(t, err)
	assert.NotNil(t, db)

	cleanup := func() {
		db.Close()
		os.RemoveAll(tempDir)
		storage.ResetDBPathResolver() // Reset to default after the test
	}

	return db, dbFilePath, encryptionKey, cleanup
}

func TestGetDefaultDBPath(t *testing.T) {
	t.Logf("DEBUG: Starting TestGetDefaultDBPath")
	tempDir := t.TempDir()
	originalUserCacheDir := os.Getenv("XDG_CACHE_HOME")
	os.Setenv("XDG_CACHE_HOME", tempDir) // Mock XDG_CACHE_HOME
	defer os.Setenv("XDG_CACHE_HOME", originalUserCacheDir) // Restore env var

	dbPath, err := storage.GetDefaultDBPath() // Use the default resolver
	assert.NoError(t, err)

	expectedPath := filepath.Join(tempDir, storage.AppName, storage.DBFileName)
	assert.Equal(t, expectedPath, dbPath)
}

func TestNewDB(t *testing.T) {
	t.Logf("DEBUG: Starting TestNewDB")
	// Test successful creation
	db, schemaFilePath, key, cleanup := setupTestDB(t, nil) // Pass nil for key
	defer cleanup()
	assert.NotNil(t, db)
	assert.NotNil(t, db.GetDB())

	// Test opening an existing database
	db2, err := storage.NewDB(schemaFilePath, key) // Pass the encryption key
	assert.NoError(t, err)
	assert.NotNil(t, db2)
	db2.Close()
}

func TestNewDB_ErrorCreatingDir(t *testing.T) {
	t.Logf("DEBUG: Starting TestNewDB_ErrorCreatingDir")
	// setupTestDB creates a DB, so close it to avoid conflicts with custom resolver
	db, schemaFilePath, key, _ := setupTestDB(t, nil) // Get schemaFilePath and key from setupTestDB
	db.Close()

	// Inject a resolver that returns an uncreatable path
	storage.SetDBPathResolver(func() (string, error) {
		return "/root/uncreatable/path/state.db", nil // Assuming /root is not writable for tests
	})
	defer storage.ResetDBPathResolver() // Reset resolver after test

	// schemaFilePath is now passed to NewDB
	db, err := storage.NewDB(schemaFilePath, key)
	assert.Error(t, err)
	assert.Nil(t, db)
	assert.Contains(t, err.Error(), "failed to create database directory")
}

func TestCloseDB(t *testing.T) {
	t.Logf("DEBUG: Starting TestCloseDB")
	db, _, _, cleanup := setupTestDB(t, nil)
	// Don't defer cleanup yet, test Close explicitly
	assert.NoError(t, db.Close())

	// Ensure calling close again doesn't panic and returns nil/no error
	assert.NoError(t, db.Close())
	cleanup() // Now clean up temp files
}

func TestApplyMigrations(t *testing.T) {
	t.Logf("DEBUG: Starting TestApplyMigrations")
	tempDir := t.TempDir()
	dbFilePath := filepath.Join(tempDir, storage.DBFileName)

	// Inject resolver for this test
	storage.SetDBPathResolver(func() (string, error) {
		return dbFilePath, nil
	})
	defer storage.ResetDBPathResolver() // Reset resolver after test

	// Open a raw sql.DB connection for testing ApplyMigrations directly
	connStr := fmt.Sprintf("file:%s?_pragma=foreign_keys(1)&_pragma=journal_mode(WAL)", dbFilePath)
	db, err := sql.Open("sqlite", connStr)
	assert.NoError(t, err)
	defer db.Close()

	schemaContent, err := os.ReadFile("internal/storage/schema.sql")
	assert.NoError(t, err)

	// Test applying valid schema
	assert.NoError(t, storage.ApplyMigrations(db, string(schemaContent)))

	// Test idempotency (applying again should not error if schema is idempotent)
	assert.NoError(t, storage.ApplyMigrations(db, string(schemaContent)))

	// Test with invalid schema
	assert.Error(t, storage.ApplyMigrations(db, "CREATE TABLE invalid_syntax (id TEXT PRIMARY KEY;"))
}

func TestSaveAndGetFile(t *testing.T) {
	t.Logf("DEBUG: Starting TestSaveAndGetFile")
	db, _, _, cleanup := setupTestDB(t, nil)
	defer cleanup()

	now := time.Now().Truncate(time.Second) // Truncate to avoid sub-second differences
	file := storage.FileMetadata{
		ID:         "file123",
		Name:       "document.txt",
		Size:       1024,
		ModTime:    now,
		IsDir:      false,
		Hash:       "abc123def456",
		RemotePath: "/docs/document.txt",
		LocalPath:  "/home/user/sync/document.txt",
		SyncStatus: storage.SyncPending,
		CreatedAt:  now,
		UpdatedAt:  now,
	}

	// Test SaveFile (insert)
	assert.NoError(t, db.SaveFile(file))

	// Test GetFile
	retrievedFile, err := db.GetFile("file123")
	assert.NoError(t, err)
	assert.NotNil(t, retrievedFile)
	assert.Equal(t, file.ID, retrievedFile.ID)
	assert.Equal(t, file.Name, retrievedFile.Name)
	assert.Equal(t, file.Size, retrievedFile.Size)
	assert.Equal(t, file.ModTime.Unix(), retrievedFile.ModTime.Unix()) // Compare Unix for precision
	assert.Equal(t, file.IsDir, retrievedFile.IsDir)
	assert.Equal(t, file.Hash, retrievedFile.Hash)
	assert.Equal(t, file.RemotePath, retrievedFile.RemotePath)
	assert.Equal(t, file.LocalPath, retrievedFile.LocalPath)
	assert.Equal(t, file.SyncStatus, retrievedFile.SyncStatus)
	assert.InDelta(t, file.CreatedAt.Unix(), retrievedFile.CreatedAt.Unix(), 1) // Allow slight difference
	assert.InDelta(t, time.Now().Unix(), retrievedFile.UpdatedAt.Unix(), 1)     // UpdatedAt should be very recent

	// Test SaveFile (update)
	file.Name = "updated_document.txt"
	file.Size = 2048
	file.SyncStatus = storage.SyncComplete
	assert.NoError(t, db.SaveFile(file))

	retrievedFile, err = db.GetFile("file123")
	assert.NoError(t, err)
	assert.NotNil(t, retrievedFile)
	assert.Equal(t, file.Name, retrievedFile.Name)
	assert.Equal(t, file.Size, retrievedFile.Size)
	assert.Equal(t, file.SyncStatus, retrievedFile.SyncStatus)
}

func TestGetFile_NotFound(t *testing.T) {
	t.Logf("DEBUG: Starting TestGetFile_NotFound")
	db, _, _, cleanup := setupTestDB(t, nil)
	defer cleanup()

	file, err := db.GetFile("nonexistent")
	assert.NoError(t, err) // sql.ErrNoRows is handled, so no error returned
	assert.Nil(t, file)
}

func TestListFiles(t *testing.T) {
	t.Logf("DEBUG: Starting TestListFiles")
	db, _, _, cleanup := setupTestDB(t, nil)
	defer cleanup()

	files, err := db.ListFiles()
	assert.NoError(t, err)
	assert.Empty(t, files)

	now := time.Now().Truncate(time.Second)
	file1 := storage.FileMetadata{ID: "1", Name: "a.txt", ModTime: now, RemotePath: "/a.txt", LocalPath: "/l/a.txt", Hash: "h1", SyncStatus: storage.SyncComplete}
	file2 := storage.FileMetadata{ID: "2", Name: "b.txt", ModTime: now, RemotePath: "/b.txt", LocalPath: "/l/b.txt", Hash: "h2", SyncStatus: storage.SyncPending}
	assert.NoError(t, db.SaveFile(file1))
	assert.NoError(t, db.SaveFile(file2))

	files, err = db.ListFiles()
	assert.NoError(t, err)
	assert.Len(t, files, 2)
	// Check content, order is not guaranteed so just check presence
	found1 := false
	found2 := false
	for _, f := range files {
		if f.ID == file1.ID {
			found1 = true
			assert.Equal(t, file1.Name, f.Name)
		}
		if f.ID == file2.ID {
			found2 = true
			assert.Equal(t, file2.Name, f.Name)
		}
	}
	assert.True(t, found1)
	assert.True(t, found2)
}

func TestDeleteFile(t *testing.T) {
	t.Logf("DEBUG: Starting TestDeleteFile")
	db, _, _, cleanup := setupTestDB(t, nil)
	defer cleanup()

	now := time.Now().Truncate(time.Second)
	file := storage.FileMetadata{ID: "todelete", Name: "delete.me", ModTime: now, RemotePath: "/d.me", LocalPath: "/l/d.me", Hash: "h", SyncStatus: storage.SyncComplete}
	assert.NoError(t, db.SaveFile(file))

	// Test successful deletion
	assert.NoError(t, db.DeleteFile("todelete"))
	retrievedFile, err := db.GetFile("todelete")
	assert.NoError(t, err)
	assert.Nil(t, retrievedFile)

	// Test deleting non-existent file
	err = db.DeleteFile("nonexistent")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "not found for deletion")
}

func TestNewDB_Encrypted_IncorrectKey(t *testing.T) {
	t.Logf("DEBUG: Starting TestNewDB_Encrypted_IncorrectKey")
	tempDir := t.TempDir()
	dbFilePath := filepath.Join(tempDir, storage.DBFileName)
	schemaFilePath := getAbsolutePathToSchemaSQL(t)

	// Create a correct key
	correctKey := make([]byte, encryption.KeySize)
	_, err := rand.Read(correctKey)
	assert.NoError(t, err)

	// Create an incorrect key
	incorrectKey := make([]byte, encryption.KeySize)
	_, err = rand.Read(incorrectKey)
	assert.NoError(t, err)
	// Ensure keys are different
	for bytes.Equal(correctKey, incorrectKey) {
		_, err = rand.Read(incorrectKey)
		assert.NoError(t, err)
	}

	// 1. Create an encrypted database with correctKey
	db, err := storage.NewDB(schemaFilePath, correctKey)
	assert.NoError(t, err)
	assert.NotNil(t, db)
	db.Close() // Close the database after creation

	// 2. Attempt to open the database with an incorrect key
	db2, err := storage.NewDB(schemaFilePath, incorrectKey)
	assert.Error(t, err)
	assert.Nil(t, db2)
	assert.Contains(t, err.Error(), "file is encrypted or is not a database")

	// Clean up
	os.RemoveAll(tempDir)
}