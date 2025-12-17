// internal/config/paths.go
package config

import (
	"os"
	"path/filepath"
)

// AppName is the base folder name for the application.
const AppName = "protondrive-linux"

// ConfigDir returns the directory containing the configuration file.
// It is simply the parent directory of the config path.
func ConfigDir(baseDir string) (string, error) {
	configPath, err := GetConfigPath(baseDir)
	if err != nil {
		return "", err
	}
	return filepath.Dir(configPath), nil
}

// GetDataDir returns the absolute path to the data directory.
//
// If baseDir is non-empty, it will be used instead of the system XDG path (useful for tests).
// The directory is automatically created if it does not exist.
func GetDataDir(baseDir string) (string, error) {
	var dir string
	if baseDir != "" {
		dir = baseDir
	} else {
		xdgData := os.Getenv("XDG_DATA_HOME")
		if xdgData == "" {
			home, err := os.UserHomeDir()
			if err != nil {
				return "", err
			}
			xdgData = filepath.Join(home, ".local", "share")
		}
		dir = filepath.Join(xdgData, AppName)
	}

	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}

	return dir, nil
}

// GetCacheDir returns the absolute path to the cache directory.
//
// If baseDir is non-empty, it will be used as the root for the cache directory (useful for tests).
// The directory is automatically created if it does not exist.
func GetCacheDir(baseDir string) (string, error) {
	var dir string
	if baseDir != "" {
		dir = filepath.Join(baseDir, "cache")
	} else {
		xdgCache := os.Getenv("XDG_CACHE_HOME")
		if xdgCache == "" {
			home, err := os.UserHomeDir()
			if err != nil {
				return "", err
			}
			xdgCache = filepath.Join(home, ".cache")
		}
		dir = filepath.Join(xdgCache, AppName)
	}

	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}

	return dir, nil
}

// MustGetDataDir returns the data directory or panics on error.
//
// Useful in initialization where failure is unrecoverable.
func MustGetDataDir(baseDir string) string {
	dir, err := GetDataDir(baseDir)
	if err != nil {
		panic(err)
	}
	return dir
}

// MustGetCacheDir returns the cache directory or panics on error.
//
// Useful in initialization where failure is unrecoverable.
func MustGetCacheDir(baseDir string) string {
	dir, err := GetCacheDir(baseDir)
	if err != nil {
		panic(err)
	}
	return dir
}
