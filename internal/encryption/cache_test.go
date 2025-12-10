package encryption

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
	"crypto/rand"

	"github.com/stretchr/testify/assert"
)

func TestEncryptDecryptCacheFile_Success(t *testing.T) {
	tempDir := t.TempDir()
	plaintextFilePath := filepath.Join(tempDir, "test_plaintext.txt")
	plaintextContent := []byte("This is some sensitive data that needs to be cached securely.")
	key := []byte("sixteenbytekey1234") // 16 bytes for AES-128, but we use 32 bytes KeySize

	// Adjust key to be KeySize (32 bytes)
	extendedKey := make([]byte, KeySize)
	copy(extendedKey, key)
	for i := len(key); i < KeySize; i++ {
		extendedKey[i] = byte(i) // Fill remaining bytes
	}
	key = extendedKey


	err := os.WriteFile(plaintextFilePath, plaintextContent, 0600)
	assert.NoError(t, err)

	cacheFilePath, err := EncryptCacheFile(plaintextFilePath, key)
	assert.NoError(t, err)
	assert.FileExists(t, cacheFilePath)

	decryptedContent, err := DecryptCacheFile(cacheFilePath, key)
	assert.NoError(t, err)
	assert.True(t, bytes.Equal(plaintextContent, decryptedContent), "Decrypted content should match original plaintext")

	// Clean up
	err = DeleteCacheFile(cacheFilePath)
	assert.NoError(t, err)
	assert.NoFileExists(t, cacheFilePath)
}

func TestEncryptDecryptCacheFile_IncorrectKey(t *testing.T) {
	tempDir := t.TempDir()
	plaintextFilePath := filepath.Join(tempDir, "test_plaintext_incorrect.txt")
	plaintextContent := []byte("Sensitive data for incorrect key test.")
	correctKey := []byte("sixteenbytekey1234")
	incorrectKey := []byte("wrongkeyforthisfile")

	// Adjust keys to be KeySize (32 bytes)
	extendedCorrectKey := make([]byte, KeySize)
	copy(extendedCorrectKey, correctKey)
	for i := len(correctKey); i < KeySize; i++ {
		extendedCorrectKey[i] = byte(i)
	}
	correctKey = extendedCorrectKey

	extendedIncorrectKey := make([]byte, KeySize)
	copy(extendedIncorrectKey, incorrectKey)
	for i := len(incorrectKey); i < KeySize; i++ {
		extendedIncorrectKey[i] = byte(i)
	}
	incorrectKey = extendedIncorrectKey


	err := os.WriteFile(plaintextFilePath, plaintextContent, 0600)
	assert.NoError(t, err)

	cacheFilePath, err := EncryptCacheFile(plaintextFilePath, correctKey)
	assert.NoError(t, err)
	assert.FileExists(t, cacheFilePath)

	// Attempt to decrypt with incorrect key
	decryptedContent, err := DecryptCacheFile(cacheFilePath, incorrectKey)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "failed to decrypt cache file (likely incorrect key or corrupted data)")
	assert.Nil(t, decryptedContent)

	// Clean up
	err = DeleteCacheFile(cacheFilePath)
	assert.NoError(t, err)
	assert.NoFileExists(t, cacheFilePath)
}

func TestEncryptCacheFile_EmptyKey(t *testing.T) {
	tempDir := t.TempDir()
	plaintextFilePath := filepath.Join(tempDir, "test_plaintext_emptykey_enc.txt")
	plaintextContent := []byte("Data for empty key encryption test.")
	emptyKey := []byte{}

	err := os.WriteFile(plaintextFilePath, plaintextContent, 0600)
	assert.NoError(t, err)

	cacheFilePath, err := EncryptCacheFile(plaintextFilePath, emptyKey)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "encryption key must be 32 bytes long")
	assert.Empty(t, cacheFilePath)
	
	// Clean up
	os.Remove(plaintextFilePath)
}

