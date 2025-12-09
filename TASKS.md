# ProtonDrive Linux - Task List (Go Edition)

**Last Updated**: 2024-12-09  
**Project Phase**: Pre-Development (Planning Complete)  
**Technology Stack**: Go + Fyne  
**Estimated Timeline**: 4-6 weeks to MVP

---

## PHASES OVERVIEW

- **Phase 0**: Migration & Setup (1-2 days) ⬅️ **START HERE**
- **Phase 1**: Project Foundation (2-3 days)
- **Phase 2**: Core Integration (3-5 days)
- **Phase 3**: GUI Development (5-7 days)
- **Phase 4**: Sync Engine (7-10 days)
- **Phase 5**: Testing & Optimization (5-7 days)
- **Phase 6**: Distribution (3-5 days)
- **Phase 7**: Documentation & Release (2-3 days)

**Total Estimated Time**: 27-37 days (4-6 weeks)

---

## LEGEND

- [ ] Not Started
- [⏳] In Progress
- [✅] Complete
- [🔄] Needs Revision
- [❌] Blocked
- [📝] Documentation Task
- [🧪] Testing Task
- [🏗️] Infrastructure Task
- [🔍] Research Task

---

## PHASE 0: MIGRATION & SETUP (1-2 DAYS)

**Goal**: Migrate from Electron to Go project structure.

### 0.1 Backup & Branch Management


### 0.2 Clean Electron Files


- [✅] 🏗️ Keep documentation files
  - Keep: README.md, LICENSE, SECURITY.md, CODE_OF_CONDUCT.md
  - Keep: docs/ directory
  - Keep: GEMINI.md (updated)

### 0.3 Initialize Go Project

- [ ] 🏗️ Initialize Go module
  ```bash
  go mod init github.com/yourusername/protondrive-linux
  ```
- [✅] 🏗️ Create project structure
  ```bash
  mkdir -p cmd/protondrive
  mkdir -p internal/{sync,gui,config,client,storage}
  mkdir -p pkg
  mkdir -p scripts
  mkdir -p .agent_logs
  ```
- [✅] 🏗️ Create initial files
  ```bash
  touch main.go
  touch cmd/protondrive/main.go
  touch internal/config/profiles.go
  ```

### 0.4 Update Configuration Files

- [✅] 📝 Update .gitignore for Go
  ```gitignore
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
  
  # IDE
  .vscode/
  .idea/
  *.swp
  *.swo
  
  # OS
  .DS_Store
  Thumbs.db
  ```

### 0.5 Initial Commit

- [ ] 🏗️ Commit migration
  ```bash
  git add .
  git commit -m "feat: pivot to Go/Fyne stack
  
  - Remove Electron/TypeScript files
  - Initialize Go module
  - Create Go project structure
  - Update documentation
  
  BREAKING CHANGE: Complete technology stack pivot"
  ```
- [ ] 🏗️ Push to remote
  ```bash
  git push origin go-pivot
  ```

---

## PHASE 1: PROJECT FOUNDATION (2-3 DAYS)

**Goal**: Set up basic Go project with dependencies and core types.

### 1.1 Dependencies

- [ ] 🏗️ Add Proton-API-Bridge
  ```bash
  go get github.com/henrybear327/Proton-API-Bridge
  ```
  - [ ] Test import and basic usage
  - [ ] Document API structure
  - [ ] Create wrapper interface

- [ ] 🏗️ Add Fyne GUI framework
  ```bash
  go get fyne.io/fyne/v2
  ```
  - [ ] Test basic window creation
  - [ ] Verify development libraries installed
  - [ ] Document setup requirements

- [ ] 🏗️ Add SQLite database
  ```bash
  go get github.com/mattn/go-sqlite3
  ```
  - [ ] Test CGO compilation
  - [ ] Create database schema
  - [ ] Implement migrations

- [ ] 🏗️ Add logging library (optional)
  ```bash
  go get golang.org/x/exp/slog  # Or use stdlib log
  ```

