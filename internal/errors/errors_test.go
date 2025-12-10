package errors

import (
	"errors"
	"fmt"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestNewSafeError(t *testing.T) {
	internalErr := errors.New("something went wrong internally")
	safeMsg := "User-friendly message."
	se := NewSafeError(internalErr, safeMsg, true, false)

	assert.Equal(t, internalErr, se.InternalErr)
	assert.Equal(t, safeMsg, se.SafeMsg)
	assert.True(t, se.IsTemporary)
	assert.False(t, se.IsUserError)
	assert.Contains(t, se.Error(), safeMsg)
	assert.Contains(t, se.Error(), internalErr.Error())
	assert.Equal(t, safeMsg, se.SafeMessage())
}

func TestSafeError_Unwrap(t *testing.T) {
	internalErr := errors.New("underlying problem")
	wrappedErr := NewSafeError(internalErr, "Failed.", false, false)

	assert.True(t, errors.Is(wrappedErr, internalErr))
	
	var se *SafeError
	assert.True(t, errors.As(wrappedErr, &se))
	assert.Equal(t, wrappedErr, se)
}

func TestMaskSensitiveData(t *testing.T) {
	// Test with SafeError
	se := NewSafeError(errors.New("internal details"), "Access Denied.", false, true)
	assert.Equal(t, "Access Denied.", MaskSensitiveData(se))

	// Test with generic error
	genericErr := errors.New("detailed path: /var/log/app.log")
	assert.Equal(t, "An unexpected error occurred.", MaskSensitiveData(genericErr))

	// Test with nil error
	assert.Empty(t, MaskSensitiveData(nil))
}

func TestWrap(t *testing.T) {
	t.Run("Wrap generic error", func(t *testing.T) {
		internalErr := fmt.Errorf("failed to connect to 192.168.1.1:8080: connection refused")
		wrapped := Wrap(internalErr)
		assert.NotNil(t, wrapped)
		assert.Equal(t, internalErr, wrapped.InternalErr)
		assert.Contains(t, wrapped.Error(), internalErr.Error())
		assert.NotContains(t, wrapped.SafeMessage(), "192.168.1.1:8080") // Should be sanitized
		assert.Equal(t, "An unexpected error occurred.", wrapped.SafeMessage())
	})

	t.Run("Wrap generic error with custom safe message", func(t *testing.T) {
		internalErr := errors.New("detailed error message with file path /home/user/secret.txt")
		wrapped := Wrap(internalErr, "Something went wrong.")
		assert.NotNil(t, wrapped)
		assert.Equal(t, internalErr, wrapped.InternalErr)
		assert.Contains(t, wrapped.Error(), internalErr.Error())
		assert.Equal(t, "Something went wrong.", wrapped.SafeMessage())
	})

	t.Run("Wrap known error", func(t *testing.T) {
		authFailed := errors.New("failed srp challenge")
		wrapped := Wrap(authFailed, ErrAuthenticationFailed.SafeMsg) // Wrap with predefined safe message
		assert.True(t, errors.Is(wrapped, ErrAuthenticationFailed))
		assert.Contains(t, wrapped.Error(), authFailed.Error())
		assert.Equal(t, ErrAuthenticationFailed.SafeMsg, wrapped.SafeMessage())
	})

	t.Run("Wrap already SafeError", func(t *testing.T) {
		originalSafeErr := NewSafeError(errors.New("original internal"), "Original safe", true, false)
		wrapped := Wrap(originalSafeErr)
		assert.Equal(t, originalSafeErr, wrapped) // Should return the same SafeError
	})
}

func TestSanitizeErrorMessage(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "Removes file paths",
			input:    "Error reading /home/user/documents/secret.txt and /tmp/tempfile.log",
			expected: "Error reading ~/documents/secret.txt and /tempfile.log",
		},
		{
			name:     "Removes IP addresses and ports",
			input:    "Connection to 192.168.1.1:8080 failed, then tried 10.0.0.5",
			expected: "Connection to [REDACTED_IP] failed, then tried [REDACTED_IP]",
		},
		{
			name:     "Removes internal IDs",
			input:    "Transaction failed: id=txn-abc-123 and another uuid:def-456",
			expected: "Transaction failed: [REDACTED_ID] and another [REDACTED_ID]",
		},
		{
			name:     "Combines sanitization",
			input:    "Failed to upload /var/log/nginx/access.log to 172.16.0.1:443 with request_id:XYZ-789",
			expected: "Failed to upload /nginx/access.log to [REDACTED_IP] with [REDACTED_ID]",
		},
		{
			name:     "No sensitive data",
			input:    "Simple error message.",
			expected: "Simple error message.",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expected, sanitizeErrorMessage(tt.input))
		})
	}
}

func TestPredefinedErrors(t *testing.T) {
	// Test that predefined errors are SafeError instances and have safe messages
	assert.NotNil(t, ErrAuthenticationFailed)
	assert.Contains(t, ErrAuthenticationFailed.Error(), "Authentication failed.")
	assert.Equal(t, "Authentication failed. Please check your credentials.", ErrAuthenticationFailed.SafeMessage())

	assert.NotNil(t, ErrNetworkTimeout)
	assert.Contains(t, ErrNetworkTimeout.Error(), "Network operation timed out.")

	// Test errors.Is with predefined errors
	underlyingErr := errors.New("db connection failed")
	dbErr := NewSafeError(underlyingErr, ErrDatabase.SafeMsg, false, false)
	assert.True(t, errors.Is(dbErr, underlyingErr)) // Unwrap works
	assert.True(t, errors.Is(dbErr, ErrDatabase))   // errors.Is should work with predefined SafeError

	// Test with a wrapped error that is not a predefined one
	errUnknown := errors.New("some unknown critical error")
	wrappedUnknown := Wrap(errUnknown)
	assert.False(t, errors.Is(wrappedUnknown, ErrAuthenticationFailed))
	assert.Equal(t, "An unexpected error occurred.", wrappedUnknown.SafeMessage())
}