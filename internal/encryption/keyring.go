package encryption

import (
	"errors"
	"fmt"
	"os"

	"github.com/zalando/go-keyring"
)

const (
	keyringService = "protondrive-linux"
)

// StoreKey stores the derived encryption key in the OS keyring.
func StoreKey(user string, key []byte) error {
	err := keyring.Set(keyringService, user, string(key))
	if err != nil {
		if errors.Is(err, keyring.ErrNotFound) {
			return fmt.Errorf("keyring service not found: %w", err)
		}
		return fmt.Errorf("failed to store key in keyring: %w", err)
	}
	return nil
}

// RetrieveKey retrieves the derived encryption key from the OS keyring.
func RetrieveKey(user string) ([]byte, error) {
	secret, err := keyring.Get(keyringService, user)
	if err != nil {
		if errors.Is(err, keyring.ErrNotFound) {
			return nil, fmt.Errorf("keyring service not found: %w", err)
		}
		return nil, fmt.Errorf("failed to retrieve key from keyring: %w", err)
	}
	return []byte(secret), nil
}

// DeleteKey deletes the stored encryption key from the OS keyring.
func DeleteKey(user string) error {
	err := keyring.Delete(keyringService, user)
	if err != nil {
		if errors.Is(err, keyring.ErrNotFound) {
			return fmt.Errorf("keyring service not found: %w", err)
		}
		return fmt.Errorf("failed to delete key from keyring: %w", err)
	}
	return nil
}

// IsKeyringAvailable checks if the OS keyring service is available.
func IsKeyringAvailable() bool {
	// A more robust check might involve trying to use the keyring with a dummy value
	// However, for now, we rely on environment variables as a heuristic, as per the original intention.
	// This function primarily signals if the environment *might* support a graphical keyring daemon.
	return os.Getenv("XDG_CURRENT_DESKTOP") != "" || os.Getenv("DBUS_SESSION_BUS_ADDRESS") != ""
}