- [ ] 🏗️ Add testing utilities
  ```bash
  go get github.com/stretchr/testify
  ```

### 1.2 Core Configuration Types

- [ ] 📝 Define `internal/config/profiles.go`
  ```go
  type PerformanceProfile interface {
      MaxConcurrentUploads() int
      MaxConcurrentDownloads() int
      CacheSizeMB() int
      ChunkSizeMB() int
  }
  
  type LowEndProfile struct{}
  type StandardProfile struct{}
  type HighEndProfile struct{}
  ```
  - [ ] Implement all three profiles
  - [ ] Add profile detection logic
  - [ ] Write tests for each profile
  - [ ] Document profile selection algorithm

- [ ] 📝 Define `internal/config/config.go`
  ```go
  type Config struct {
      SyncDir          string
      Profile          PerformanceProfile
      LogLevel         string
      ProtonUsername   string
      // Don't store password in config!
  }
  ```
  - [ ] Implement config loading from file
  - [ ] Implement config saving
  - [ ] Add validation
  - [ ] Write tests

### 1.3 System Capabilities Detection

- [ ] 🔍 Implement `internal/config/capabilities.go`
  ```go
  type SystemCapabilities struct {
      TotalRAM     uint64
      AvailableRAM uint64
      CPUCores     int
      Architecture string
      StorageType  string
  }
  
  func DetectCapabilities() SystemCapabilities
  ```
  - [ ] RAM detection (read /proc/meminfo)
  - [ ] CPU detection (runtime.NumCPU())
  - [ ] Architecture detection (runtime.GOARCH)
  - [ ] Storage type detection (benchmark write)
  - [ ] Write comprehensive tests
  - [ ] Test on multiple systems

### 1.4 Error Types

- [ ] 📝 Define `internal/errors/errors.go`
  ```go
  var (
      ErrAuthenticationFailed = errors.New("authentication failed")
      ErrNetworkTimeout      = errors.New("network timeout")
      ErrFileNotFound        = errors.New("file not found")
      ErrInvalidConfig       = errors.New("invalid configuration")
      ErrStorageFull         = errors.New("storage full")
      ErrPermissionDenied    = errors.New("permission denied")
  )
  ```
  - [ ] Add error wrapping functions
  - [ ] Document error handling patterns
  - [ ] Create error recovery strategies

### 1.5 Basic CLI

- [ ] 📝 Create `main.go`
  ```go
  package main
  
  import (
      "fmt"
      "github.com/yourusername/protondrive-linux/internal/config"
  )
  
  func main() {
      fmt.Println("ProtonDrive Linux - Go Edition")
      
      caps := config.DetectCapabilities()
      profile := config.DetectProfile(caps)
      
      fmt.Printf("Detected profile: %T\n", profile)
      fmt.Printf("RAM: %d MB\n", caps.TotalRAM/1024/1024)
      fmt.Printf("CPU Cores: %d\n", caps.CPUCores)
  }
  ```
  - [ ] Test build on development machine
  - [ ] Test on low-end hardware (if available)

### 1.6 Testing Infrastructure

- [ ] 🧪 Set up test structure
  ```bash
  # Each package should have _test.go files
  touch internal/config/profiles_test.go
  touch internal/config/config_test.go
  touch internal/config/capabilities_test.go
  ```

- [ ] 🧪 Create test helpers
  ```go
  // internal/testutil/testutil.go
  package testutil
  
  func CreateTempConfig() *config.Config { ... }
  func CreateMockClient() *client.ProtonClient { ... }
  ```

- [ ] 🧪 Set up CI/CD (optional for MVP)
  - [ ] Create .github/workflows/test.yml
  - [ ] Test on multiple Go versions
  - [ ] Test on multiple architectures

### 1.7 Documentation

- [ ] 📝 Update README.md
  - [ ] Replace Electron setup with Go setup
  - [ ] Add build instructions
  - [ ] Document dependencies
  - [ ] Add quick start guide

