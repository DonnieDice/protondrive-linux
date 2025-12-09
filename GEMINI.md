# ProtonDrive Linux Client - Project Context (Go Stack)

**Version**: 8.0 - STRATEGIC PIVOT  
**Last Updated**: 2024-12-09  
**Phase**: Project Restart - Technology Stack Change  
**Previous Stack**: TypeScript/Electron → **New Stack**: Go/Fyne
**Project Health**: 10/10 (Better foundation chosen)

---

# doc links
@./AGENT.md

---

## 🔄 STRATEGIC PIVOT ANNOUNCEMENT

**This project is pivoting from TypeScript/Electron to Go/Fyne.**

**Why the Pivot?**

1. **Proven Foundation**: Proton-API-Bridge (Go) already solves ProtonDrive API integration
2. **Better Performance**: Native Go binary vs Electron overhead
3. **Easier Distribution**: Single binary vs complex Electron packaging
4. **Lower Resource Usage**: 10-20MB RAM vs 80-150MB for Electron
5. **Community Support**: Active Go ProtonDrive ecosystem
6. **Simpler Stack**: Go is easier to learn and maintain than TypeScript + Node.js + Electron

**What This Means:**
- Restart project with Go
- Leverage existing Proton-API-Bridge
- Build native Linux client with Fyne GUI
- Much faster path to working product

---

## WHAT THIS DOCUMENT IS

This is the complete project context for building ProtonDrive Linux client in **Go**.

**Purpose**: Guide development of a native Linux client for ProtonDrive using Go and leveraging the existing Proton-API-Bridge.

**This document contains:**
- Project overview and goals
- Architecture decisions (Go-specific)
- Why Go over TypeScript/Electron
- Development patterns and best practices
- Migration plan from Electron

**This document does NOT contain:**
- Learning roadmaps (see separate learning docs)
- Task lists (see TASKS.md)
- Operational rules (see AGENT.md)
- User documentation (see README.md)

---

## PROJECT OVERVIEW

### What We're Building

ProtonDrive Linux is an unofficial, open-source desktop client for ProtonDrive targeting Linux users exclusively. **Native Go application** providing seamless file synchronization with ProtonDrive's zero-knowledge encryption.

**Critical Design Goal**: Universal hardware compatibility - runs on ANY Linux device (Raspberry Pi to workstations) with minimal resource usage.

### Why Go Instead of Electron

**Decision**: Use Go with Fyne GUI instead of TypeScript/Electron.

**Reasoning**:

| Aspect | Electron (Old) | Go + Fyne (New) | Winner |
|--------|----------------|-----------------|---------|
| **Binary Size** | 60-80MB | 10-20MB | 🏆 Go |
| **RAM Usage** | 80-150MB | 20-40MB | 🏆 Go |
| **Startup Time** | 1-2 seconds | <500ms | 🏆 Go |
| **Distribution** | Complex packaging | Single binary | 🏆 Go |
| **Cross-compile** | Difficult | Easy | 🏆 Go |
| **Learning Curve** | Steep (TS+Node+Electron) | Easier | 🏆 Go |
| **ProtonDrive Integration** | Build from scratch | Use Proton-API-Bridge | 🏆 Go |
| **Community** | General Electron | ProtonDrive-specific | 🏆 Go |

**The Killer Advantage**: Proton-API-Bridge already exists in Go and handles:
- ProtonDrive authentication
- File encryption/decryption
- API communication
- Rate limiting
- Error handling

We can build on top of this instead of reimplementing everything.

---

## ARCHITECTURE (GO STACK)

### Overall Architecture

```
┌─────────────────────────────────────────┐
│         GUI (Fyne Framework)            │
│   - Cross-platform native widgets       │
│   - Lightweight (not web-based)         │
│   - No JavaScript runtime               │
└──────────────┬──────────────────────────┘
               │ Direct Go function calls
┌──────────────┴──────────────────────────┐
│         Application Logic (Go)          │
│   - File synchronization                │
│   - Conflict resolution                 │
│   - Local state management              │
│   - Performance profiling               │
└──────────────┬──────────────────────────┘
               │ Go API calls
┌──────────────┴──────────────────────────┐
│     Proton-API-Bridge (Go Library)      │
│   - ProtonDrive SDK integration         │
│   - Authentication & encryption         │
│   - API communication                   │
│   - Rate limiting                       │
└──────────────┬──────────────────────────┘
               │ HTTPS
┌──────────────┴──────────────────────────┐
│         ProtonDrive API                 │
└─────────────────────────────────────────┘
```

