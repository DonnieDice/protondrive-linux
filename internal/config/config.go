package config

// Config represents the application's configuration.
type Config struct {
	SyncDir        string
	Profile        PerformanceProfile
	LogLevel       string
	ProtonUsername string
	// Don't store password in config!
}
