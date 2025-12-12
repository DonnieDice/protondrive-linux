package security

import (
	"io/ioutil"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"yourproject/internal/config"
)

func TestConfigContainsNoSensitiveData(t *testing.T) {
	// Create a temporary baseDir for test isolation
	baseDir, err := ioutil.TempDir("", "protondrive_test")
	assert.NoError(t, err)
	defer os.RemoveAll(baseDir) // clean up after test

	// Create a config with sensitive entries
	cfg := config.NewConfig()
	cfg.SyncDirectory = "/home/user/secrets"
	cfg.VerboseLogging = true
	// Simulate sensitive filenames
	sensitiveFiles := []string{"passwords.txt", "secret_document.pdf", "token.json"}

	// Normally files would be in metadata; add to config for test
	for _, f := range sensitiveFiles {
		cfg.SyncDirectory += f // simulate sensitive entry
	}

	// Save config
	err = cfg.Save(baseDir)
	assert.NoError(t, err)

	// Read raw config file
	configPath := config.GetConfigPath(baseDir)
	rawBytes, err := ioutil.ReadFile(configPath)
	assert.NoError(t, err)
	rawContent := string(rawBytes)

	// Verify no sensitive filenames or tokens appear in plaintext
	for _, s := range sensitiveFiles {
		assert.NotContains(t, rawContent, s, "Sensitive data found in config file")
	}

	// Optional: verify non-sensitive fields are present
	assert.Contains(t, rawContent, "SyncDirectory")
	assert.Contains(t, rawContent, "VerboseLogging")
}
