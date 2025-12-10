package security

import (
	"bytes"
	"fmt"
	"io/ioutil"
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/yourusername/protondrive-linux/internal/encryption" // Assuming internal/encryption has DecryptCacheFile or similar
)

// AssertFileIsEncrypted verifies that a given file is indeed encrypted.
// It tries to decrypt the file with a correct key (which should succeed)
// and with an incorrect key (which should fail).
//
// decryptFunc is a function that takes a file path and a key, and returns
// the decrypted bytes or an error. This allows it to be used for different
// types of encrypted files (e.g., cache files, database files via a specific API).
func AssertFileIsEncrypted(t *testing.T, filePath string, correctKey, incorrectKey []byte, decryptFunc func(string, []byte) ([]byte, error)) {
	t.Helper()

	assert.FileExists(t, filePath, "Encrypted file should exist")

	// 1. Try to decrypt with the incorrect key (should fail)
	_, err := decryptFunc(filePath, incorrectKey)
	assert.Error(t, err, "Decryption with incorrect key should fail")
	assert.Contains(t, err.Error(), "incorrect key", "Error message should indicate incorrect key") // Specific error from internal/encryption.DecryptCacheFile

	// 2. Try to decrypt with the correct key (should succeed)
	_, err = decryptFunc(filePath, correctKey)
	assert.NoError(t, err, "Decryption with correct key should succeed")
}

// AssertFileContainsNoPlaintext checks that a raw file on disk does not contain specific plaintext strings.
// This is useful for verifying that sensitive data (like filenames or content snippets) is not
// accidentally written to disk unencrypted.
func AssertFileContainsNoPlaintext(t *testing.T, filePath string, sensitiveStrings []string) {
	t.Helper()

	fileContent, err := ioutil.ReadFile(filePath)
	assert.NoError(t, err, fmt.Sprintf("Failed to read file %s", filePath))

	for _, s := range sensitiveStrings {
		assert.NotContains(t, string(fileContent), s, fmt.Sprintf("File %s should not contain plaintext: %s", filePath, s))
	}
}

// AssertMemoryWiped checks if a byte slice has been securely wiped (zeroed out).
func AssertMemoryWiped(t *testing.T, data []byte) {
	t.Helper()

	for i, b := range data {
		assert.Equal(t, byte(0), b, fmt.Sprintf("Byte at index %d was not wiped (expected 0, got %d)", i, b))
	}
}

// GenerateTestKey creates a test key. It wraps testutil.GenerateTestKey.
func GenerateTestKey(t *testing.T) []byte {
	t.Helper()
	key := make([]byte, encryption.KeySize)
	_, err := rand.Read(key)
	if err != nil {
		t.Fatalf("failed to generate random test key: %v", err)
	}
	return key
}

// GenerateIncorrectKey generates an incorrect key that is guaranteed to be different from the correctKey.
func GenerateIncorrectKey(t *testing.T, correctKey []byte) []byte {
	t.Helper()
	incorrectKey := make([]byte, encryption.KeySize)
	_, err := rand.Read(incorrectKey)
	if err != nil {
		t.Fatalf("failed to generate random incorrect key: %v", err)
	}
	// Ensure keys are different
	for bytes.Equal(correctKey, incorrectKey) {
		_, err = rand.Read(incorrectKey)
		if err != nil {
			t.Fatalf("failed to generate random incorrect key: %v", err)
		}
	}
	return incorrectKey
}