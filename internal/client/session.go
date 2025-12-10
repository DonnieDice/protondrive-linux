package client

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"path/filepath"

	"github.com/henrybear327/Proton-API-Bridge/common" // Import common
	"github.com/yourusername/protondrive-linux/internal/encryption"
)

const (
	sessionFileName = "session.json.enc"
	appName = "protondrive-linux" // Should match the one in storage package or be centralized
)

// getSessionFilePath determines the path where the encrypted session file will be stored.
func getSessionFilePath() (string, error) {
	configDir, err := os.UserConfigDir()
	if err != nil {
		return "", fmt.Errorf("failed to get user config directory: %w", err)
	}
	appConfigDir := filepath.Join(configDir, appName)
	if err := os.MkdirAll(appConfigDir, 0700); err != nil {
		return "", fmt.Errorf("failed to create application config directory %s: %w", appConfigDir, err)
	}
	return filepath.Join(appConfigDir, sessionFileName), nil
}

// SaveSession saves the ProtonDrive session data encrypted with the provided key.
func SaveSession(session *common.ProtonDriveCredential, key []byte) error {
	if session == nil {
		return fmt.Errorf("session cannot be nil")
	}
	if len(key) != encryption.KeySize {
		return fmt.Errorf("encryption key must be %d bytes long", encryption.KeySize)
	}

	sessionFilePath, err := getSessionFilePath()
	if err != nil {
		return fmt.Errorf("failed to get session file path: %w", err)
	}

	jsonData, err := json.Marshal(session)
	if err != nil {
		return fmt.Errorf("failed to marshal session data: %w", err)
	}

	encryptedData, err := encryption.EncryptBytes(jsonData, key)
	if err != nil {
		return fmt.Errorf("failed to encrypt session data: %w", err)
	}

	if err := ioutil.WriteFile(sessionFilePath, encryptedData, 0600); err != nil {
		return fmt.Errorf("failed to write encrypted session file: %w", err)
	}

	log.Println("[client] Session saved successfully.")
	return nil
}

// LoadSession loads and decrypts the ProtonDrive session data using the provided key.
func LoadSession(key []byte) (*common.ProtonDriveCredential, error) {
	if len(key) != encryption.KeySize {
		return nil, fmt.Errorf("encryption key must be %d bytes long", encryption.KeySize)
	}

	sessionFilePath, err := getSessionFilePath()
	if err != nil {
		return nil, fmt.Errorf("failed to get session file path: %w", err)
	}

	encryptedData, err := ioutil.ReadFile(sessionFilePath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("session file not found: %w", err)
		}
		return nil, fmt.Errorf("failed to read encrypted session file: %w", err)
	}

	decryptedData, err := encryption.DecryptBytes(encryptedData, key)
	if err != nil {
		return nil, fmt.Errorf("failed to decrypt session data: %w", err)
	}

	var session common.ProtonDriveCredential
	if err := json.Unmarshal(decryptedData, &session); err != nil {
		return nil, fmt.Errorf("failed to unmarshal session data: %w", err)
	}

	log.Println("[client] Session loaded successfully.")
	return &session, nil
}

// ClearSession deletes the encrypted session file.
func ClearSession() error {
	sessionFilePath, err := getSessionFilePath()
	if err != nil {
		return fmt.Errorf("failed to get session file path: %w", err)
	}

	if err := os.Remove(sessionFilePath); err != nil {
		if os.IsNotExist(err) {
			return nil // Already deleted
		}
		return fmt.Errorf("failed to delete session file: %w", err)
	}
	log.Println("[client] Session file cleared.")
	return nil
}
