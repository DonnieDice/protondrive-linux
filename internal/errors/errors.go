package errors

import (
	"fmt"
	"regexp"
	"strings"
)

// SafeError is a custom error type that wraps an internal error and provides
// a safe, non-sensitive message that can be exposed to users or logs.
// It helps prevent leaking sensitive information from internal error details.
type SafeError struct {
	// InternalErr is the underlying, detailed error.
	InternalErr error
	// SafeMsg is a user-friendly or sanitized error message.
	SafeMsg string
	// IsTemporary indicates if the error is temporary and can be retried.
	IsTemporary bool
	// IsUserError indicates if the error is due to user action/input.
	IsUserError bool
}

// Error implements the error interface for SafeError.
func (e *SafeError) Error() string {
	if e.InternalErr != nil {
		return fmt.Sprintf("safe_error: %s (internal: %v)", e.SafeMsg, e.InternalErr)
	}
	return fmt.Sprintf("safe_error: %s", e.SafeMsg)
}

// Unwrap returns the underlying internal error, supporting errors.Is and errors.As.
func (e *SafeError) Unwrap() error {
	return e.InternalErr
}

// SafeMessage returns the safe, non-sensitive message of the error.
func (e *SafeError) SafeMessage() string {
	return e.SafeMsg
}

// NewSafeError creates a new SafeError.
func NewSafeError(internalErr error, safeMsg string, isTemporary, isUserError bool) *SafeError {
	return &SafeError{
		InternalErr: internalErr,
		SafeMsg:     safeMsg,
		IsTemporary: isTemporary,
		IsUserError: isUserError,
	}
}

// Predefined common errors
var (
	ErrAuthenticationFailed = NewSafeError(nil, "Authentication failed. Please check your credentials.", false, true)
	ErrNetworkTimeout       = NewSafeError(nil, "Network operation timed out. Please check your internet connection.", true, false)
	ErrFileNotFound         = NewSafeError(nil, "File not found.", false, true)
	ErrInvalidConfig        = NewSafeError(nil, "Invalid configuration detected. Please check application settings.", false, true)
	ErrStorageFull          = NewSafeError(nil, "Storage limit reached. Please free up space.", false, true)
	ErrPermissionDenied     = NewSafeError(nil, "Permission denied. Please check your access rights.", false, true)
	ErrDatabase           = NewSafeError(nil, "A database error occurred. Please try again later.", false, false)
	ErrInternal             = NewSafeError(nil, "An internal error occurred. Please contact support.", false, false)
)

// MaskSensitiveData takes an error and returns its safe message.
// If the error is a SafeError, it returns its SafeMsg. Otherwise, it returns
// a generic message to prevent leaking unexpected sensitive data.
func MaskSensitiveData(err error) string {
	if err == nil {
		return ""
	}
	var se *SafeError
	if As(err, &se) {
		return se.SafeMsg
	}
	// Fallback for any other unexpected error type.
	return "An unexpected error occurred."
}

// Is reports whether any error in err's chain matches target.
func Is(err, target error) bool {
	return errors.Is(err, target)
}

// As finds the first error in err's chain that matches target, and if so, sets target to that error value and returns true.
func As(err error, target interface{}) bool {
	return errors.As(err, target)
}

// Wrap is a utility function to create a SafeError from an existing error,
// providing a consistent way to wrap errors for reporting.
// It inspects the original error to deduce SafeMsg if not provided explicitly.
func Wrap(err error, safeMsg ...string) *SafeError {
	if err == nil {
		return nil
	}

	// If the error is already a SafeError, return it directly.
	if se, ok := err.(*SafeError); ok {
		return se
	}

	// Try to deduce SafeMsg from known predefined errors
	for _, predErr := range []*SafeError{
		ErrAuthenticationFailed, ErrNetworkTimeout, ErrFileNotFound,
		ErrInvalidConfig, ErrStorageFull, ErrPermissionDenied,
		ErrDatabase, ErrInternal,
	} {
		if errors.Is(err, predErr.InternalErr) {
			return NewSafeError(err, predErr.SafeMsg, predErr.IsTemporary, predErr.IsUserError)
		}
	}

	// Default safe message
	msg := "An unexpected error occurred."
	if len(safeMsg) > 0 && safeMsg[0] != "" {
		msg = safeMsg[0]
	}

	// Attempt to make message safer by removing specific details often found in Go's default error.
	// This is a heuristic and should be used with caution.
	if !strings.Contains(msg, "file ID:") { // Only if not already using file ID
		msg = sanitizeErrorMessage(msg)
	}

	return NewSafeError(err, msg, false, false)
}

// sanitizeErrorMessage attempts to remove potentially sensitive details from a given error message string.
// This is a heuristic and might need to be refined as specific sensitive patterns are identified.
func sanitizeErrorMessage(msg string) string {
	// Remove file paths
	msg = strings.ReplaceAll(msg, "/home/user/", "~/")
	msg = strings.ReplaceAll(msg, "/var/log/", "")
	msg = strings.ReplaceAll(msg, "/tmp/", "")

	// Remove IP addresses or ports (simple regex could be more robust)
	msg = stripIPAddresses(msg)

	// Remove specific error codes or internal IDs that might be sensitive
	msg = stripInternalIDs(msg)

	return msg
}

// stripIPAddresses removes simple IPv4 and port patterns.
func stripIPAddresses(s string) string {
	// Very basic, might need a more robust regex for full IP/port scrubbing
	// Example: "192.168.1.1:8080" or "10.0.0.1"
	re := regexp.MustCompile(`\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?\b`)
	return re.ReplaceAllString(s, "[REDACTED_IP]")
}

// stripInternalIDs removes generic internal ID patterns.
func stripInternalIDs(s string) string {
	// Example: "id=XYZ-123", "uuid:abc-def-123"
	re := regexp.MustCompile(`\b(?:id|uuid|key):[a-zA-Z0-9-]+`)
	return re.ReplaceAllString(s, "[REDACTED_ID]")
}