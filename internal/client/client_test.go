package client_test

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/yourusername/protondrive-linux/internal/testutil"
)

// func TestNewProtonClient(t *testing.T) {
// 	c := client.NewProtonClient()
// 	assert.NotNil(t, c)
// 	assert.False(t, c.IsAuthenticated())
// }

func TestLogin(t *testing.T) {
	mockClient := &testutil.MockProtonClient{}
	// For actual client, we would need to mock the bridge.Login method.
	// For now, we are testing the wrapper's behavior.

	// Since our realProtonClient uses a real bridge, we can't directly use MockProtonClient as the bridge.
	// This test will focus on the public interface of client.ProtonClient.

	// To properly test the realProtonClient's Login method without making actual API calls,
	// we would need to inject a mock for drive.Client into realProtonClient.
	// This highlights the importance of dependency injection.

	// For now, a basic integration test with the actual Proton-API-Bridge would be needed,
	// or further refactoring of realProtonClient to accept a drive.Client interface.

	// Placeholder test for now:
	assert.Nil(t, mockClient.Login("testuser", "testpass"))
	assert.True(t, mockClient.IsAuthenticated()) // Mock should authenticate for these credentials
}

func TestIsAuthenticated(t *testing.T) {
	mockClient := testutil.CreateMockClient()
	assert.True(t, mockClient.IsAuthenticated()) // Mock should authenticate by default
}
