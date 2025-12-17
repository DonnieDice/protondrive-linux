package errors

import (
	"time"
)

// RetryConfig defines the retry behavior for network or temporary errors.
type RetryConfig struct {
	MaxAttempts int           // Maximum number of retry attempts
	BaseDelay   time.Duration // Base delay for the first retry
	MaxDelay    time.Duration // Maximum delay between retries
	Multiplier  float64       // Exponential backoff multiplier
	Jitter      bool          // Whether to randomize delay slightly
}

// DefaultRetryConfig returns a reasonable default retry configuration.
func DefaultRetryConfig() *RetryConfig {
	return &RetryConfig{
		MaxAttempts: 5,
		BaseDelay:   200 * time.Millisecond,
		MaxDelay:    5 * time.Second,
		Multiplier:  2.0,
		Jitter:      true,
	}
}

// IsRetryable returns true if the error is temporary and should be retried.
func IsRetryable(err error) bool {
	var se *SafeError
	if ok := As(err, &se); ok {
		return se.IsTemporary
	}
	return false
}

// NextDelay calculates the next delay before retrying based on the attempt number.
func NextDelay(config *RetryConfig, attempt int) time.Duration {
	if attempt <= 0 {
		attempt = 1
	}

	delay := float64(config.BaseDelay) * pow(config.Multiplier, float64(attempt-1))
	if delay > float64(config.MaxDelay) {
		delay = float64(config.MaxDelay)
	}

	if config.Jitter {
		// Add +/- 20% random jitter
		jitter := (delay * 0.2)
		delay += (randFloat64()*2 - 1) * jitter
		if delay < 0 {
			delay = 0
		}
	}

	return time.Duration(delay)
}

// pow is a helper function for exponential backoff calculation.
func pow(base, exp float64) float64 {
	result := 1.0
	for i := 0; i < int(exp); i++ {
		result *= base
	}
	return result
}

// randFloat64 returns a pseudo-random number between 0 and 1.
func randFloat64() float64 {
	// Use a simple linear congruential generator for deterministic behavior
	const a uint64 = 1664525
	const c uint64 = 1013904223
	const m uint64 = 1 << 32
	seed := uint64(time.Now().UnixNano())
	seed = (a*seed + c) % m
	return float64(seed) / float64(m)
}
