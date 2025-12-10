package config

import (
	"os"
	"path/filepath"
	"testing"
	"encoding/json"

	"github.com/stretchr/testify/assert"
)

// SetupTestConfigDir creates a temporary directory and returns its path
// to be used as a baseDir for config functions, along with a cleanup function.
func SetupTestConfigDir(t *testing.T) (string, func()) {
	t.Helper()
	tempDir := t.TempDir()

	// Capture original env vars to restore later
	originalXDGConfigHome := os.Getenv("XDG_CONFIG_HOME")
	originalHome := os.Getenv("HOME")

	// Temporarily set XDG_CONFIG_HOME and HOME for tests
	// This ensures os.UserConfigDir() (called by GetDefaultConfigPath)
	// resolves to our tempDir when baseDir is ""
	os.Setenv("XDG_CONFIG_HOME", tempDir)
	os.Setenv("HOME", tempDir)

	cleanup := func() {
		os.Setenv("XDG_CONFIG_HOME", originalXDGConfigHome)
		os.Setenv("HOME", originalHome)
	}

	return tempDir, cleanup
}

func TestNewConfig(t *testing.T) {
	cfg := NewConfig()
	assert.NotNil(t, cfg)
	homeDir, _ := os.UserHomeDir()
	expectedSyncDir := filepath.Join(homeDir, "ProtonDrive")
	assert.Equal(t, expectedSyncDir, cfg.SyncDirectory)
	assert.Equal(t, "Standard", cfg.PerformanceProfile)
	assert.False(t, cfg.VerboseLogging)
	assert.Equal(t, "", cfg.DiskType) // Default DiskType should be empty
}

func TestGetDefaultConfigPath(t *testing.T) {
	testDir, cleanup := SetupTestConfigDir(t)
	defer cleanup()

	configPath, err := GetDefaultConfigPath()
	assert.NoError(t, err)

	expectedPath := filepath.Join(testDir, appName, configFileName) // Should resolve to tempDir due to mocking
	assert.Equal(t, expectedPath, configPath)
}

func TestGetConfigPath_WithBaseDir(t *testing.T) {
	_, cleanup := SetupTestConfigDir(t) // Still set env vars for GetDefaultConfigPath if called indirectly
	defer cleanup()

	baseDir := "/test/custom/dir"
	configPath, err := GetConfigPath(baseDir)
	assert.NoError(t, err)

	expectedPath := filepath.Join(baseDir, appName, configFileName)
	assert.Equal(t, expectedPath, configPath)
}

func TestGetConfigPath_EmptyBaseDir(t *testing.T) {
	testDir, cleanup := SetupTestConfigDir(t)
	defer cleanup()

	configPath, err := GetConfigPath("")
	assert.NoError(t, err)

	expectedPath := filepath.Join(testDir, appName, configFileName)
	assert.Equal(t, expectedPath, configPath)
}

func TestLoadConfig_NonExistentFile(t *testing.T) {
	testDir, cleanup := SetupTestConfigDir(t)
	defer cleanup()

	cfg, err := LoadConfig(testDir)
	assert.NoError(t, err)
	assert.NotNil(t, cfg)
	assert.Equal(t, NewConfig().SyncDirectory, cfg.SyncDirectory) // Should load defaults
	assert.Equal(t, NewConfig().PerformanceProfile, cfg.PerformanceProfile)

	// Verify the file was created
	configPath, _ := GetConfigPath(testDir)
	assert.FileExists(t, configPath)
}

func TestLoadConfig_ExistingValidFile(t *testing.T) {
	testDir, cleanup := SetupTestConfigDir(t)
	defer cleanup()

	// Create a dummy config file
	customConfig := &Config{
		SyncDirectory:      filepath.Join(testDir, "CustomSync"),
		PerformanceProfile: "High-End",
		VerboseLogging:     true,
		DiskType:           "SSD",
	}
	err := customConfig.Save(testDir) // Save with baseDir
	assert.NoError(t, err)

	loadedConfig, err := LoadConfig(testDir) // Load with baseDir
	assert.NoError(t, err)
	assert.NotNil(t, loadedConfig)
	assert.Equal(t, customConfig.SyncDirectory, loadedConfig.SyncDirectory)
	assert.Equal(t, customConfig.PerformanceProfile, loadedConfig.PerformanceProfile)
	assert.Equal(t, customConfig.VerboseLogging, loadedConfig.VerboseLogging)
}

