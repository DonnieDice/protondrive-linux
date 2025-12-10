package testutil

import (
	"errors" // Import errors package
	"os"
	"path/filepath"
	"crypto/rand" // Added for key generation
	"time" // Added for time.Time in FileMetadata

	"github.com/yourusername/protondrive-linux/internal/client"
	"github.com/yourusername/protondrive-linux/internal/config"
	"github.com/yourusername/protondrive-linux/internal/encryption"
	"github.com/yourusername/protondrive-linux/internal/storage" // Added for storage.FileMetadata

// CreateTempConfig creates a temporary Config for testing with a temporary directory.
func CreateTempConfig(t TInterface) *config.Config {
	t.Helper()
	tempDir := t.TempDir() // Uses testing.T.TempDir()
	configPath := filepath.Join(tempDir, "config.json")
	
	cfg := config.NewConfig(configPath) // Assuming NewConfig takes a path
	return cfg
}

// GenerateTestKey generates a cryptographically secure random key of encryption.KeySize bytes.
func GenerateTestKey(t TInterface) []byte {
	t.Helper()
	key := make([]byte, encryption.KeySize)
	_, err := rand.Read(key)
	if err != nil {
		t.Fatalf("failed to generate random test key: %v", err)
	}
	return key
}

// TInterface is a subset of testing.TB interface that TempDir uses.
// This allows CreateTempConfig and GenerateTestKey to be used by both testing.T and testing.B.
// TInterface is a subset of testing.TB interface that TempDir uses.
// This allows CreateTempConfig and GenerateTestKey to be used by both testing.T and testing.B.
type TInterface interface {
	Helper()
	TempDir() string
	Fatalf(format string, args ...interface{})
}

// MockProtonClient is a mock implementation of the client.ProtonClient interface for testing.
type MockProtonClient struct {
	MockLogin          func(username, password string) error
	MockLogout         func() error
	MockIsAuthenticated func() bool
	MockUpload         func(filepath string) error
	MockDownload       func(filepath string) error

	// Internal state for testing purposes
	Authenticated bool
	Username      string
}

// Login implements the Login method for MockProtonClient.
func (m *MockProtonClient) Login(username, password string) error {
	if m.MockLogin != nil {
		return m.MockLogin(username, password)
	}
	// Default mock behavior
	if username == "testuser" && password == "testpass" {
		m.Authenticated = true
		m.Username = username
		return nil
	}
	m.Authenticated = false
	m.Username = ""
	return errors.New("mock login failed") // Use a generic error for mock
}

// Logout implements the Logout method for MockProtonClient.
func (m *MockProtonClient) Logout() error {
	if m.MockLogout != nil {
		return m.MockLogout()
	}
	m.Authenticated = false
	m.Username = ""
	return nil
}

// IsAuthenticated implements the IsAuthenticated method for MockProtonClient.
func (m *MockProtonClient) IsAuthenticated() bool {
	if m.MockIsAuthenticated != nil {
		return m.MockIsAuthenticated()
	}
	return m.Authenticated
}

// Upload implements the Upload method for MockProtonClient.
func (m *MockProtonClient) Upload(filepath string) error {
	if m.MockUpload != nil {
		return m.MockUpload(filepath)
	}
	if !m.Authenticated {
		return errors.New("mock: not authenticated for upload")
	}
	// Simulate successful upload
	return nil
}

// Download implements the Download method for MockProtonClient.
func (m *MockProtonClient) Download(filepath string) error {
	if m.MockDownload != nil {
		return m.MockDownload(filepath)
	}
	if !m.Authenticated {
		return errors.New("mock: not authenticated for download")
	}
	// Simulate successful download
	return nil
}

// MockEncryptionClient is a mock implementation for encryption operations.
type MockEncryptionClient struct {
	MockEncryptCacheFile func(plaintextFilePath string, key []byte) (string, error)
	MockDecryptCacheFile func(cacheFilePath string, key []byte) ([]byte, error)
	MockDeriveKey        func(password, salt []byte, iterations int) ([]byte, error)
	MockGenerateSalt     func() ([]byte, error)
}

// EncryptCacheFile implements the EncryptCacheFile method for MockEncryptionClient.
func (m *MockEncryptionClient) EncryptCacheFile(plaintextFilePath string, key []byte) (string, error) {
	if m.MockEncryptCacheFile != nil {
		return m.MockEncryptCacheFile(plaintextFilePath, key)
	}
	// Default behavior: return obfuscated path without actual encryption
	return filepath.Join(os.TempDir(), "mock_"+filepath.Base(plaintextFilePath)+".enc"), nil
}

// DecryptCacheFile implements the DecryptCacheFile method for MockEncryptionClient.
func (m *MockEncryptionClient) DecryptCacheFile(cacheFilePath string, key []byte) ([]byte, error) {
	if m.MockDecryptCacheFile != nil {
		return m.MockDecryptCacheFile(cacheFilePath, key)
	}
	// Default behavior: return some placeholder plaintext
	return []byte("mock decrypted content"), nil
}

// DeriveKey implements the DeriveKey method for MockEncryptionClient.
func (m *MockEncryptionClient) DeriveKey(password, salt []byte, iterations int) ([]byte, error) {
	if m.MockDeriveKey != nil {
		return m.MockDeriveKey(password, salt, iterations)
	}
	// Default behavior: return a fixed mock key
	return []byte("mock_derived_key_for_testing_1234"), nil
}

// GenerateSalt implements the GenerateSalt method for MockEncryptionClient.
func (m *MockEncryptionClient) GenerateSalt() ([]byte, error) {
	if m.MockGenerateSalt != nil {
		return m.MockGenerateSalt()
	}
	return []byte("mock_salt"), nil
}

// CreateFileMetadata creates a generic FileMetadata object for testing.
func CreateFileMetadata(id, name string, isDir bool) *storage.FileMetadata {
	now := time.Now().Truncate(time.Second)
	return &storage.FileMetadata{
		ID:         id,
		Name:       name,
		Size:       1024,
		ModTime:    now,
		IsDir:      isDir,
		Hash:       "mockhash-" + id,
		RemotePath: "/remote/" + name,
		LocalPath:  "/local/" + name,
		SyncStatus: storage.SyncPending,
		CreatedAt:  now,
		UpdatedAt:  now,
	}
}