- [ ] 📝 Create internal/doc.go
  ```go
  // Package protondrive provides a native Linux client for ProtonDrive.
  //
  // This implementation uses the Go programming language and Fyne GUI
  // framework to provide a lightweight, efficient alternative to the
  // official ProtonDrive clients.
  ```

---

## PHASE 2: CORE INTEGRATION (3-5 DAYS)

**Goal**: Integrate Proton-API-Bridge and implement authentication.

### 2.1 Proton Client Wrapper

- [ ] 🔍 Research Proton-API-Bridge
  - [ ] Study repository documentation
  - [ ] Examine example code
  - [ ] Understand authentication flow
  - [ ] Document API endpoints used

- [ ] 📝 Create `internal/client/client.go`
  ```go
  package client
  
  import (
      "github.com/henrybear327/Proton-API-Bridge/pkg/drive"
  )
  
  type ProtonClient struct {
      bridge    *drive.Client
      username  string
      session   *drive.Session
  }
  
  func NewProtonClient() *ProtonClient
  func (c *ProtonClient) Login(username, password string) error
  func (c *ProtonClient) Logout() error
  func (c *ProtonClient) IsAuthenticated() bool
  ```
  - [ ] Implement client initialization
  - [ ] Implement authentication
  - [ ] Handle session management
  - [ ] Add error handling

- [ ] 🧪 Write tests for client
  - [ ] Test login with valid credentials
  - [ ] Test login with invalid credentials
  - [ ] Test session persistence
  - [ ] Test logout

### 2.2 Authentication & Session Management

- [ ] 📝 Implement secure credential storage
  ```go
  // internal/client/keyring.go
  func SaveCredentials(username, password string) error
  func LoadCredentials() (string, string, error)
  func ClearCredentials() error
  ```
  - [ ] Use Linux keyring (libsecret/gnome-keyring)
  - [ ] Fallback to encrypted file if keyring unavailable
  - [ ] Never log or print credentials

- [ ] 📝 Implement session token management
  ```go
  // internal/client/session.go
  func SaveSession(session *drive.Session) error
  func LoadSession() (*drive.Session, error)
  func RefreshSession() error
  ```
  - [ ] Save session tokens securely
  - [ ] Auto-refresh expired tokens
  - [ ] Handle refresh failures gracefully

- [ ] 🧪 Security testing
  - [ ] Verify credentials never logged
  - [ ] Test session refresh
  - [ ] Test session expiration handling

### 2.3 File Operations

- [ ] 📝 Implement basic file operations
  ```go
  // internal/client/files.go
  func (c *ProtonClient) ListFiles(path string) ([]File, error)
  func (c *ProtonClient) CreateFolder(path string) error
  func (c *ProtonClient) UploadFile(localPath, remotePath string) error
  func (c *ProtonClient) DownloadFile(remotePath, localPath string) error
  func (c *ProtonClient) DeleteFile(path string) error
  func (c *ProtonClient) MoveFile(oldPath, newPath string) error
  ```
  - [ ] Implement each operation
  - [ ] Add progress reporting
  - [ ] Handle large files (chunking)
  - [ ] Add rate limiting

- [ ] 🧪 Write tests for file operations
  - [ ] Test file listing
  - [ ] Test upload (small file)
  - [ ] Test upload (large file)
  - [ ] Test download
  - [ ] Test folder creation
  - [ ] Test delete/move

### 2.4 Metadata & State

- [ ] 📝 Define file metadata structure
  ```go
  type FileMetadata struct {
      ID           string
      Name         string
      Size         int64
      ModTime      time.Time
      IsDir        bool
      Hash         string
      RemotePath   string
      LocalPath    string
      SyncStatus   SyncStatus
  }
  
  type SyncStatus int
  const (
      SyncPending SyncStatus = iota
      SyncInProgress
      SyncComplete
      SyncFailed
  )
  ```

