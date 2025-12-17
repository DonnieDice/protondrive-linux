package encryption

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"fmt"

	"golang.org/x/crypto/pbkdf2"
)

const (
	// KeySize is the size of the derived key in bytes.
	KeySize = 32 // 256 bits for AES-256
	// DefaultPBKDF2Iterations is the recommended minimum number of iterations for PBKDF2.
	DefaultPBKDF2Iterations = 256000
	// SaltSize is the size of the salt in bytes.
	SaltSize = 16
)

// GenerateSalt generates a cryptographically secure random salt.
func GenerateSalt() ([]byte, error) {
	salt := make([]byte, SaltSize)
	if _, err := rand.Read(salt); err != nil {
		return nil, fmt.Errorf("failed to generate salt: %w", err)
	}
	return salt, nil
}

// DeriveKey derives a cryptographic key from a password, salt, and number of iterations
// using PBKDF2 with SHA256. The key size is fixed at KeySize (256 bits).
func DeriveKey(password, salt []byte, iterations int) ([]byte, error) {
	if len(password) == 0 {
		return nil, fmt.Errorf("password cannot be empty")
	}
	if len(salt) != SaltSize {
		return nil, fmt.Errorf("salt must be %d bytes long", SaltSize)
	}
	if iterations < 1 {
		return nil, fmt.Errorf("iterations must be greater than 0")
	}

	key := pbkdf2.Key(password, salt, iterations, KeySize, sha256.New)
	return key, nil
}

// WipeKey securely wipes a byte slice from memory by overwriting it with zeros.
// This helps prevent sensitive data from lingering in memory.
func WipeKey(key []byte) {
	for i := range key {
		key[i] = 0
	}
}

// EncryptBytes encrypts a byte slice using AES-256-GCM.
func EncryptBytes(plaintext []byte, key []byte) ([]byte, error) {
	if len(key) != KeySize {
		return nil, fmt.Errorf("encryption key must be %d bytes long", KeySize)
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("failed to create AES cipher: %w", err)
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("failed to create GCM: %w", err)
	}

	nonce := make([]byte, gcm.NonceSize())
	if _, err = rand.Read(nonce); err != nil {
		return nil, fmt.Errorf("failed to generate nonce: %w", err)
	}

	ciphertext := gcm.Seal(nonce, nonce, plaintext, nil)
	return ciphertext, nil
}

// DecryptBytes decrypts a byte slice encrypted with AES-256-GCM.
func DecryptBytes(ciphertext []byte, key []byte) ([]byte, error) {
	if len(key) != KeySize {
		return nil, fmt.Errorf("encryption key must be %d bytes long", KeySize)
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
		return nil, fmt.Errorf("failed to decrypt data (likely incorrect key or corrupted data): %w", err)
	}

	return plaintext, nil
}

// TODO: Add Argon2 implementation (optional, more secure)
