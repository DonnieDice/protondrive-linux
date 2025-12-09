package main

import (
	"fmt"
	"github.com/yourusername/protondrive-linux/internal/config"
)

func main() {
	fmt.Println("ProtonDrive Linux - Go Edition")

	caps := config.DetectCapabilities()
	// profile := config.DetectProfile(caps) // This will be implemented later

	fmt.Printf("Detected profile: %T\n", "UNKNOWN") // Placeholder
	fmt.Printf("RAM: %d MB\n", caps.TotalRAM/1024/1024)
	fmt.Printf("CPU Cores: %d\n", caps.CPUCores)
}