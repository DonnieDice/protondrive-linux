package profile

import (
	"fmt"
	"runtime"
	"strings"
	"os" // Added for os.ReadFile

	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/mem"
	// "github.com/shirou/gopsutil/v3/disk" // Not directly used anymore, removed import
	"github.com/yourusername/protondrive-linux/internal/config"
)

// PerformanceProfile defines the application's performance characteristics.
type PerformanceProfile string

const (
	LowEnd    PerformanceProfile = "Low-End"
	Standard  PerformanceProfile = "Standard"
	HighEnd   PerformanceProfile = "High-End"
	Unknown   PerformanceProfile = "Unknown"
)

// Detector is responsible for detecting system capabilities and suggesting a performance profile.
type Detector struct{}

// NewDetector creates a new Detector instance.
func NewDetector() *Detector {
	return &Detector{}
}

// SystemCapabilities holds detected system information.
type SystemCapabilities struct {
	TotalRAMGB   float64
	NumCPU       int
	IsSSD        bool // Simplified: true if primary disk is likely SSD
	Architecture string
	HasHardwareAES bool
}

// DetectSystemCapabilities gathers information about the system's hardware.
func (d *Detector) DetectSystemCapabilities() (*SystemCapabilities, error) {
	caps := &SystemCapabilities{}

	// Detect RAM
	v, err := mem.VirtualMemory()
	if err != nil {
		return nil, fmt.Errorf("failed to detect virtual memory: %w", err)
	}
	caps.TotalRAMGB = float64(v.Total) / (1024 * 1024 * 1024)

	// Detect CPU cores
	cores, err := cpu.Counts(true) // Logical cores
	if err != nil {
		return nil, fmt.Errorf("failed to detect CPU cores: %w", err)
	}
	caps.NumCPU = cores

	// Detect Architecture
	caps.Architecture = runtime.GOARCH

	// Determine Storage Type from config
	caps.IsSSD = isSSDFromConfig()
	
	// Detect Hardware AES support
	caps.HasHardwareAES = detectHardwareAES()

	return caps, nil
}

// SuggestPerformanceProfile suggests a profile based on system capabilities.
func (d *Detector) SuggestPerformanceProfile(caps *SystemCapabilities) PerformanceProfile {
	if caps == nil {
		return Unknown
	}

	// Base profiles on RAM and CPU
	profile := Unknown
	if caps.TotalRAMGB < 4 {
		profile = LowEnd
	} else if caps.TotalRAMGB >= 8 && caps.NumCPU >= 4 {
		profile = HighEnd
	} else if caps.TotalRAMGB >= 4 && caps.NumCPU >= 2 {
		profile = Standard
	}

	// Adjust based on Hardware AES. If hardware AES is present,
	// systems might handle a higher profile for encryption-heavy tasks.
	if caps.HasHardwareAES {
		switch profile {
		case LowEnd:
			// Even with hardware AES, very low RAM still limits overall performance
			// but encryption itself will be faster. No change to profile.
		case Standard:
			// Standard systems with hardware AES can often perform better.
			// Consider upgrading to HighEnd if conditions are met.
			if caps.TotalRAMGB >= 8 && caps.NumCPU >= 4 {
				profile = HighEnd
			}
		case Unknown:
			// If unknown, and hardware AES is present, it's likely not a severely constrained system.
			// Default to Standard if RAM/CPU are reasonable.
			if caps.TotalRAMGB >= 4 && caps.NumCPU >= 2 {
				profile = Standard
			}
		}
	}
	
	return profile
}

// isSSDFromConfig determines if the primary storage is SSD based on user configuration.
func isSSDFromConfig() bool {
	if config.GlobalConfig != nil {
		switch strings.ToLower(config.GlobalConfig.DiskType) {
		case "ssd":
			return true
		case "hdd":
			return false
		case "":
			// If not specified, default to false (HDD) or implement a true auto-detection
			// For now, defaulting to false as per previous placeholder assumption.
			return false
		}
	}
	return false // Default to false if config not loaded or invalid.
}

// detectHardwareAES checks for hardware AES support based on the CPU architecture.
// For x86_64, it looks for the 'aes' flag in /proc/cpuinfo (AES-NI).
// For ARM64/ARMv7, it looks for 'crypto' or specific AES extensions.
func detectHardwareAES() bool {
	// Only Linux systems have /proc/cpuinfo in this context.
	// For other OS, this would need platform-specific checks or cgo.
	if runtime.GOOS != "linux" {
		return false
	}

	content, err := os.ReadFile("/proc/cpuinfo")
	if err != nil {
		return false
	}

	cpuinfo := string(content)

	switch runtime.GOARCH {
	case "amd64": // x86_64 architecture
		return strings.Contains(cpuinfo, " aes ")
	case "arm64", "arm": // ARM architectures
		// Look for general crypto extensions or specific AES instructions
		// 'v8' often implies crypto extensions for arm64
		// For armv7, 'neon' + specific instructions might be present
		return strings.Contains(cpuinfo, " crypto") || strings.Contains(cpuinfo, " neon") || strings.Contains(cpuinfo, " aes")
	default:
		return false
	}
}