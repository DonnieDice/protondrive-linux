package encryption

import (
	"database/sql"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestOpenEncryptedDB_Success(t *testing.T) {
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "test.db")
	
	key := []byte("averysecretkeyforatest1234567890") // 32 bytes for simplicity in test
	
	db, err := OpenEncryptedDB(dbPath, key)
	assert.NoError(t, err)
	assert.NotNil(t, db)

	// Try to write some data
	_, err = db.Exec("CREATE TABLE IF NOT EXISTS test_table (id INTEGER PRIMARY KEY, value TEXT);")
	assert.NoError(t, err)
	_, err = db.Exec("INSERT INTO test_table (value) VALUES (?);", "test_value")
	assert.NoError(t, err)

	err = CloseEncryptedDB(db)
	assert.NoError(t, err)

	// Re-open with the same key to verify persistence and decryption
	db, err = OpenEncryptedDB(dbPath, key)
	assert.NoError(t, err)
	assert.NotNil(t, db)

	var value string
	err = db.QueryRow("SELECT value FROM test_table WHERE id = 1;").Scan(&value)
	assert.NoError(t, err)
	assert.Equal(t, "test_value", value)

	err = CloseEncryptedDB(db)
	assert.NoError(t, err)
}

func TestOpenEncryptedDB_IncorrectKey(t *testing.T) {
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "test.db")
	
	correctKey := []byte("averysecretkeyforatest1234567890")
	incorrectKey := []byte("wrongkeyforatest0987654321fedcba")
	
	// First, create and encrypt the database with the correct key
	db, err := OpenEncryptedDB(dbPath, correctKey)
	assert.NoError(t, err)
	assert.NotNil(t, db)
	_, err = db.Exec("CREATE TABLE IF NOT EXISTS sensitive_data (id INTEGER PRIMARY KEY, secret TEXT);")
	assert.NoError(t, err)
	err = CloseEncryptedDB(db)
	assert.NoError(t, err)

	// Now, try to open it with the incorrect key
	dbIncorrect, err := OpenEncryptedDB(dbPath, incorrectKey)
	assert.Error(t, err) // Expect an error
	assert.Nil(t, dbIncorrect)
	assert.Contains(t, err.Error(), "incorrect key or corrupted database")

	// Ensure the database file exists
	_, err = os.Stat(dbPath)
	assert.NoError(t, err) // File should still exist
}

func TestOpenEncryptedDB_EmptyKey(t *testing.T) {
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "test.db")
	
	emptyKey := []byte{} // Empty key
	
	db, err := OpenEncryptedDB(dbPath, emptyKey)
	assert.Error(t, err)
	assert.Nil(t, db)
	assert.Contains(t, err.Error(), "encryption key cannot be empty")
	
	// Ensure no database file was created for an empty key attempt
	_, err = os.Stat(dbPath)
	assert.True(t, os.IsNotExist(err))
}

func TestCloseEncryptedDB_ValidConnection(t *testing.T) {
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "test.db")
	key := []byte("anothersupersecretkey1234567890")
	
	db, err := OpenEncryptedDB(dbPath, key)
	assert.NoError(t, err)
	assert.NotNil(t, db)

	err = CloseEncryptedDB(db)
	assert.NoError(t, err)
}

func TestCloseEncryptedDB_NilConnection(t *testing.T) {
	var db *sql.DB = nil
	err := CloseEncryptedDB(db)
	assert.NoError(t, err) // Should not panic or return error for nil
}
