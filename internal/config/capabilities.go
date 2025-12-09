package config

import (
	"runtime"
)

// SystemCapabilities represents the system's hardware capabilities.
type SystemCapabilities struct {
	TotalRAM     uint64
	AvailableRAM uint64
	CPUCores     int
	Architecture string
	StorageType  string
}

// DetectCapabilities detects the system's hardware capabilities.
// Note: This is a basic implementation. More platform-specific code
// may be required for accurate detection.
func DetectCapabilities() SystemCapabilities {
	// TODO: Implement more accurate detection for RAM and StorageType.
	return SystemCapabilities{
		TotalRAM:     0, // Placeholder
		AvailableRAM: 0, // Placeholder
		CPUCores:     runtime.NumCPU(),
		Architecture: runtime.GOARCH,
		StorageType:  "UNKNOWN", // Placeholder
	}
}