**Key Advantages vs Electron**:
- No IPC (Inter-Process Communication) needed
- No preload scripts or context isolation complexity
- Direct function calls between GUI and logic
- Single process, not multi-process like Electron
- Native performance throughout

---

## WHY GO IS PERFECT FOR THIS PROJECT

### 1. Built-in Concurrency

**Perfect for sync operations:**

```go
// Upload multiple files concurrently - built into language
func uploadFiles(files []string) {
    var wg sync.WaitGroup
    
    for _, file := range files {
        wg.Add(1)
        go func(f string) {
            defer wg.Done()
            uploadFile(f)
        }(file)
    }
    
    wg.Wait() // Wait for all uploads to complete
}
```

**Why This Matters**:
- File sync requires concurrent operations
- Go's goroutines are lightweight (2KB each)
- Can handle thousands of concurrent uploads/downloads
- Built into language, no external libraries needed

### 2. Single Binary Distribution

**Build once, run anywhere:**

```bash
# Build for current system
go build -o protondrive-linux

# Cross-compile for different architectures (ONE command)
GOOS=linux GOARCH=amd64 go build -o protondrive-linux-x64
GOOS=linux GOARCH=arm64 go build -o protondrive-linux-arm64
GOOS=linux GOARCH=arm go build -o protondrive-linux-armv7

# Result: Single 10-20MB binary
# No dependencies, no runtime needed
# Just copy and run
```

**Compare to Electron**:
- Electron: 60-80MB package + Node.js runtime + platform-specific installers
- Go: Single 10-20MB binary, works immediately

### 3. Resource Efficiency

**Memory footprint comparison:**

| Application | Idle RAM | Active RAM | Binary Size |
|-------------|----------|------------|-------------|
| Electron ProtonDrive | 80-100MB | 150-200MB | 60-80MB |
| **Go ProtonDrive** | **15-25MB** | **30-50MB** | **10-20MB** |

**Why this matters:**
- Runs on Raspberry Pi with 1GB RAM
- Multiple instances possible
- Battery efficient on laptops
- Fast startup (no V8 initialization)

### 4. Proton-API-Bridge Integration

**This is the game-changer:**

Instead of building from scratch:

```go
// Literally this simple with Proton-API-Bridge
import "github.com/henrybear327/Proton-API-Bridge/pkg/drive"

func main() {
    client := drive.NewClient()
    client.Login(username, password)
    
    files, _ := client.ListFiles("/")
    for _, file := range files {
        println(file.Name)
    }
}
```

vs TypeScript/Electron approach:
- Study ProtonDrive API docs
- Implement authentication (SRP protocol)
- Handle encryption/decryption
- Deal with API quirks
- Debug for weeks

Proton-API-Bridge: **Already done.**

### 5. Simplicity

**Go Philosophy**: "Less is more"

```go
// HTTP client in Go - standard library
package main

import (
    "net/http"
    "io"
    "os"
)

func main() {
    resp, _ := http.Get("https://example.com")
    defer resp.Body.Close()
    io.Copy(os.Stdout, resp.Body)
}
```

**No need for**:
- package.json
- webpack
- tsconfig.json
- node_modules (5000+ files)
- Complex build pipeline

**Just**: `go run main.go`

---

## UNIVERSAL HARDWARE COMPATIBILITY (GO APPROACH)

### Design Philosophy

**"If it runs Linux, it should run ProtonDrive Linux"**

Go makes this even easier than Electron:

### 1. Adaptive Resource Management