- [ ] 📝 Implement `internal/storage/db.go`
  ```go
  type Database struct {
      db *sql.DB
  }
  
  func NewDatabase(path string) (*Database, error)
  func (db *Database) SaveFile(metadata FileMetadata) error
  func (db *Database) GetFile(id string) (FileMetadata, error)
  func (db *Database) ListFiles() ([]FileMetadata, error)
  func (db *Database) DeleteFile(id string) error
  ```
  - [ ] Create database schema
  - [ ] Implement CRUD operations
  - [ ] Add indexes for performance
  - [ ] Implement migrations

- [ ] 🧪 Database tests
  - [ ] Test file save/retrieve
  - [ ] Test query performance
  - [ ] Test migration system

### 2.5 Network & Error Handling

- [ ] 📝 Implement retry logic
  ```go
  // internal/client/retry.go
  func WithRetry(fn func() error, maxAttempts int) error
  ```
  - [ ] Exponential backoff
  - [ ] Maximum retry limits
  - [ ] Network error detection

- [ ] 📝 Implement rate limiting
  ```go
  // internal/client/ratelimit.go
  type RateLimiter struct {
      requestsPerSecond int
      burst             int
  }
  ```
  - [ ] Respect ProtonDrive API limits
  - [ ] Implement token bucket algorithm

- [ ] 🧪 Test error scenarios
  - [ ] Network timeout
  - [ ] API rate limit
  - [ ] Invalid auth
  - [ ] Server error (5xx)

---

## PHASE 3: GUI DEVELOPMENT (5-7 DAYS)

**Goal**: Build Fyne-based GUI for user interaction.

### 3.1 Application Window

- [ ] 📝 Create `internal/gui/app.go`
  ```go
  package gui
  
  import "fyne.io/fyne/v2/app"
  
  type App struct {
      fyneApp fyne.App
      window  fyne.Window
      client  *client.ProtonClient
      config  *config.Config
  }
  
  func NewApp(client *client.ProtonClient, config *config.Config) *App
  func (a *App) Run()
  func (a *App) ShowLogin()
  func (a *App) ShowMainView()
  ```
  - [ ] Initialize Fyne application
  - [ ] Create main window
  - [ ] Set window size and position
  - [ ] Add window icon

### 3.2 Login Screen

- [ ] 📝 Create `internal/gui/login.go`
  ```go
  func (a *App) createLoginView() fyne.CanvasObject {
      usernameEntry := widget.NewEntry()
      passwordEntry := widget.NewPasswordEntry()
      loginButton := widget.NewButton("Login", a.handleLogin)
      
      return container.NewVBox(
          widget.NewLabel("ProtonDrive Login"),
          usernameEntry,
          passwordEntry,
          loginButton,
      )
  }
  
  func (a *App) handleLogin() {
      // Authenticate and switch to main view
  }
  ```
  - [ ] Username field
  - [ ] Password field (masked)
  - [ ] Login button
  - [ ] "Remember me" checkbox
  - [ ] Error message display
  - [ ] Loading indicator during auth

- [ ] 🧪 Test login UI
  - [ ] Test valid credentials
  - [ ] Test invalid credentials
  - [ ] Test network errors
  - [ ] Test UI responsiveness

### 3.3 Main View (File List)

- [ ] 📝 Create `internal/gui/filelist.go`
  ```go
  type FileListView struct {
      tree    *widget.Tree
      toolbar *widget.Toolbar
  }
  
  func (a *App) createFileListView() fyne.CanvasObject {
      // Create tree widget
      // Add toolbar with actions
      // Handle file selection
  }
  ```
  - [ ] Tree view for folders
  - [ ] File list with icons
  - [ ] Sort by name/size/date
  - [ ] Context menu (right-click)
  - [ ] Multi-select support
  - [ ] Drag & drop (future)

### 3.4 Toolbar & Actions