func TestDecryptCacheFile_EmptyKey(t *testing.T) {
	tempDir := t.TempDir()
	plaintextFilePath := filepath.Join(tempDir, "test_plaintext_emptykey_dec.txt")
	plaintextContent := []byte("Data for empty key decryption test.")
	correctKey := make([]byte, KeySize) // Ensure key is KeySize
	_, err := rand.Read(correctKey)
	assert.NoError(t, err)

	err = os.WriteFile(plaintextFilePath, plaintextContent, 0600)
	assert.NoError(t, err)

	cacheFilePath, err := EncryptCacheFile(plaintextFilePath, correctKey)
	assert.NoError(t, err)
	assert.FileExists(t, cacheFilePath)

	// Attempt to decrypt with empty key
	decryptedContent, err := DecryptCacheFile(cacheFilePath, []byte{}) // Pass empty slice
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "encryption key must be 32 bytes long")
	assert.Nil(t, decryptedContent)

	// Clean up
	err = os.Remove(cacheFilePath) // Direct removal
	assert.NoError(t, err)
	assert.NoFileExists(t, cacheFilePath)
	
	err = os.Remove(plaintextFilePath) // Direct removal
	assert.NoError(t, err)
	assert.NoFileExists(t, plaintextFilePath) // Verify plaintext file is also gone
}

func TestDeleteCacheFile(t *testing.T) {
	tempDir := t.TempDir()
	cacheFilePath := filepath.Join(tempDir, "test_cache_file_to_delete.enc")
	
	// Create a dummy file
	err := os.WriteFile(cacheFilePath, []byte("dummy content for wiping"), 0600)
	assert.NoError(t, err)
	assert.FileExists(t, cacheFilePath)

	err = DeleteCacheFile(cacheFilePath)
	assert.NoError(t, err)
	assert.NoFileExists(t, cacheFilePath)

	// Test deleting a non-existent file (should not return error)
	nonExistentFilePath := filepath.Join(tempDir, "non_existent_file.enc")
	err = DeleteCacheFile(nonExistentFilePath)
	assert.NoError(t, err)
}

func BenchmarkEncryptCacheFile(b *testing.B) {
	tempDir := b.TempDir()
	plaintextFilePath := filepath.Join(tempDir, "benchmark_plaintext.bin")
	key := make([]byte, KeySize)
	_, err := rand.Read(key)
	if err != nil {
		b.Fatal(err)
	}

	// Create a 10MB dummy file
	dummyContent := make([]byte, 10*1024*1024) // 10MB
	_, err = rand.Read(dummyContent)
	if err != nil {
		b.Fatal(err)
	}
	err = os.WriteFile(plaintextFilePath, dummyContent, 0600)
	if err != nil {
		b.Fatal(err)
	}
	defer os.Remove(plaintextFilePath)

	b.ResetTimer()
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		cacheFilePath, err := EncryptCacheFile(plaintextFilePath, key)
		if err != nil {
			b.Fatal(err)
		}
		// Clean up encrypted file for each iteration
		os.Remove(cacheFilePath)
	}
	// For performance calculation as MB/s
	// 10MB * b.N / elapsed_seconds
	totalBytes := float64(10 * 1024 * 1024 * b.N)
	mbPerSec := (totalBytes / b.Elapsed().Seconds()) / (1024 * 1024)
	b.ReportMetric(mbPerSec, "MB/s")

	// Target is >100 MB/s
	if mbPerSec < 100 {
		b.Errorf("EncryptCacheFile performance (%f MB/s) is below target (100 MB/s)", mbPerSec)
	}
}

func BenchmarkDecryptCacheFile(b *testing.B) {
	tempDir := b.TempDir()
	plaintextFilePath := filepath.Join(tempDir, "benchmark_plaintext_dec.bin")
	key := make([]byte, KeySize)
	_, err := rand.Read(key)
	if err != nil {
		b.Fatal(err)
	}

	// Create a 10MB dummy file
	dummyContent := make([]byte, 10*1024*1024) // 10MB
	_, err = rand.Read(dummyContent)
	if err != nil {
		b.Fatal(err)
	}
	err = os.WriteFile(plaintextFilePath, dummyContent, 0600)
	if err != nil {
		b.Fatal(err)
	}
	defer os.Remove(plaintextFilePath)

	// Encrypt once for setup
	cacheFilePath, err := EncryptCacheFile(plaintextFilePath, key)
	if err != nil {
		b.Fatal(err)
	}
	defer os.Remove(cacheFilePath)

	b.ResetTimer()
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		_, err := DecryptCacheFile(cacheFilePath, key)
		if err != nil {
			b.Fatal(err)
		}
	}
	// For performance calculation as MB/s
	// 10MB * b.N / elapsed_seconds
	totalBytes := float64(10 * 1024 * 1024 * b.N)
	mbPerSec := (totalBytes / b.Elapsed().Seconds()) / (1024 * 1024)
	b.ReportMetric(mbPerSec, "MB/s")

	// Target is >100 MB/s
	if mbPerSec < 100 {
		b.Errorf("DecryptCacheFile performance (%f MB/s) is below target (100 MB/s)", mbPerSec)
	}
}
