package encryption

import (
	"runtime"
)

// WipeSlice securely wipes a byte slice from memory by overwriting it with zeros.
// This helps prevent sensitive data from lingering in memory.
func WipeSlice(s []byte) {
	for i := range s {
		s[i] = 0
	}
}

// ClearMemory takes a byte slice and wipes its content from memory using WipeSlice,
// then explicitly calls the garbage collector to free the memory.
// It's intended to be used with a defer statement after sensitive data is no longer needed.
// Example:
//
//	sensitiveData := decryptFile(...)
//	defer ClearMemory(sensitiveData)
//	// Use sensitiveData...
func ClearMemory(s []byte) {
	if s == nil {
		return
	}
	WipeSlice(s)
	runtime.GC() // Force garbage collection
}