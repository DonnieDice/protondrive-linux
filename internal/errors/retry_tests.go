package errors

import (
	"errors"
	"testing"
	"time"
)

func TestDefaultRetryConfig(t *testing.T) {
	cfg := DefaultRetryConfig()

	if cfg.MaxAttempts != 5 {
		t.Errorf("expected MaxAttempts=5, got %d", cfg.MaxAttempts)
	}
	if cfg.BaseDelay != 200*time.Millisecond {
		t.Errorf("expected BaseDelay=200ms, got %v", cfg.BaseDelay)
	}
	if cfg.MaxDelay != 5*time.Second {
		t.Errorf("expected MaxDelay=5s, got %v", cfg.MaxDelay)
	}
	if cfg.Multiplier != 2.0 {
		t.Errorf("expected Multiplier=2.0, got %v", cfg.Multiplier)
	}
	if cfg.Jitter != true {
		t.Errorf("expected Jitter=true")
	}
}

func TestIsRetryable(t *testing.T) {
	temp := &SafeError{IsTemporary: true}
	if !IsRetryable(temp) {
		t.Errorf("expected IsRetryable=true for temporary error")
	}

	nonTemp := &SafeError{IsTemporary: false}
	if IsRetryable(nonTemp) {
		t.Errorf("expected IsRetryable=false for non-temporary error")
	}

	normal := errors.New("plain error")
	if IsRetryable(normal) {
		t.Errorf("expected IsRetryable=false for generic error")
	}
}

func TestNextDelay_NoJitter(t *testing.T) {
	cfg := &RetryConfig{
		MaxAttempts: 3,
		BaseDelay:   100 * time.Millisecond,
		MaxDelay:    1 * time.Second,
		Multiplier:  2.0,
		Jitter:      false,
	}

	d1 := NextDelay(cfg, 1)
	if d1 != 100*time.Millisecond {
		t.Errorf("expected 100ms, got %v", d1)
	}

	d2 := NextDelay(cfg, 2)
	if d2 != 200*time.Millisecond {
		t.Errorf("expected 200ms, got %v", d2)
	}

	// attempt 10 must cap at MaxDelay
	dCap := NextDelay(cfg, 10)
	if dCap > cfg.MaxDelay {
		t.Errorf("expected <= MaxDelay (%v), got %v", cfg.MaxDelay, dCap)
	}
}

func TestNextDelay_WithJitter(t *testing.T) {
	cfg := &RetryConfig{
		MaxAttempts: 3,
		BaseDelay:   500 * time.Millisecond,
		MaxDelay:    5 * time.Second,
		Multiplier:  2.0,
		Jitter:      true,
	}

	expected := 1 * time.Second       // nominal for attempt 2
	min := time.Duration(float64(expected) * 0.8)
	max := time.Duration(float64(expected) * 1.2)

	d := NextDelay(cfg, 2)

	if d < min || d > max {
		t.Errorf("delay with jitter out of bounds: %v not in [%v, %v]", d, min, max)
	}
}