```go
// Detect system capabilities at startup
type SystemCapabilities struct {
    TotalRAM      uint64 // Bytes
    AvailableRAM  uint64 // Bytes
    CPUCores      int
    Architecture  string // amd64, arm64, arm
    StorageType   string // SSD, HDD, UNKNOWN
}

// Performance profiles
type PerformanceProfile interface {
    MaxConcurrentUploads() int
    MaxConcurrentDownloads() int
    CacheSizeMB() int
    ChunkSizeMB() int
}

type LowEndProfile struct{}
func (p LowEndProfile) MaxConcurrentUploads() int { return 1 }
func (p LowEndProfile) MaxConcurrentDownloads() int { return 2 }
func (p LowEndProfile) CacheSizeMB() int { return 50 }
func (p LowEndProfile) ChunkSizeMB() int { return 5 }

type StandardProfile struct{}
func (p StandardProfile) MaxConcurrentUploads() int { return 3 }
func (p StandardProfile) MaxConcurrentDownloads() int { return 5 }
func (p StandardProfile) CacheSizeMB() int { return 100 }
func (p StandardProfile) ChunkSizeMB() int { return 5 }

type HighEndProfile struct{}
func (p HighEndProfile) MaxConcurrentUploads() int { return 5 }
func (p HighEndProfile) MaxConcurrentDownloads() int { return 10 }
func (p HighEndProfile) CacheSizeMB() int { return 200 }
func (p HighEndProfile) ChunkSizeMB() int { return 10 }

func DetectProfile() PerformanceProfile {
    caps := detectSystemCapabilities()
    
    totalRAMMB := caps.TotalRAM / 1024 / 1024
    
    if totalRAMMB < 4096 {
        return LowEndProfile{}
    } else if totalRAMMB < 8192 {
        return StandardProfile{}
    }
    return HighEndProfile{}
}
```

### 2. Graceful Degradation

```go
// Adaptive concurrency
type SyncManager struct {
    profile PerformanceProfile
    uploadSem chan struct{} // Semaphore for uploads
}

func NewSyncManager(profile PerformanceProfile) *SyncManager {
    return &SyncManager{
        profile: profile,
        uploadSem: make(chan struct{}, profile.MaxConcurrentUploads()),
    }
}

func (sm *SyncManager) Upload(file string) error {
    sm.uploadSem <- struct{}{} // Acquire
    defer func() { <-sm.uploadSem }() // Release
    
    // Actual upload logic
    return uploadFile(file)
}
```

### 3. Storage Type Optimization

```go
func detectStorageType(path string) string {
    testFile := filepath.Join(path, ".storage-test")
    testData := make([]byte, 10*1024*1024) // 10MB
    
    start := time.Now()
    
    // Write test
    f, _ := os.Create(testFile)
    f.Write(testData)
    f.Sync() // Force flush to disk
    f.Close()
    
    duration := time.Since(start)
    os.Remove(testFile)
    
    // SSD: <100ms, HDD: >200ms for 10MB sync write
    if duration < 100*time.Millisecond {
        return "SSD"
    } else if duration > 150*time.Millisecond {
        return "HDD"
    }
    return "UNKNOWN"
}

// Adjust behavior
func optimizeForStorage(storageType string, db *sql.DB) {
    if storageType == "HDD" {
        // More aggressive batching for HDD
        db.Exec("PRAGMA synchronous = NORMAL")
        db.Exec("PRAGMA journal_mode = WAL")
        db.Exec("PRAGMA cache_size = -4000") // 4MB
    } else {
        db.Exec("PRAGMA synchronous = FULL")
        db.Exec("PRAGMA cache_size = -8000") // 8MB
    }
}
```

### 4. Multi-Architecture Support

```bash
# Build for all architectures
#!/bin/bash

# x86_64 (Intel/AMD)
GOOS=linux GOARCH=amd64 go build -o dist/protondrive-linux-x64

# ARM64 (Raspberry Pi 3+, modern ARM)
GOOS=linux GOARCH=arm64 go build -o dist/protondrive-linux-arm64

# ARMv7 (Raspberry Pi 2, older ARM)
GOOS=linux GOARCH=arm GOARM=7 go build -o dist/protondrive-linux-armv7

# ARMv6 (Raspberry Pi 1, very old ARM)
GOOS=linux GOARCH=arm GOARM=6 go build -o dist/protondrive-linux-armv6
```

