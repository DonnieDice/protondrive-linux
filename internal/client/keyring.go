package client

import (
	"encoding/hex"
	"fmt"
	"log"

	"github.com/zalando/go-keyring"
)

const (
	keyringService = "protondrive-linux"
	keyringSessionKeyLabel = "session_encryption_key" // Label for the session key in keyring
)

// SaveSessionKey securely stores the session encryption key in the system keyring.
func SaveSessionKey(username string, key []byte) error {
	log.Printf("[client] Attempting to save session encryption key for user: %s", username)
	
	keyHex := hex.EncodeToString(key)
	err := keyring.Set(keyringService, username+"_"+keyringSessionKeyLabel, keyHex)
	if err != nil {
		log.Printf("[client] Failed to save session encryption key for %s: %v", username, err)
		// TODO: Implement robust encrypted file fallback.
		return fmt.Errorf("failed to save session encryption key to keyring: %w", err)
	}
	log.Printf("[client] Session encryption key for user: %s saved successfully.", username)
	return nil
}

// LoadSessionKey retrieves the session encryption key from the system keyring.
func LoadSessionKey(username string) ([]byte, error) {
	log.Printf("[client] Attempting to load session encryption key for user: %s", username)
	
	keyHex, err := keyring.Get(keyringService, username+"_"+keyringSessionKeyLabel)
	if err != nil {
		log.Printf("[client] Failed to load session encryption key for %s: %v", username, err)
		// TODO: Implement robust encrypted file fallback.
		return nil, fmt.Errorf("failed to load session encryption key from keyring: %w", err)
	}
	
	key, err := hex.DecodeString(keyHex)
	if err != nil {
		return nil, fmt.Errorf("failed to decode session encryption key from hex: %w", err)
	}

	log.Printf("[client] Session encryption key for user: %s loaded successfully.", username)
	return key, nil
}

// ClearSessionKey removes the session encryption key from the system keyring.
func ClearSessionKey(username string) error {
	log.Printf("[client] Attempting to clear session encryption key for user: %s", username)
	err := keyring.Delete(keyringService, username+"_"+keyringSessionKeyLabel)
	if err != nil {
		log.Printf("[client] Failed to clear session encryption key for %s: %v", username, err)
		// TODO: Implement robust encrypted file fallback.
		return fmt.Errorf("failed to clear session encryption key from keyring: %w", err)
	}
	log.Printf("[client] Session encryption key for user: %s cleared successfully.", username)
	return nil
}
