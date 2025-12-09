package config

// PerformanceProfile defines the interface for different performance profiles.
type PerformanceProfile interface {
	MaxConcurrentUploads() int
	MaxConcurrentDownloads() int
	CacheSizeMB() int
	ChunkSizeMB() int
}

// LowEndProfile is for systems with limited resources.
type LowEndProfile struct{}

// MaxConcurrentUploads returns the maximum number of concurrent uploads for the low-end profile.
func (p LowEndProfile) MaxConcurrentUploads() int { return 1 }

// MaxConcurrentDownloads returns the maximum number of concurrent downloads for the low-end profile.
func (p LowEndProfile) MaxConcurrentDownloads() int { return 2 }

// CacheSizeMB returns the cache size in megabytes for the low-end profile.
func (p LowEndProfile) CacheSizeMB() int { return 50 }

// ChunkSizeMB returns the chunk size in megabytes for the low-end profile.
func (p LowEndProfile) ChunkSizeMB() int { return 5 }

// StandardProfile is for systems with moderate resources.
type StandardProfile struct{}

// MaxConcurrentUploads returns the maximum number of concurrent uploads for the standard profile.
func (p StandardProfile) MaxConcurrentUploads() int { return 3 }

// MaxConcurrentDownloads returns the maximum number of concurrent downloads for the standard profile.
func (p StandardProfile) MaxConcurrentDownloads() int { return 5 }

// CacheSizeMB returns the cache size in megabytes for the standard profile.
func (p StandardProfile) CacheSizeMB() int { return 100 }

// ChunkSizeMB returns the chunk size in megabytes for the standard profile.
func (p StandardProfile) ChunkSizeMB() int { return 5 }

// HighEndProfile is for systems with ample resources.
type HighEndProfile struct{}

// MaxConcurrentUploads returns the maximum number of concurrent uploads for the high-end profile.
func (p HighEndProfile) MaxConcurrentUploads() int { return 5 }

// MaxConcurrentDownloads returns the maximum number of concurrent downloads for the high-end profile.
func (p HighEndProfile) MaxConcurrentDownloads() int { return 10 }

// CacheSizeMB returns the cache size in megabytes for the high-end profile.
func (p HighEndProfile) CacheSizeMB() int { return 200 }

// ChunkSizeMB returns the chunk size in megabytes for the high-end profile.
func (p HighEndProfile) ChunkSizeMB() int { return 10 }
