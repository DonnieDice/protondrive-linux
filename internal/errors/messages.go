package errors

// userMessages maps predefined error codes to friendly messages for end users.
var userMessages = map[ErrorCode]string{
	ErrAuthenticationFailed: "Authentication failed. Please check your credentials.",
	ErrNetworkTimeout:       "Network timeout occurred. Please check your connection and try again.",
	ErrFileNotFound:         "The requested file could not be found.",
	ErrInvalidConfig:        "The application configuration is invalid. Consider resetting or reviewing the config.",
	ErrStorageFull:          "Storage is full. Free up space and try again.",
	ErrPermissionDenied:     "Permission denied. Ensure you have proper access rights.",
	ErrDatabase:             "A database error occurred. Please try again later.",
	ErrInternal:             "An internal error occurred. Please contact support.",
}

// recoverySuggestions maps error codes to suggested recovery actions.
var recoverySuggestions = map[ErrorCode]string{
	ErrAuthenticationFailed: "Try logging in again or resetting your password.",
	ErrNetworkTimeout:       "Check your internet connection or try again later.",
	ErrFileNotFound:         "Verify the file path or restore the missing file.",
	ErrInvalidConfig:        "Restore a valid config or delete the corrupted one to regenerate defaults.",
	ErrStorageFull:          "Clear disk space and retry the operation.",
	ErrPermissionDenied:     "Run the application with appropriate permissions.",
	ErrDatabase:             "Wait and retry, or contact support if the problem persists.",
	ErrInternal:             "Contact support with error details for further assistance.",
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
