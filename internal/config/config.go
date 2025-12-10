package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync" // For mutex if concurrent access is a concern
)

const (
	// Default config file name
	configFileName = "config.json"
	// Default application config directory
	appName = "protondrive-linux"
)

// Config holds all application configuration settings.
type Config struct {
	// SyncDirectory specifies the local directory to synchronize with ProtonDrive.
	SyncDirectory string `json:"sync_directory"`

	// PerformanceProfile allows users to override the automatically detected profile.
	// Valid values: "Low-End", "Standard", "High-End"
	PerformanceProfile string `json:"performance_profile"`

	// VerboseLogging enables detailed logging for debugging purposes.
	// This should only print to stderr and not to files in production.
	VerboseLogging bool `json:"verbose_logging"`

	// DiskType allows users to manually specify their primary disk type for performance tuning.
	// Valid values: "SSD", "HDD", or empty for auto-detection/default.
	DiskType string `json:"disk_type"`

	// Add other user preferences and settings here
	// Example: AutoStart bool `json:"auto_start"`
}

// NewConfig creates and returns a Config with default values.
func NewConfig() *Config {
	homeDir, _ := os.UserHomeDir()
	defaultSyncDir := filepath.Join(homeDir, "ProtonDrive") // Default sync directory

	return &Config{
		SyncDirectory:      defaultSyncDir,
		PerformanceProfile: "Standard", // Default to Standard profile
		VerboseLogging:     false,
		DiskType:           "",         // Default to empty, meaning auto-detect or no specific user input
	}
}

// GetDefaultConfigPath returns the full path to the default configuration file location.
func GetDefaultConfigPath() (string, error) {
	configDir, err := os.UserConfigDir()
	if err != nil {
		return "", fmt.Errorf("failed to get user config directory: %w", err)
	}
	appConfigDir := filepath.Join(configDir, appName)
	return filepath.Join(appConfigDir, configFileName), nil
}

// GetConfigPath returns the full path to the configuration file,
// using baseDir if provided, otherwise using the default config directory.
// For testing, baseDir can be set to a temporary directory.
func GetConfigPath(baseDir string) (string, error) {
	if baseDir != "" {
		appConfigDir := filepath.Join(baseDir, appName)
		return filepath.Join(appConfigDir, configFileName), nil
	}
	return GetDefaultConfigPath()
}

// LoadConfig loads the configuration from the config file.
// If the file does not exist, it creates one with default values.
// baseDir can be provided for testing purposes; otherwise, pass an empty string.
func LoadConfig(baseDir string) (*Config, error) {
	cfg := NewConfig()
	configPath, err := GetConfigPath(baseDir)
	if err != nil {
		return nil, fmt.Errorf("failed to get config path: %w", err)
	}

	// Ensure the config directory exists
	configDir := filepath.Dir(configPath)
	if err := os.MkdirAll(configDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create config directory %s: %w", configDir, err)
	}

	data, err := os.ReadFile(configPath)
	if err != nil {
		if os.IsNotExist(err) {
			// Config file doesn't exist, save default config
			if err := cfg.Save(""); err != nil {
				return nil, fmt.Errorf("failed to save default config: %w", err)
			}
			return cfg, nil
		}
		return nil, fmt.Errorf("failed to read config file %s: %w", configPath, err)
	}

	if err := json.Unmarshal(data, cfg); err != nil {
		return nil, fmt.Errorf("failed to unmarshal config data: %w", err)
	}

	return cfg, nil
}

// Save saves the current configuration to the config file.
// baseDir can be provided for testing purposes; otherwise, pass an empty string.
func (c *Config) Save(baseDir string) error {
	configPath, err := GetConfigPath(baseDir)
	if err != nil {
		return fmt.Errorf("failed to get config path: %w", err)
	}

	// Ensure the config directory exists
	configDir := filepath.Dir(configPath)
	if err := os.MkdirAll(configDir, 0755); err != nil {
		return fmt.Errorf("failed to create config directory %s: %w", configDir, err)
	}

	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal config to JSON: %w", err)
	}

	if err := os.WriteFile(configPath, data, 0644); err != nil {
		return fmt.Errorf("failed to write config file %s: %w", configPath, err)
	}

	return nil
}

// Validate checks if the configuration values are valid.
func (c *Config) Validate() error {
	if c.SyncDirectory == "" {
		return fmt.Errorf("sync directory cannot be empty")
	}
	if _, err := os.Stat(c.SyncDirectory); os.IsNotExist(err) {
		// If sync directory doesn't exist, try to create it.
		if err := os.MkdirAll(c.SyncDirectory, 0755); err != nil {
			return fmt.Errorf("sync directory %s does not exist and cannot be created: %w", c.SyncDirectory, err)
		}
	} else if err != nil {
		return fmt.Errorf("failed to check sync directory %s: %w", c.SyncDirectory, err)
	}

	// Validate PerformanceProfile
	switch c.PerformanceProfile {
	case "Low-End", "Standard", "High-End":
		// Valid profile
	default:
		return fmt.Errorf("invalid performance profile: %s. Must be 'Low-End', 'Standard', or 'High-End'", c.PerformanceProfile)
	}

	// Validate DiskType
	switch strings.ToLower(c.DiskType) {
	case "", "ssd", "hdd":
		// Valid disk type or empty for auto-detection
	default:
		return fmt.Errorf("invalid disk type: %s. Must be 'SSD', 'HDD', or empty for auto-detection", c.DiskType)
	}

	return nil
}

// Mutex for protecting concurrent access to the config, if it were to be mutable after loading.
// For now, assuming config is loaded once and then read-only.
var configMutex sync.Mutex

// GlobalConfig holds the loaded application configuration.
// Access should be via LoadConfig at startup.
var GlobalConfig *Config

func init() {
	// Attempt to load config during package initialization.
	// In a real application, this might be handled more explicitly in main().
	cfg, err := LoadConfig("")
	if err != nil {
		// Log error during initialization, but don't panic.
		// Fallback to default config.
		fmt.Fprintf(os.Stderr, "Warning: Failed to load config, using default settings: %v\n", err)
		GlobalConfig = NewConfig()
	} else {
		GlobalConfig = cfg
	}
}
