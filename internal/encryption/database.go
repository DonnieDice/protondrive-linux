package encryption

import (
	"database/sql"
	"fmt"
	"net/url" // For URL encoding to safely pass key in DSN
	"encoding/hex"

	_ "github.com/mutecomm/go-sqlcipher/v4" // Import for SQLCipher driver
)

const (
	// DefaultKDFIterations is the recommended number of KDF iterations for SQLCipher.
	DefaultKDFIterations = 256000
	// DefaultCipherPageSize is the default page size for SQLCipher database.
	DefaultCipherPageSize = 4096
)

// OpenEncryptedDB opens and initializes an SQLCipher database with the provided key.
func OpenEncryptedDB(dbPath string, key []byte) (*sql.DB, error) {
	if len(key) == 0 {
		return nil, fmt.Errorf("encryption key cannot be empty")
	}

	// Hex-encode the key to safely pass it in the DSN.
	// This prevents issues with special characters in the key.
	keyHex := hex.EncodeToString(key)

	// Construct the DSN (Data Source Name) for SQLCipher.
	// The key is passed directly as a URI parameter.
	// We also set other PRAGMA options directly in the DSN for initial setup.
	// Note: Some PRAGMAs might not be supported directly in the DSN or have different syntax.
	// We'll stick to the core ones that are generally supported.
	// For example, "_pragma_cipher_page_size=..." is a common DSN parameter.
	dsn := fmt.Sprintf("file:%s?_pragma_key=X'%s'&_pragma_cipher_page_size=%d&_pragma_kdf_iter=%d&_pragma_cipher=aes-256-gcm&_pragma_hmac_use=1&_pragma_journal_mode=WAL&_pragma_foreign_keys=ON",
		url.PathEscape(dbPath), keyHex, DefaultCipherPageSize, DefaultKDFIterations)

	db, err := sql.Open("sqlite3", dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to open database with DSN: %w", err)
	}

	// After opening, a simple query to verify access.
	// If the DSN was correct and the key worked, this should succeed.
	_, err = db.Exec("SELECT 1;")
	if err != nil {
		db.Close()
		return nil, fmt.Errorf("failed to verify database access (incorrect key or corrupted database): %w", err)
	}

	return db, nil
}

// CloseEncryptedDB closes the encrypted database connection.
func CloseEncryptedDB(db *sql.DB) error {
	if db == nil {
		return nil
	}
	return db.Close()
}

// TODO: Add function for key rotation (re-encrypting the database with a new key)