func TestLoadConfig_InvalidJSON(t *testing.T) {
	testDir, cleanup := SetupTestConfigDir(t)
	defer cleanup()

	configPath, _ := GetConfigPath(testDir) // Get path using baseDir
	configDir := filepath.Dir(configPath)
	os.MkdirAll(configDir, 0755) // Ensure directory exists
	err := os.WriteFile(configPath, []byte("{invalid json"), 0644)
	assert.NoError(t, err)

	cfg, err := LoadConfig(testDir) // Load with baseDir
	assert.Error(t, err)
	assert.Nil(t, cfg)
	assert.Contains(t, err.Error(), "failed to unmarshal config data")
}

func TestSaveConfig(t *testing.T) {
	testDir, cleanup := SetupTestConfigDir(t)
	defer cleanup()

	cfg := NewConfig()
	cfg.SyncDirectory = filepath.Join(testDir, "new/sync/dir") // Use a test-friendly path
	cfg.PerformanceProfile = "Low-End"
	cfg.VerboseLogging = true
	cfg.DiskType = "HDD"

	err := cfg.Save(testDir) // Save with baseDir
	assert.NoError(t, err)

	configPath, _ := GetConfigPath(testDir)
	assert.FileExists(t, configPath)

	// Read and verify content
	data, err := os.ReadFile(configPath)
	assert.NoError(t, err)

	var loadedCfg Config
	err = json.Unmarshal(data, &loadedCfg)
	assert.NoError(t, err)
	assert.Equal(t, cfg.SyncDirectory, loadedCfg.SyncDirectory)
	assert.Equal(t, cfg.PerformanceProfile, loadedCfg.PerformanceProfile)
	assert.Equal(t, cfg.VerboseLogging, loadedCfg.VerboseLogging)
}

func TestValidate_ValidConfig(t *testing.T) {
	// No need for SetupTestConfigDir as it doesn't touch config files
	cfg := NewConfig()
	tempSyncDir := t.TempDir()
	cfg.SyncDirectory = tempSyncDir // Ensure it's a valid path
	defer os.RemoveAll(tempSyncDir) // Clean up

	assert.NoError(t, cfg.Validate())

	cfg.PerformanceProfile = "Low-End"
	assert.NoError(t, cfg.Validate())

	cfg.PerformanceProfile = "High-End"
	assert.NoError(t, cfg.Validate())

	cfg.DiskType = "SSD"
	assert.NoError(t, cfg.Validate())

	cfg.DiskType = "hdd" // Case-insensitive check
	assert.NoError(t, cfg.Validate())

	cfg.DiskType = "" // Empty is valid
	assert.NoError(t, cfg.Validate())
}

func TestValidate_InvalidSyncDirectory(t *testing.T) {
	cfg := NewConfig()
	cfg.SyncDirectory = ""
	assert.Error(t, cfg.Validate())
	assert.Contains(t, cfg.Validate().Error(), "sync directory cannot be empty")

	// Test with a path that cannot be created (e.g., in a non-existent, permission-denied parent)
	cfg.SyncDirectory = "/root/nonexistent/sync" // This path is generally uncreatable for non-root
	if os.Getuid() != 0 {                       // Only run this specific assertion if not root
		assert.Error(t, cfg.Validate())
		assert.Contains(t, cfg.Validate().Error(), "cannot be created")
	}
}

func TestValidate_InvalidPerformanceProfile(t *testing.T) {
	cfg := NewConfig()
	cfg.SyncDirectory = t.TempDir() // Valid sync dir
	defer os.RemoveAll(cfg.SyncDirectory)

	cfg.PerformanceProfile = "InvalidProfile"
	assert.Error(t, cfg.Validate())
	assert.Contains(t, cfg.Validate().Error(), "invalid performance profile")
}

func TestValidate_InvalidDiskType(t *testing.T) {
	cfg := NewConfig()
	cfg.SyncDirectory = t.TempDir() // Valid sync dir
	defer os.RemoveAll(cfg.SyncDirectory)

	cfg.DiskType = "InvalidDiskType"
	assert.Error(t, cfg.Validate())
	assert.Contains(t, cfg.Validate().Error(), "invalid disk type")

	cfg.DiskType = "sssd"
	assert.Error(t, cfg.Validate())
	assert.Contains(t, cfg.Validate().Error(), "invalid disk type")
}
