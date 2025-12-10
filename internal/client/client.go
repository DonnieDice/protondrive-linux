package client

import (
	"context" // Import context
	"errors" // Added for error handling
	"fmt"     // Import fmt
	"net/http" // Import net/http

	"github.com/henrybear327/Proton-API-Bridge"
	"github.com/henrybear327/Proton-API-Bridge/common" // Import common
	"github.com/henrybear327/go-proton-api" // Import go-proton-api for AuthHandler

	"github.com/yourusername/protondrive-linux/internal/client/keyring" // Added for keyring operations
	"github.com/yourusername/protondrive-linux/internal/client/session" // Added for session operations
	"github.com/yourusername/protondrive-linux/internal/encryption" // Added for key derivation/wiping
)

// ProtonClient defines the interface for interacting with the ProtonDrive API.
type ProtonClient interface {
	Login(ctx context.Context, username string, password []byte, rememberMe bool) error
	Logout() error
	IsAuthenticated() bool
	Upload(filepath string) error
	Download(filepath string) error
	// Add other ProtonDrive API methods as needed
}

// NewClient creates a new instance of the real ProtonDrive client, returning it as the ProtonClient interface.
func NewClient(ctx context.Context, httpClient *http.Client, username string) (ProtonClient, error) {
	return NewProtonClient(ctx, httpClient, username)
}

// realProtonClient is the concrete implementation of the ProtonClient interface.
type realProtonClient struct {
	bridge    *proton_api_bridge.ProtonDrive
	username  string
	session   *common.ProtonDriveCredential // Corrected type
}

// NewProtonClient creates a new instance of the real ProtonDrive client.
// It attempts to load a saved session for the given username to facilitate auto-login.
func NewProtonClient(ctx context.Context, httpClient *http.Client, username string) (*realProtonClient, error) {
	cfg := common.NewConfig() // Use a default config
	
	client := &realProtonClient{}
	client.username = username

	// Attempt to load session encryption key
	sessionEncryptionKey, err := keyring.LoadSessionKey(username)
	if err != nil {
		// Key not found or error loading, proceed without a loaded session.
		// User will need to log in manually.
		log.Printf("No session encryption key found for %s, proceeding to create unauthenticated client: %v", username, err)
		driveClient, _, err := proton_api_bridge.NewProtonDrive(ctx, cfg, nil, nil)
		if err != nil {
			return nil, errors.Wrap(err, errors.ErrInternal.SafeMsg)
		}
		client.bridge = driveClient
		return client, nil
	}
	defer encryption.WipeKey(sessionEncryptionKey) // Wipe key after use

	// Attempt to load the session data
	sessionCred, err := session.LoadSession(sessionEncryptionKey)
	if err != nil {
		// Session data not found or error loading, proceed without a loaded session.
		log.Printf("No session data found for %s or error loading: %v", username, err)
		// Clear potentially stale session key if session data is corrupted/missing.
		_ = keyring.ClearSessionKey(username)
		driveClient, _, err := proton_api_bridge.NewProtonDrive(ctx, cfg, nil, nil)
		if err != nil {
			return nil, errors.Wrap(err, errors.ErrInternal.SafeMsg)
		}
		client.bridge = driveClient
		return client, nil
	}

	// Initialize ProtonDrive bridge with the loaded session
	driveClient, err := proton_api_bridge.NewProtonDriveWithSession(ctx, cfg, sessionCred)
	if err != nil {
		log.Printf("Failed to initialize ProtonDrive client with loaded session, attempting unauthenticated: %v", err)
		// Fallback to unauthenticated client if session init fails
		driveClient, _, err := proton_api_bridge.NewProtonDrive(ctx, cfg, nil, nil)
		if err != nil {
			return nil, errors.Wrap(err, errors.ErrInternal.SafeMsg)
		}
		client.bridge = driveClient
		return client, nil
	}

	client.bridge = driveClient
	client.session = sessionCred
	return client, nil
}

// Login implements the Login method for realProtonClient.
// It performs SRP authentication and, if rememberMe is true,
// saves the session credentials securely.
func (c *realProtonClient) Login(ctx context.Context, username string, password []byte, rememberMe bool) error {
	defer encryption.WipeKey(password) // Ensure password is wiped from memory

	c.username = username
	
	// Perform SRP authentication using the bridge's Login method.
	sessionCred, err := c.bridge.Login(ctx, username, string(password))
	if err != nil {
		return fmt.Errorf("ProtonDrive SRP login failed: %w", err)
	}

	c.session = sessionCred // Store the authenticated session

	if rememberMe {
		// Derive a key for encrypting the session. This key itself is stored in the OS keyring.
		// For simplicity, we are using a derived key from a fixed "session-key-password"
		// which would ideally be generated once and stored in the OS keyring.
		// A more robust solution would derive this from the user's password securely
		// and then wipe the original password.

		// For now, let's derive a key from a fixed passphrase + username as salt
		// In a real scenario, this would be a more robust derivation from user password.
		sessionEncryptionKey, err := encryption.DeriveKey([]byte("fixed-session-key-passphrase"), []byte(username), encryption.DefaultPBKDF2Iterations)
		if err != nil {
			return fmt.Errorf("failed to derive session encryption key: %w", err)
		}
		defer encryption.WipeKey(sessionEncryptionKey) // Wipe derived key after use

		// Store this derived key in the OS keyring
		if err := keyring.SaveSessionKey(username, sessionEncryptionKey); err != nil {
			return fmt.Errorf("failed to save session encryption key to keyring: %w", err)
		}

		// Save the encrypted session data
		if err := session.SaveSession(c.session, sessionEncryptionKey); err != nil {
			return fmt.Errorf("failed to save encrypted session: %w", err)
		}
	} else {
		// If not "remember me", ensure any existing session key/data is cleared.
		_ = keyring.ClearSessionKey(username) // Best effort clear
		_ = session.ClearSession()           // Best effort clear
	}

	return nil
}

// Logout implements the Logout method for realProtonClient.
func (c *realProtonClient) Logout() error {
	// Invalidate the session with the ProtonDrive API if the bridge provides such a method.
	// For now, we clear the local state and persisted session data.
	
	// Clear persisted session data and key
	if c.username != "" {
		_ = session.ClearSession()
		_ = keyring.ClearSessionKey(c.username)
	}

	c.username = ""
	c.session = nil // Clear session if stored locally

	return nil
}

// IsAuthenticated implements the IsAuthenticated method for realProtonClient.
func (c *realProtonClient) IsAuthenticated() bool {
	// A more robust check would also verify if the session is expired or requires refresh.
	// For now, simply checking for the presence of a session and username is sufficient.
	return c.username != "" && c.session != nil && c.session.AccessToken != ""
}

// Upload implements the Upload method for realProtonClient.
func (c *realProtonClient) Upload(filepath string) error {
	// TODO: Implement actual upload logic using c.bridge, converting local filepath to remote path and handling streams.
	// Example: return c.bridge.UploadFile(localFilePath, remoteFolderID)
	_ = filepath // Avoid unused variable warning
	return nil
}

// Download implements the Download method for realProtonClient.
func (c *realProtonClient) Download(filepath string) error {
	// TODO: Implement actual download logic using c.bridge, converting remote filepath to local path and handling streams.
	// Example: return c.bridge.DownloadFile(remoteFileID, localFilePath)
	_ = filepath // Avoid unused variable warning
	return nil
}