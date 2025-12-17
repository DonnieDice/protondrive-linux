package errors

// userMessages maps predefined error codes to friendly messages for end users.
var userMessages = map[ErrorCode]string{
	ErrCodeAuth:       "Authentication failed. Please check your credentials.",
	ErrCodeNetwork:    "Network timeout occurred. Please check your connection and try again.",
	ErrCodeNotFound:   "The requested file could not be found.",
	ErrCodeConfig:     "The application configuration is invalid. Consider resetting or reviewing the config.",
	ErrCodeStorage:    "Storage is full. Free up space and try again.",
	ErrCodePermission: "Permission denied. Ensure you have proper access rights.",
	ErrCodeDatabase:   "A database error occurred. Please try again later.",
	ErrCodeInternal:   "An internal error occurred. Please contact support.",
}

// recoverySuggestions maps error codes to suggested recovery actions.
var recoverySuggestions = map[ErrorCode]string{
	ErrCodeAuth:       "Try logging in again or resetting your password.",
	ErrCodeNetwork:    "Check your internet connection or try again later.",
	ErrCodeNotFound:   "Verify the file path or restore the missing file.",
	ErrCodeConfig:     "Restore a valid config or delete the corrupted one to regenerate defaults.",
	ErrCodeStorage:    "Clear disk space and retry the operation.",
	ErrCodePermission: "Run the application with appropriate permissions.",
	ErrCodeDatabase:   "Wait and retry, or contact support if the problem persists.",
	ErrCodeInternal:   "Contact support with error details for further assistance.",
}

// UserMessage returns a safe, user-friendly message for the given error.
// If the error is a SafeError, it uses the predefined mapping.
func UserMessage(err error) string {
	if se, ok := err.(*SafeError); ok {
		if msg, exists := userMessages[se.Code]; exists {
			return msg
		}
	}
	return "An unknown error occurred."
}

// RecoverySuggestion returns suggested recovery steps for a given error.
// Returns empty string if no suggestion is available.
func RecoverySuggestion(err error) string {
	if se, ok := err.(*SafeError); ok {
		if suggestion, exists := recoverySuggestions[se.Code]; exists {
			return suggestion
		}
	}
	return ""
}