**Result**: 4 binaries, each 10-20MB, ready to distribute.

---

## PROJECT STRUCTURE (GO)

```
protondrive-linux/
├── go.mod                    # Dependencies (like package.json)
├── go.sum                    # Dependency checksums
├── main.go                   # Entry point
├── cmd/                      # Command-line tools
│   └── protondrive/
│       └── main.go
├── internal/                 # Private application code
│   ├── sync/                # Sync engine
│   │   ├── manager.go
│   │   ├── uploader.go
│   │   └── downloader.go
│   ├── gui/                 # GUI components (Fyne)
│   │   ├── app.go
│   │   ├── login.go
│   │   └── filelist.go
│   ├── config/              # Configuration
│   │   ├── config.go
│   │   └── profiles.go
│   ├── client/              # ProtonDrive client wrapper
│   │   └── client.go
│   └── storage/             # Local database
│       ├── db.go
│       └── migrations.go
├── pkg/                     # Public libraries (if any)
├── scripts/                 # Build scripts
│   └── build-all.sh
├── docs/                    # Documentation
├── .agent_logs/             # AI agent logs
├── GEMINI.md               # This file
├── AGENT.md                # Operational rules
├── TASKS.md                # Task list
└── README.md               # User documentation
```

**Key Differences from Electron Structure**:
- No `src/main/`, `src/renderer/`, `src/preload/` split
- No `node_modules/` directory
- `internal/` for application code (private)
- `pkg/` for reusable libraries (public)
- `cmd/` for multiple binaries if needed

---

## DEVELOPMENT PATTERNS

### How to Implement a Service (Go Style)

```go
// internal/sync/manager.go
package sync

import (
    "context"
    "log"
    "sync"
)

// Manager handles file synchronization
type Manager struct {
    profile       PerformanceProfile
    client        *client.ProtonClient
    uploadQueue   chan string
    downloadQueue chan string
    wg            sync.WaitGroup
}

// NewManager creates a new sync manager
func NewManager(profile PerformanceProfile, client *client.ProtonClient) *Manager {
    return &Manager{
        profile:       profile,
        client:        client,
        uploadQueue:   make(chan string, 100),
        downloadQueue: make(chan string, 100),
    }
}

// Start begins sync operations
func (m *Manager) Start(ctx context.Context) error {
    log.Println("Starting sync manager")
    
    // Start upload workers
    for i := 0; i < m.profile.MaxConcurrentUploads(); i++ {
        m.wg.Add(1)
        go m.uploadWorker(ctx)
    }
    
    // Start download workers
    for i := 0; i < m.profile.MaxConcurrentDownloads(); i++ {
        m.wg.Add(1)
        go m.downloadWorker(ctx)
    }
    
    log.Println("Sync manager started")
    return nil
}

// Stop gracefully stops sync operations
func (m *Manager) Stop() {
    log.Println("Stopping sync manager")
    close(m.uploadQueue)
    close(m.downloadQueue)
    m.wg.Wait()
    log.Println("Sync manager stopped")
}

// QueueUpload adds file to upload queue
func (m *Manager) QueueUpload(filepath string) {
    m.uploadQueue <- filepath
}

// uploadWorker processes upload queue
func (m *Manager) uploadWorker(ctx context.Context) {
    defer m.wg.Done()
    
    for {
        select {
        case filepath, ok := <-m.uploadQueue:
            if !ok {
                return // Channel closed
            }
            
            log.Printf("Uploading: %s", filepath)
            if err := m.client.Upload(filepath); err != nil {
                log.Printf("Upload failed: %v", err)
            }
            
        case <-ctx.Done():
            return
        }
    }
}

// downloadWorker processes download queue
func (m *Manager) downloadWorker(ctx context.Context) {
    defer m.wg.Done()
    
    for {
        select {
        case filepath, ok := <-m.downloadQueue:
            if !ok {
                return // Channel closed
            }
            
            log.Printf("Downloading: %s", filepath)
            if err := m.client.Download(filepath); err != nil {
                log.Printf("Download failed: %v", err)
            }
            
        case <-ctx.Done():
            return
        }
    }
}
```

### How to Write Tests (Go Style)

