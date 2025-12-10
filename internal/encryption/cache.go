package encryption

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// EncryptCacheFile reads a plaintext file, encrypts its content using AES-256-GCM,
// stores it in a new location with an obfuscated filename, and returns the path
// to the encrypted cache file.
func EncryptCacheFile(plaintextFilePath string, key []byte) (string, error) {
	if len(key) != KeySize {
		return "", fmt.Errorf("encryption key must be %d bytes long", KeySize)
	}

	plaintext, err := os.ReadFile(plaintextFilePath)
	if err != nil {
		return "", fmt.Errorf("failed to read plaintext file: %w", err)
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return "", fmt.Errorf("failed to create AES cipher: %w", err)
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("failed to create GCM: %w", err)
	}

	nonce := make([]byte, gcm.NonceSize())
	if _, err = io.ReadFull(rand.Reader, nonce); err != nil {
		return "", fmt.Errorf("failed to generate nonce: %w", err)
	}

	ciphertext := gcm.Seal(nonce, nonce, plaintext, nil)

	// Obfuscate filename: SHA256 hash of the original file path
	hash := sha256.Sum256([]byte(plaintextFilePath))
	obfuscatedFilename := hex.EncodeToString(hash[:]) + ".enc"
	
	// Determine cache directory (e.g., ~/.cache/protondrive/)
	// For simplicity, we'll use a temporary directory for now, actual cache path will be configured later.
	cacheDir := os.TempDir() // Placeholder, will be replaced with actual config path
	cacheFilePath := filepath.Join(cacheDir, obfuscatedFilename)

	err = os.WriteFile(cacheFilePath, ciphertext, 0600)
	if err != nil {
		return "", fmt.Errorf("failed to write encrypted cache file: %w", err)
	}

	return cacheFilePath, nil
}

// DecryptCacheFile reads an encrypted cache file, decrypts its content using AES-256-GCM,
// and returns the plaintext bytes.
func DecryptCacheFile(cacheFilePath string, key []byte) ([]byte, error) {
	if len(key) != KeySize {
		return nil, fmt.Errorf("encryption key must be %d bytes long", KeySize)
	}

	ciphertext, err := os.ReadFile(cacheFilePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read encrypted cache file: %w", err)
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("failed to create AES cipher: %w", err)
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("failed to create GCM: %w", err)
	}

	nonceSize := gcm.NonceSize()
	if len(ciphertext) < nonceSize {
		return nil, fmt.Errorf("ciphertext too short")
	}

	nonce, encryptedMessage := ciphertext[:nonceSize], ciphertext[nonceSize:]
	plaintext, err := gcm.Open(nil, nonce, encryptedMessage, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to decrypt cache file (likely incorrect key or corrupted data): %w", err)
	}

	return plaintext, nil
}

// DeleteCacheFile securely deletes the cache file by zeroing its content before deletion.
func DeleteCacheFile(cacheFilePath string) error {
	// Read the file content
	fileInfo, err := os.Stat(cacheFilePath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil // File does not exist, nothing to do
		}
		return fmt.Errorf("failed to stat cache file: %w", err)
	}

	fileSize := fileInfo.Size()
	
	// Zero out the file content before deleting
	file, err := os.OpenFile(cacheFilePath, os.O_WRONLY, 0)
	if err != nil {
		return fmt.Errorf("failed to open cache file for wiping: %w", err)
	}
	defer file.Close()

	zeroBytes := make([]byte, 1024) // Write in chunks
	for i := int64(0); i < fileSize; i += int64(len(zeroBytes)) {
		end := i + int64(len(zeroBytes))
		if end > fileSize {
			end = fileSize
		}
		if _, err := file.WriteAt(zeroBytes[:end-i], i); err != nil {
			return fmt.Errorf("failed to wipe cache file content: %w", err)
		}
	}

	err = file.Sync() // Ensure data is written to disk
	if err != nil {
		return fmt.Errorf("failed to sync wiped cache file to disk: %w", err)
	}

	err = os.Remove(cacheFilePath)
	if err != nil {
		return fmt.Errorf("failed to delete cache file: %w", err)
	}
	return nil
}