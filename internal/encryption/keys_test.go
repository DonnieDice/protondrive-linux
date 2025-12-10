package encryption

import (
	"bytes"
	"encoding/hex"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestGenerateSalt_Success(t *testing.T) {
	salt1, err := GenerateSalt()
	assert.NoError(t, err)
	assert.Len(t, salt1, SaltSize)

	salt2, err := GenerateSalt()
	assert.NoError(t, err)
	assert.Len(t, salt2, SaltSize)

	// Salts should be different
	assert.False(t, bytes.Equal(salt1, salt2), "Generated salts should be different")
}

func TestDeriveKey_Success(t *testing.T) {
	password := []byte("testpassword")
	salt, _ := hex.DecodeString("0123456789abcdef0123456789abcdef") // 16 bytes
	iterations := DefaultPBKDF2Iterations

	key, err := DeriveKey(password, salt, iterations)
	assert.NoError(t, err)
	assert.Len(t, key, KeySize)
	assert.NotNil(t, key)
}

func TestDeriveKey_Consistency(t *testing.T) {
	password := []byte("consistentpassword")
	salt, _ := hex.DecodeString("fedcba9876543210fedcba9876543210")
	iterations := DefaultPBKDF2Iterations

	key1, err := DeriveKey(password, salt, iterations)
	assert.NoError(t, err)

	key2, err := DeriveKey(password, salt, iterations)
	assert.NoError(t, err)

	assert.Equal(t, key1, key2, "Derived keys should be consistent for same inputs")
}

func TestDeriveKey_EmptyPassword(t *testing.T) {
	password := []byte("")
	salt, _ := hex.DecodeString("0123456789abcdef0123456789abcdef")
	iterations := DefaultPBKDF2Iterations

	key, err := DeriveKey(password, salt, iterations)
	assert.Error(t, err)
	assert.Nil(t, key)
	assert.Contains(t, err.Error(), "password cannot be empty")
}

func TestDeriveKey_InvalidSaltSize(t *testing.T) {
	password := []byte("testpassword")
	salt := []byte("short") // Invalid size
	iterations := DefaultPBKDF2Iterations

	key, err := DeriveKey(password, salt, iterations)
	assert.Error(t, err)
	assert.Nil(t, key)
	assert.Contains(t, err.Error(), "salt must be 16 bytes long")
}

func TestDeriveKey_InvalidIterations(t *testing.T) {
	password := []byte("testpassword")
	salt, _ := hex.DecodeString("0123456789abcdef0123456789abcdef")
	iterations := 0 // Invalid iterations

	key, err := DeriveKey(password, salt, iterations)
	assert.Error(t, err)
	assert.Nil(t, key)
	assert.Contains(t, err.Error(), "iterations must be greater than 0")
}

func TestWipeKey(t *testing.T) {
	sensitiveData := []byte("supersecret")
	originalCopy := make([]byte, len(sensitiveData))
	copy(originalCopy, sensitiveData)

	WipeKey(sensitiveData)

	// Verify that the original slice is zeroed out
	for _, b := range sensitiveData {
		assert.Equal(t, byte(0), b, "Byte was not wiped to zero")
	}

	// Ensure the original content is different from the wiped one
	assert.NotEqual(t, originalCopy, sensitiveData, "Wiped data should not match original")
}

func BenchmarkDeriveKey(b *testing.B) {
	password := []byte("benchmarkpassword")
	salt, _ := hex.DecodeString("aabbccddeeff00112233445566778899")
	iterations := DefaultPBKDF2Iterations // 256,000 iterations

	b.ResetTimer()
	start := time.Now()
	for i := 0; i < b.N; i++ {
		_, err := DeriveKey(password, salt, iterations)
		if err != nil {
			b.Fatal(err)
		}
	}
	elapsed := time.Since(start)
	b.ReportMetric(float64(b.N)/elapsed.Seconds(), "ops/s")

	// Per GEMINI.md, target for key derivation is <500ms
	// This benchmark runs b.N times, so average time per op should be less than 500ms
	// For N=1, this means total elapsed should be less than 500ms
	if b.N == 1 && elapsed > 500*time.Millisecond {
		b.Errorf("DeriveKey took %s, expected less than 500ms", elapsed)
	}
}