- [ ] 📝 Create toolbar
  ```go
  toolbar := widget.NewToolbar(
      widget.NewToolbarAction(theme.FolderNewIcon(), createFolder),
      widget.NewToolbarAction(theme.UploadIcon(), uploadFiles),
      widget.NewToolbarAction(theme.DownloadIcon(), downloadFiles),
      widget.NewToolbarSeparator(),
      widget.NewToolbarAction(theme.DeleteIcon(), deleteFiles),
      widget.NewToolbarSpacer(),
      widget.NewToolbarAction(theme.SettingsIcon(), openSettings),
  )
  ```
  - [ ] Upload button
  - [ ] Download button
  - [ ] New folder button
  - [ ] Delete button
  - [ ] Settings button
  - [ ] Refresh button

### 3.5 File Operations Dialogs

- [ ] 📝 Upload dialog
  ```go
  func (a *App) showUploadDialog() {
      dialog.ShowFileOpen(func(reader fyne.URIReadCloser, err error) {
          if err != nil {
              dialog.ShowError(err, a.window)
              return
          }
          // Upload file
      }, a.window)
  }
  ```
  - [ ] File picker integration
  - [ ] Multiple file selection
  - [ ] Progress bar
  - [ ] Cancel button

- [ ] 📝 Download dialog
  ```go
  func (a *App) showDownloadDialog(file FileMetadata) {
      dialog.ShowFileSave(func(writer fyne.URIWriteCloser, err error) {
          // Download file
      }, a.window)
  }
  ```
  - [ ] Save location picker
  - [ ] Progress bar
  - [ ] Cancel button

- [ ] 📝 Delete confirmation
  ```go
  func (a *App) confirmDelete(files []FileMetadata) {
      dialog.ShowConfirm("Delete Files",
          fmt.Sprintf("Delete %d file(s)?", len(files)),
          func(confirmed bool) {
              if confirmed {
                  // Delete files
              }
          }, a.window)
  }
  ```

### 3.6 Settings Dialog

- [ ] 📝 Create `internal/gui/settings.go`
  ```go
  func (a *App) showSettings() {
      syncDirEntry := widget.NewEntry()
      profileSelect := widget.NewSelect(
          []string{"Low-End", "Standard", "High-End"},
          nil,
      )
      
      dialog.ShowCustomConfirm("Settings",
          "Save", "Cancel",
          container.NewVBox(
              widget.NewLabel("Sync Directory:"),
              syncDirEntry,
              widget.NewLabel("Performance Profile:"),
              profileSelect,
          ),
          a.handleSettingsSave,
          a.window,
      )
  }
  ```
  - [ ] Sync directory chooser
  - [ ] Performance profile selector
  - [ ] Auto-start option
  - [ ] Log level selector
  - [ ] About section

### 3.7 Status Bar & Notifications

- [ ] 📝 Create status bar
  ```go
  statusBar := container.NewHBox(
      widget.NewLabel("Connected"),
      layout.NewSpacer(),
      widget.NewProgressBarInfinite(),
      widget.NewLabel("Syncing..."),
  )
  ```
  - [ ] Connection status
  - [ ] Sync status
  - [ ] Storage usage
  - [ ] Upload/download speed

- [ ] 📝 System notifications
  ```go
  func (a *App) sendNotification(title, message string) {
      fyne.CurrentApp().SendNotification(&fyne.Notification{
          Title:   title,
          Content: message,
      })
  }
  ```
  - [ ] Upload complete
  - [ ] Download complete
  - [ ] Sync errors
  - [ ] Connection issues

### 3.8 Themes & Styling

- [ ] 📝 Apply custom theme (optional)
  ```go
  customTheme := &myTheme{}
  app.Settings().SetTheme(customTheme)
  ```
  - [ ] Dark/light mode toggle
  - [ ] Custom colors
  - [ ] Custom fonts
  - [ ] Icon set

---

## PHASE 4: SYNC ENGINE (7-10 DAYS)

**Goal**: Implement bidirectional file synchronization.

### 4.1 File Watcher