```go
// internal/sync/manager_test.go
package sync

import (
    "context"
    "testing"
    "time"
)

// Mock client
type mockProtonClient struct {
    uploadCalled   int
    downloadCalled int
}

func (m *mockProtonClient) Upload(filepath string) error {
    m.uploadCalled++
    return nil
}

func (m *mockProtonClient) Download(filepath string) error {
    m.downloadCalled++
    return nil
}

func TestManagerStart(t *testing.T) {
    profile := StandardProfile{}
    mockClient := &mockProtonClient{}
    
    manager := NewManager(profile, mockClient)
    
    ctx, cancel := context.WithCancel(context.Background())
    defer cancel()
    
    if err := manager.Start(ctx); err != nil {
        t.Fatalf("Start failed: %v", err)
    }
    
    // Queue some uploads
    manager.QueueUpload("file1.txt")
    manager.QueueUpload("file2.txt")
    
    // Wait a bit for processing
    time.Sleep(100 * time.Millisecond)
    
    manager.Stop()
    
    if mockClient.uploadCalled != 2 {
        t.Errorf("Expected 2 uploads, got %d", mockClient.uploadCalled)
    }
}

func TestManagerConcurrency(t *testing.T) {
    profile := HighEndProfile{}
    mockClient := &mockProtonClient{}
    
    manager := NewManager(profile, mockClient)
    
    ctx, cancel := context.WithCancel(context.Background())
    defer cancel()
    
    manager.Start(ctx)
    
    // Queue many files
    for i := 0; i < 50; i++ {
        manager.QueueUpload("file.txt")
    }
    
    time.Sleep(500 * time.Millisecond)
    manager.Stop()
    
    if mockClient.uploadCalled != 50 {
        t.Errorf("Expected 50 uploads, got %d", mockClient.uploadCalled)
    }
}
```

**Run tests:**
```bash
go test ./...                    # All tests
go test -v ./internal/sync       # Verbose, specific package
go test -cover ./...             # With coverage
go test -race ./...              # Race detection
```

### Error Handling (Go Style)

```go
// internal/errors/errors.go
package errors

import "errors"

var (
    ErrAuthenticationFailed = errors.New("authentication failed")
    ErrNetworkTimeout      = errors.New("network timeout")
    ErrFileNotFound        = errors.New("file not found")
    ErrInvalidConfig       = errors.New("invalid configuration")
)

// Wrap errors with context
func WrapAuthentication(err error) error {
    return fmt.Errorf("authentication: %w", err)
}

func WrapNetwork(err error) error {
    return fmt.Errorf("network: %w", err)
}
```

**Usage:**
```go
func (c *ProtonClient) Login(username, password string) error {
    if err := c.api.Authenticate(username, password); err != nil {
        return errors.WrapAuthentication(err)
    }
    return nil
}

// In caller
if err := client.Login(username, password); err != nil {
    if errors.Is(err, errors.ErrAuthenticationFailed) {
        // Handle auth error specifically
    }
    return err
}
```

---

## MIGRATION PLAN FROM ELECTRON PROJECT

### What to Keep

From the existing TypeScript/Electron project:

✅ **Keep these concepts**:
- Overall architecture decisions (security, privacy)
- Universal hardware compatibility philosophy
- Performance profiling concepts
- Documentation structure
- Testing philosophy (80% coverage)
- Git workflow

✅ **Keep these files**:
- `README.md` (update tech stack section)
- `LICENSE`
- `SECURITY.md`
- `CODE_OF_CONDUCT.md`
- `.gitignore` (update for Go)
- `docs/` directory content
- `AGENT.md` (update commands)
- This file (GEMINI.md - already updated)

### What to Remove

❌ **Delete Electron-specific files**:
```bash
rm -rf node_modules/
rm package.json package-lock.json
rm tsconfig.json
rm webpack.config.js
rm forge.config.js
rm -rf src/
rm .eslintrc.json
rm .prettierrc
rm jest.config.js
```

### What to Create

