package config

// PerformanceProfile defines the interface for different performance profiles.
type PerformanceProfile interface {
	MaxConcurrentUploads() int
	MaxConcurrentDownloads() int
	CacheSizeMB() int
	ChunkSizeMB() int
}

// LowEndProfile implements PerformanceProfile for low-end systems.
type LowEndProfile struct{}

// MaxConcurrentUploads returns the maximum concurrent uploads for a low-end profile.
func (p LowEndProfile) MaxConcurrentUploads() int { return 1 }

// MaxConcurrentDownloads returns the maximum concurrent downloads for a low-end profile.
func (p LowEndProfile) MaxConcurrentDownloads() int { return 2 }

// CacheSizeMB returns the cache size in MB for a low-end profile.
func (p LowEndProfile) CacheSizeMB() int { return 50 }

// ChunkSizeMB returns the chunk size in MB for a low-end profile.
func (p LowEndProfile) ChunkSizeMB() int { return 5 }

// StandardProfile implements PerformanceProfile for standard systems.
type StandardProfile struct{}

// MaxConcurrentUploads returns the maximum concurrent uploads for a standard profile.
func (p StandardProfile) MaxConcurrentUploads() int { return 3 }

// MaxConcurrentDownloads returns the maximum concurrent downloads for a standard profile.
func (p StandardProfile) MaxConcurrentDownloads() int { return 5 }

// CacheSizeMB returns the cache size in MB for a standard profile.
func (p StandardProfile) CacheSizeMB() int { return 100 }

// ChunkSizeMB returns the chunk size in MB for a standard profile.
func (p StandardProfile) ChunkSizeMB() int { return 5 }

// HighEndProfile implements PerformanceProfile for high-end systems.
type HighEndProfile struct{}

// MaxConcurrentUploads returns the maximum concurrent uploads for a high-end profile.
func (p HighEndProfile) MaxConcurrentUploads() int { return 5 }

// MaxConcurrentDownloads returns the maximum concurrent downloads for a high-end profile.
func (p HighEndProfile) MaxConcurrentDownloads() int { return 10 }

// CacheSizeMB returns the cache size in MB for a high-end profile.
func (p HighEndProfile) CacheSizeMB() int { return 200 }

// ChunkSizeMB returns the chunk size in MB for a high-end profile.
func (p HighEndProfile) ChunkSizeMB() int { return 10 }