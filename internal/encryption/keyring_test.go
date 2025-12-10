package encryption

import (
	"bytes"
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/zalando/go-keyring"
)

func TestMain(m *testing.M) {
	// Use a mock keyring for testing
	keyring.MockInit()
	os.Exit(m.Run())
}

func TestStoreAndRetrieveKey(t *testing.T) {
	user := "testuser_store_retrieve"
	testKey := []byte("secretkey123")

	err := StoreKey(user, testKey)
	assert.NoError(t, err)

	retrievedKey, err := RetrieveKey(user)
	assert.NoError(t, err)
	assert.True(t, bytes.Equal(testKey, retrievedKey), "Retrieved key should match stored key")

	// Clean up
	err = DeleteKey(user)
	assert.NoError(t, err)
}

func TestRetrieveNonExistentKey(t *testing.T) {
	user := "nonexistent_user"
	retrievedKey, err := RetrieveKey(user)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "secret not found")
	assert.Nil(t, retrievedKey)
}

func TestDeleteKey(t *testing.T) {
	user := "testuser_delete"
	testKey := []byte("keytodelete")

	// Store key first
	err := StoreKey(user, testKey)
	assert.NoError(t, err)

	// Delete key
	err = DeleteKey(user)
	assert.NoError(t, err)

	// Try to retrieve it to confirm deletion
	retrievedKey, err := RetrieveKey(user)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "secret not found")
	assert.Nil(t, retrievedKey)
}

func TestDeleteNonExistentKey(t *testing.T) {
	user := "nonexistent_user_delete"
	err := DeleteKey(user)
	// Expect an error when deleting a non-existent key
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "secret not found")
}

func TestIsKeyringAvailable(t *testing.T) {
	// With MockInit(), keyring is always "available" in a sense,
	// but the function implementation checks environment variables.
	// This test might need more sophisticated mocking of environment variables
	// or be moved to an integration test.
	// For now, given the mock, it will behave as if it's available.
	// Original implementation: checks env vars, which is a heuristic.
	// We'll rely on the MockInit() for the test environment.
	t.Setenv("XDG_CURRENT_DESKTOP", "GNOME")
	assert.True(t, IsKeyringAvailable(), "Keyring should be available with XDG_CURRENT_DESKTOP set")

	t.Setenv("XDG_CURRENT_DESKTOP", "")
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/run/user/1000/bus")
	assert.True(t, IsKeyringAvailable(), "Keyring should be available with DBUS_SESSION_BUS_ADDRESS set")

	t.Setenv("XDG_CURRENT_DESKTOP", "")
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", "")
	assert.False(t, IsKeyringAvailable(), "Keyring should not be available without relevant env vars")
}
