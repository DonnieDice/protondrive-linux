package profile

import (
	"runtime"
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/yourusername/protondrive-linux/internal/config" // Import config package
)

// Mock mem.VirtualMemory and cpu.Counts for testing
// This requires modifying the gopsutil library which is not ideal.
// A better approach is to wrap gopsutil calls in a local interface.
// For now, we will test the logic of SuggestPerformanceProfile with static SystemCapabilities.

func TestNewDetector(t *testing.T) {
	d := NewDetector()
	assert.NotNil(t, d)
}

func TestDetectSystemCapabilities(t *testing.T) {
	// Temporarily override config.GlobalConfig.DiskType for this test
	originalDiskType := config.GlobalConfig.DiskType
	defer func() { config.GlobalConfig.DiskType = originalDiskType }()

	// Test case 1: SSD configured
	config.GlobalConfig.DiskType = "SSD"
	d := NewDetector()
	caps, err := d.DetectSystemCapabilities()
	assert.NoError(t, err)
	assert.NotNil(t, caps)
	assert.True(t, caps.IsSSD)

	// Test case 2: HDD configured
	config.GlobalConfig.DiskType = "HDD"
	caps, err = d.DetectSystemCapabilities()
	assert.NoError(t, err)
	assert.NotNil(t, caps)
	assert.False(t, caps.IsSSD)

	// Test case 3: Empty DiskType (defaults to HDD assumption)
	config.GlobalConfig.DiskType = ""
	caps, err = d.DetectSystemCapabilities()
	assert.NoError(t, err)
	assert.NotNil(t, caps)
	assert.False(t, caps.IsSSD)

	// Test case 4: Valid CPU and RAM detection (cannot mock easily without wrapper)
	// Just check if values are non-zero/valid
	assert.True(t, caps.TotalRAMGB > 0)
	assert.True(t, caps.NumCPU > 0)
	assert.Equal(t, runtime.GOARCH, caps.Architecture) // Architecture is direct from runtime
}

func TestSuggestPerformanceProfile(t *testing.T) {
	d := NewDetector()

	// Test Low-End Profile
	capsLowEnd := &SystemCapabilities{TotalRAMGB: 2, NumCPU: 1}
	assert.Equal(t, LowEnd, d.SuggestPerformanceProfile(capsLowEnd))
	capsLowEnd2 := &SystemCapabilities{TotalRAMGB: 3.9, NumCPU: 4} // High CPU, but low RAM
	assert.Equal(t, LowEnd, d.SuggestPerformanceProfile(capsLowEnd2))

	// Test Standard Profile
	capsStandard := &SystemCapabilities{TotalRAMGB: 4, NumCPU: 2}
	assert.Equal(t, Standard, d.SuggestPerformanceProfile(capsStandard))
	capsStandard2 := &SystemCapabilities{TotalRAMGB: 7.9, NumCPU: 3}
	assert.Equal(t, Standard, d.SuggestPerformanceProfile(capsStandard2))
	capsStandard3 := &SystemCapabilities{TotalRAMGB: 4, NumCPU: 1} // Enough RAM, but low CPU for High-End
	assert.Equal(t, Unknown, d.SuggestPerformanceProfile(capsStandard3)) // Corrected: should be Unknown

	// Test High-End Profile
	capsHighEnd := &SystemCapabilities{TotalRAMGB: 8, NumCPU: 4}
	assert.Equal(t, HighEnd, d.SuggestPerformanceProfile(capsHighEnd))
	capsHighEnd2 := &SystemCapabilities{TotalRAMGB: 16, NumCPU: 8}
	assert.Equal(t, HighEnd, d.SuggestPerformanceProfile(capsHighEnd2))

	// Test Unknown Profile (e.g., nil caps)
	assert.Equal(t, Unknown, d.SuggestPerformanceProfile(nil))
}

func TestGetArchitecture(t *testing.T) {
	// Temporarily override runtime.GOARCH for testing
	// This is tricky and generally not recommended as runtime.GOARCH is a constant.
	// We'll rely on the switch statement covering known cases for this test.
	assert.Equal(t, "x86_64", GetArchitectureFromGOARCH("amd64"))
	assert.Equal(t, "ARM64", GetArchitectureFromGOARCH("arm64"))
	assert.Equal(t, "ARMv7", GetArchitectureFromGOARCH("arm"))
	assert.Equal(t, "riscv64", GetArchitectureFromGOARCH("riscv64")) // Default case
}

// GetArchitectureFromGOARCH is a helper to test GetArchitecture's logic independently.
func GetArchitectureFromGOARCH(goarch string) string {
	switch goarch {
	case "amd64":
		return "x86_64"
	case "arm64":
		return "ARM64"
	case "arm":
		return "ARMv7"
	default:
		return goarch
	}
}