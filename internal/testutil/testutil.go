package testutil

import (
	"github.com/yourusername/protondrive-linux/internal/client"
	"github.com/yourusername/protondrive-linux/internal/config"
)

// CreateTempConfig creates a temporary configuration for testing.
func CreateTempConfig() *config.Config {
	// TODO: Implement actual temporary config creation
	return &config.Config{}
}

// MockProtonClient is a mock implementation of the ProtonClient interface.
type MockProtonClient struct {
	UploadCalled   int
	DownloadCalled int
	// Add other mock fields as needed
}

// Upload mocks the Upload method of ProtonClient.
func (m *MockProtonClient) Upload(filepath string) error {
	m.UploadCalled++
	return nil
}

// Download mocks the Download method of ProtonClient.
func (m *MockProtonClient) Download(filepath string) error {
	m.DownloadCalled++
	return nil
}

// Login mocks the Login method of ProtonClient.
func (m *MockProtonClient) Login(username, password string) error {
	return nil
}

// Logout mocks the Logout method of ProtonClient.
func (m *MockProtonClient) Logout() error {
	return nil
}

// IsAuthenticated mocks the IsAuthenticated method of ProtonClient.
func (m *MockProtonClient) IsAuthenticated() bool {
	return true
}

// NewMockProtonClient creates and returns a new MockProtonClient.
func NewMockProtonClient() client.ProtonClient {
	return &MockProtonClient{}
}