- [ ] 📝 Create `internal/sync/watcher.go`
  ```go
  package sync
  
  import "github.com/fsnotify/fsnotify"
  
  type Watcher struct {
      watcher *fsnotify.Watcher
      events  chan FileEvent
  }
  
  type FileEvent struct {
      Path   string
      Op     FileOp
      IsDir  bool
  }
  
  type FileOp int
  const (
      OpCreate FileOp = iota
      OpModify
      OpDelete
      OpRename
  )
  
  func NewWatcher(path string) (*Watcher, error)
  func (w *Watcher) Start() error
  func (w *Watcher) Stop()
  func (w *Watcher) Events() <-chan FileEvent
  ```
  - [ ] Monitor sync directory
  - [ ] Detect file changes
  - [ ] Handle renames
  - [ ] Ignore temporary files
  - [ ] Debounce rapid changes

- [ ] 🧪 Test file watcher
  - [ ] Test file create
  - [ ] Test file modify
  - [ ] Test file delete
  - [ ] Test folder operations
  - [ ] Test performance (many files)

### 4.2 Sync Manager

- [ ] 📝 Create `internal/sync/manager.go`
  ```go
  type Manager struct {
      client        *client.ProtonClient
      db            *storage.Database
      watcher       *Watcher
      profile       config.PerformanceProfile
      uploadQueue   chan string
      downloadQueue chan string
      wg            sync.WaitGroup
      ctx           context.Context
      cancel        context.CancelFunc
  }
  
  func NewManager(...) *Manager
  func (m *Manager) Start() error
  func (m *Manager) Stop()
  func (m *Manager) QueueUpload(filepath string)
  func (m *Manager) QueueDownload(filepath string)
  ```
  - [ ] Initialize worker pools
  - [ ] Handle file events
  - [ ] Queue management
  - [ ] Graceful shutdown

- [ ] 📝 Implement upload workers
  ```go
  func (m *Manager) uploadWorker(ctx context.Context) {
      for {
          select {
          case filepath := <-m.uploadQueue:
              m.uploadFile(filepath)
          case <-ctx.Done():
              return
          }
      }
  }
  
  func (m *Manager) uploadFile(filepath string) error {
      // Read file
      // Compute hash
      // Check if changed
      // Upload to ProtonDrive
      // Update database
  }
  ```
  - [ ] Implement upload logic
  - [ ] Handle chunked uploads
  - [ ] Progress reporting
  - [ ] Error handling
  - [ ] Retry logic

- [ ] 📝 Implement download workers
  ```go
  func (m *Manager) downloadWorker(ctx context.Context) {
      // Similar to uploadWorker
  }
  
  func (m *Manager) downloadFile(remotePath string) error {
      // Download from ProtonDrive
      // Verify hash
      // Write to disk
      // Update database
  }
  ```

### 4.3 Conflict Resolution

- [ ] 📝 Create `internal/sync/conflict.go`
  ```go
  type ConflictResolution int
  const (
      ResolveLocal ConflictResolution = iota
      ResolveRemote
      ResolveKeepBoth
      ResolveManual
  )
  
  type Conflict struct {
      LocalFile  FileMetadata
      RemoteFile FileMetadata
      Resolution ConflictResolution
  }
  
  func DetectConflict(local, remote FileMetadata) bool
  func ResolveConflict(conflict Conflict) error
  ```
  - [ ] Detect conflicts (both sides modified)
  - [ ] Implement resolution strategies
  - [ ] Notify user of conflicts
  - [ ] Create conflict copies

- [ ] 🧪 Test conflict scenarios
  - [ ] Both sides modify same file
  - [ ] One side deletes, other modifies
  - [ ] Both sides create same name
  - [ ] Test all resolution strategies

### 4.4 Change Detection & Hashing