✅ **Create Go-specific files**:
```bash
# Initialize Go module
go mod init github.com/yourusername/protondrive-linux

# Create project structure
mkdir -p cmd/protondrive
mkdir -p internal/{sync,gui,config,client,storage}
mkdir -p pkg
mkdir -p scripts

# Create main.go
touch main.go
touch cmd/protondrive/main.go

# Add dependencies
go get github.com/henrybear327/Proton-API-Bridge
go get fyne.io/fyne/v2
go get github.com/mattn/go-sqlite3
```

### Migration Steps

```bash
# 1. Backup existing project
git checkout -b electron-backup
git commit -am "Backup Electron version before Go pivot"
git push origin electron-backup

# 2. Create Go branch
git checkout main
git checkout -b go-pivot

# 3. Clean Electron files
rm -rf node_modules src package*.json tsconfig.json webpack.config.js forge.config.js

# 4. Initialize Go
go mod init github.com/yourusername/protondrive-linux

# 5. Create structure
mkdir -p cmd/protondrive internal/{sync,gui,config,client,storage} pkg scripts

# 6. Add dependencies
go get github.com/henrybear327/Proton-API-Bridge
go get fyne.io/fyne/v2
go get github.com/mattn/go-sqlite3

# 7. Update .gitignore
cat >> .gitignore << 'EOF'

# Go
*.exe
*.exe~
*.dll
*.so
*.dylib
*.test
*.out
go.work
dist/
vendor/
EOF

# 8. Create initial main.go
cat > main.go << 'EOF'
package main

import "fmt"

func main() {
    fmt.Println("ProtonDrive Linux - Go Edition")
}
EOF

# 9. Test build
go build -o protondrive-linux

# 10. Commit
git add .
git commit -m "feat: pivot to Go/Fyne stack"
git push origin go-pivot
```

### Updated TASKS.md Structure

The existing TASKS.md needs to be rewritten for Go development. New phase structure:

**Phase 1: Go Project Setup** (1-2 days)
- Initialize Go module
- Set up project structure
- Integrate Proton-API-Bridge
- Create basic CLI
- Basic authentication

**Phase 2: GUI Foundation** (2-3 days)
- Fyne setup
- Login form
- File list view
- Basic navigation

**Phase 3: Sync Engine** (1-2 weeks)
- File watcher
- Upload/download queue
- Conflict resolution
- Performance profiling integration

**Phase 4: Polish & Distribution** (1 week)
- Testing
- Multi-architecture builds
- Documentation
- Release

---

## PERFORMANCE BUDGETS (GO)

### Startup Time
- **Cold start**: < 500ms (was 2s for Electron)
- **Warm start**: < 200ms (was 1s for Electron)

### Memory Usage
- **Low-end profile**: < 30MB (was 100MB)
- **Standard profile**: < 50MB (was 150MB)
- **High-end profile**: < 80MB (was 200MB)

### Binary Size
- **Single binary**: < 20MB (was 60-80MB)
- **No unpacking needed** (Electron required 200MB unpacked)

### UI Performance
- **FPS**: 60 on all hardware (native rendering)
- **First paint**: < 100ms (was 500ms)
- **Time to interactive**: < 500ms (was 1.5s)

---

## KEY PRINCIPLES (UPDATED FOR GO)

1. **Universal Compatibility**: Must run on any Linux device
2. **Adaptive Performance**: Adjust to available hardware
3. **Leverage Existing Work**: Build on Proton-API-Bridge
4. **Native Performance**: No V8/Chromium overhead
5. **Simple Distribution**: Single binary
6. **Test Coverage**: 80% minimum on all code
7. **Documentation**: GoDoc on all public APIs
8. **Graceful Degradation**: Never fail hard, reduce features instead

---

## SUCCESS METRICS

**Go version is successful when**:
- ✅ Binary < 20MB
- ✅ RAM usage < 50MB under normal operation
- ✅ Startup < 500ms
- ✅ Successfully authenticates with ProtonDrive
- ✅ Can list, upload, download files
- ✅ Runs on Raspberry Pi with 1GB RAM
- ✅ Single binary distribution works
- ✅ 80% test coverage maintained

---

**For Task Management**: See TASKS.md (will be updated for Go)  
**For Operational Rules**: See AGENT.md (update commands for Go)  
**For User Documentation**: See README.md (update tech stack)