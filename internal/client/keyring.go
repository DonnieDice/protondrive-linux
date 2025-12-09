package client

import (
	"fmt"
	"log"
	"time"

	"github.com/zalando/go-keyring"
)

const (
	keyringService = "protondrive-linux"
	// For now, we'll store username and password together.
	// In a real application, consider storing tokens, not raw credentials,
	// and potentially separating service/user for more fine-grained control.
)

// SaveCredentials securely stores the user's username and password in the system keyring.
func SaveCredentials(username, password string) error {
	log.Printf("[client] Attempting to save credentials for user: %s", username)
	err := keyring.Set(keyringService, username, password)
	if err != nil {
		log.Printf("[client] Failed to save credentials for %s: %v", username, err)
		// TODO: Fallback to encrypted file if keyring is unavailable
		return fmt.Errorf("failed to save credentials to keyring: %w", err)
	}
	log.Printf("[client] Credentials for user: %s saved successfully.", username)
	return nil
}

// LoadCredentials retrieves the user's username and password from the system keyring.
func LoadCredentials(username string) (string, string, error) {
	log.Printf("[client] Attempting to load credentials for user: %s", username)
	password, err := keyring.Get(keyringService, username)
	if err != nil {
		log.Printf("[client] Failed to load credentials for %s: %v", username, err)
		return "", "", fmt.Errorf("failed to load credentials from keyring: %w", err)
	}
	log.Printf("[client] Credentials for user: %s loaded successfully.", username)
	return username, password, nil
}

// ClearCredentials removes the user's credentials from the system keyring.
func ClearCredentials(username string) error {
	log.Printf("[client] Attempting to clear credentials for user: %s", username)
	err := keyring.Delete(keyringService, username)
	if err != nil {
		log.Printf("[client] Failed to clear credentials for %s: %v", username, err)
		return fmt.Errorf("failed to clear credentials from keyring: %w", err)
	}
	log.Printf("[client] Credentials for user: %s cleared successfully.", username)
	return nil
}

// Placeholder for a simple fallback mechanism if keyring fails
// TODO: Implement a robust encrypted file fallback.
func storeCredentialsFallback(username, password string) error {
	log.Println("WARNING: Using insecure fallback for credential storage.")
	// For demonstration only - DO NOT USE IN PRODUCTION
	_ = username
	_ = password
	time.Sleep(1 * time.Second) // Simulate storage
	return fmt.Errorf("fallback storage not implemented")
}

func retrieveCredentialsFallback(username string) (string, string, error) {
	log.Println("WARNING: Using insecure fallback for credential retrieval.")
	_ = username
	time.Sleep(1 * time.Second) // Simulate retrieval
	return "", "", fmt.Errorf("fallback retrieval not implemented")
}

func deleteCredentialsFallback(username string) error {
	log.Println("WARNING: Using insecure fallback for credential deletion.")
	_ = username
	time.Sleep(1 * time.Second) // Simulate deletion
	return fmt.Errorf("fallback deletion not implemented")
}