- [ ] 📝 Create `internal/sync/hash.go`
  ```go
  func ComputeFileHash(filepath string) (string, error) {
      // Use SHA-256
      f, _ := os.Open(filepath)
      defer f.Close()
      
      h := sha256.New()
      io.Copy(h, f)
      return hex.EncodeToString(h.Sum(nil)), nil
  }
  
  func HasFileChanged(filepath string, lastHash string) bool {
      currentHash, _ := ComputeFileHash(filepath)
      return currentHash != lastHash
  }
  ```
  - [ ] Use SHA-256 for hashing
  - [ ] Cache hashes in database
  - [ ] Optimize for large files

- [ ] 🧪 Test hashing
  - [ ] Test small files
  - [ ] Test large files (GB+)
  - [ ] Test performance

### 4.5 Sync States & Recovery

- [ ] 📝 Implement sync state machine
  ```go
  type SyncState int
  const (
      StateIdle SyncState = iota
      StateScanning
      StateSyncing
      StatePaused
      StateError
  )
  
  func (m *Manager) SetState(state SyncState)
  func (m *Manager) GetState() SyncState
  ```

- [ ] 📝 Implement recovery mechanisms
  ```go
  func (m *Manager) RecoverFromCrash() error {
      // Load incomplete uploads
      // Resume or restart them
  }
  
  func (m *Manager) PauseSync()
  func (m *Manager) ResumeSync()
  ```

### 4.6 Performance Profiling Integration

- [ ] 📝 Add profiling hooks
  ```go
  func (m *Manager) GetStats() SyncStats {
      return SyncStats{
          FilesUploaded:   m.filesUploaded,
          FilesDownloaded: m.filesDownloaded,
          BytesUploaded:   m.bytesUploaded,
          BytesDownloaded: m.bytesDownloaded,
          Errors:          m.errors,
          CurrentRAM:      m.getCurrentRAM(),
      }
  }
  ```
  - [ ] Track memory usage
  - [ ] Track CPU usage
  - [ ] Track network usage
  - [ ] Adjust concurrency dynamically

- [ ] 🧪 Performance testing
  - [ ] Test with 10 files
  - [ ] Test with 1000 files
  - [ ] Test with 10,000 files
  - [ ] Measure resource usage
  - [ ] Verify profile scaling works

### 4.7 Sync Testing

- [ ] 🧪 Create test scenarios
  ```go
  func TestFullSync(t *testing.T) {
      // Create local files
      // Start sync
      // Verify upload
      // Modify remote
      // Verify download
  }
  ```
  - [ ] Test initial sync
  - [ ] Test incremental sync
  - [ ] Test large file sync
  - [ ] Test many small files
  - [ ] Test sync interruption/resume

---

## PHASE 5: TESTING & OPTIMIZATION (5-7 DAYS)

**Goal**: Comprehensive testing and performance optimization.

### 5.1 Unit Tests

- [ ] 🧪 Test coverage audit
  ```bash
  go test -cover ./... | grep -v "100.0%"
  ```
  - [ ] Ensure ≥80% coverage in all packages
  - [ ] Write missing tests
  - [ ] Document untested code (if any)

- [ ] 🧪 Package-specific tests
  - [ ] internal/config (100%)
  - [ ] internal/client (≥80%)
  - [ ] internal/sync (≥80%)
  - [ ] internal/storage (≥80%)
  - [ ] internal/gui (≥60%, harder to test)

### 5.2 Integration Tests

- [ ] 🧪 Create `integration_test.go`
  ```go
  //go:build integration
  
  func TestFullWorkflow(t *testing.T) {
      // Real ProtonDrive account
      // Create files
      // Upload
      // Download
      // Verify
  }
  ```
  - [ ] Test with real ProtonDrive account
  - [ ] Test authentication flow
  - [ ] Test file operations
  - [ ] Test sync engine
  - [ ] Document setup requirements

### 5.3 Hardware Compatibility Tests

- [ ] 🧪 Test on different systems
  - [ ] Ubuntu 22.04 (x64)
  - [ ] Debian 12 (x64)
  - [ ] Fedora 39 (x64)
  - [ ] Arch Linux (x64)
  - [ ]
