package errors

import "errors"

var (
	ErrAuthenticationFailed = errors.New("authentication failed")
	ErrNetworkTimeout      = errors.New("network timeout")
	ErrFileNotFound        = errors.New("file not found")
	ErrInvalidConfig       = errors.New("invalid configuration")
	ErrStorageFull         = errors.New("storage full")
	ErrPermissionDenied    = errors.New("permission denied")
)
