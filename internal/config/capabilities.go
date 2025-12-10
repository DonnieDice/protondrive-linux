package config

import (
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"
)

// SystemCapabilities holds information about the system's hardware capabilities.
type SystemCapabilities struct {
	TotalRAM     uint64 // Bytes
	AvailableRAM uint64 // Bytes
	CPUCores     int
	Architecture string // amd64, arm64, arm
	StorageType  string // SSD, HDD, UNKNOWN
}

// DetectCapabilities detects and returns the system's hardware capabilities.
func DetectCapabilities() SystemCapabilities {
	caps := SystemCapabilities{
		CPUCores:     runtime.NumCPU(),
		Architecture: runtime.GOARCH,
		StorageType:  detectStorageType("/tmp"), // Use /tmp for a general system storage test
	}

	totalRAM, availableRAM := detectRAM()
	caps.TotalRAM = totalRAM
	caps.AvailableRAM = availableRAM

	return caps
}

// detectRAM reads /proc/meminfo to get total and available RAM on Linux.
func detectRAM() (total uint64, available uint64) {
	if runtime.GOOS != "linux" {
		// Placeholder for non-Linux systems or more complex detection
		return 0, 0
	}

	content, err := ioutil.ReadFile("/proc/meminfo")
	if err != nil {
		fmt.Printf("Error reading /proc/meminfo: %v\n", err)
		return 0, 0
	}

	lines := strings.Split(string(content), "\n")
	for _, line := range lines {
		if strings.HasPrefix(line, "MemTotal:") {
			total = parseMeminfoLine(line) * 1024 // Convert KB to Bytes
		} else if strings.HasPrefix(line, "MemAvailable:") {
			available = parseMeminfoLine(line) * 1024 // Convert KB to Bytes
		}
	}
	return total, available
}

// parseMeminfoLine parses a line from /proc/meminfo to extract the memory value.
func parseMeminfoLine(line string) uint64 {
	parts := strings.Fields(line)
	if len(parts) >= 2 {
		value, err := strconv.ParseUint(parts[1], 10, 64)
		if err == nil {
			return value
		}
	}
	return 0
}

// detectStorageType attempts to determine the storage type by benchmarking a write operation.
func detectStorageType(path string) string {
	testFile := filepath.Join(path, ".storage-test-protondrive")
	testData := make([]byte, 10*1024*1024) // 10MB test file

	start := time.Now()

	// Write test
	f, err := os.Create(testFile)
	if err != nil {
		fmt.Printf("Error creating storage test file: %v\n", err)
		return "UNKNOWN"
	}
	_, err = f.Write(testData)
	if err != nil {
		fmt.Printf("Error writing to storage test file: %v\n", err)
		f.Close()
		os.Remove(testFile)
		return "UNKNOWN"
	}
	err = f.Sync() // Force flush to disk
	if err != nil {
		fmt.Printf("Error syncing storage test file: %v\n", err)
	}
	f.Close()
	os.Remove(testFile) // Clean up test file

	duration := time.Since(start)

	// Thresholds (these are heuristic and might need tuning)
	// SSDs are typically < 100ms for 10MB sync write
	// HDDs are typically > 200ms for 10MB sync write
	if duration < 100*time.Millisecond {
		return "SSD"
	} else if duration > 200*time.Millisecond {
		return "HDD"
	}
	return "UNKNOWN"
}

// DetectProfile selects the appropriate performance profile based on system capabilities.
func DetectProfile(caps SystemCapabilities) PerformanceProfile {
	totalRAMMB := caps.TotalRAM / 1024 / 1024

	if totalRAMMB < 4096 { // Less than 4GB
		return LowEndProfile{}
	} else if totalRAMMB < 8192 { // Less than 8GB
		return StandardProfile{}
	}
	return HighEndProfile{}
}