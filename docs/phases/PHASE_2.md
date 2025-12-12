# Phase 2: Core API & Sync Engine

**Duration**: 6-8 days  
**Status**: ❌ Blocked by Phase 1  
**Dependencies**: Phase 1 (Foundation) complete  
**Unlocks**: Phase 3

---

## OVERVIEW

Implement ProtonDrive integration and sync functionality.

**Entry Criteria**: 
- Phase 1 complete
- CI/CD pipeline passing
- 100% test coverage on encryption

**Exit Criteria**:
- Can authenticate with ProtonDrive via CLI
- Can list, upload, download files via CLI
- Sync engine detects and syncs changes
- All tests passing

---

## INTERNAL DEPENDENCIES

```
1.4 Encryption ──┬──► 2.1 Proton Client ──► 2.2 File Operations
1.5 Storage ─────┘           │                      │
                             │                      ▼
                             ▼              2.3 Sync Engine
                        2.5 Observability          │
                             │                     │
                             ▼                     ▼
                        2.4 CLI ◄──────────────────┘
```

---

## 2.1 PROTON CLIENT WRAPPER

**Dependencies**: 1.4 (Encryption), 1.5 (Storage)  
**Output**: `internal/client/`  
**Estimated Time**: 1.5 days

### Research (Do First)

- [ ] 🔍 **Study Proton-API-Bridge thoroughly**
  - [ ] Read all documentation
  - [ ] Examine example code in repo
  - [ ] Understand authentication flow (SRP protocol)
  - [ ] Understand session management
  - [ ] Document API methods we need
  - [ ] Note rate limiting behavior
  - [ ] Note error types returned

### Tasks

- [ ] 🏗️ **Create `internal/client/client.go`**
  - [ ] `Client` struct wrapping Proton-API-Bridge:
    ```go
    type Client struct {
        bridge    *protonapi.Client
        config    *ClientConfig
        encryptor encryption.Encryptor
        store     storage.Store
        mu        sync.RWMutex
    }
    ```
  - [ ] `ClientConfig` struct:
    ```go
    type ClientConfig struct {
        AppVersion string
        UserAgent  string
        Timeout    time.Duration
        RetryConfig *errors.RetryConfig
    }
    ```
  - [ ] `NewClient(config *ClientConfig, enc encryption.Encryptor, store storage.Store) (*Client, error)`
  - [ ] `Close() error`
  - [ ] `IsConnected() bool`

- [ ] 🔒 **Create `internal/client/auth.go`**
  - [ ] `Login(username, password string) error`
    - Use Proton-API-Bridge SRP authentication
    - On success, store session token in keyring
    - Never store password
  - [ ] `LoginWithSession() error`
    - Load session from keyring
    - Validate session still valid
  - [ ] `Logout() error`
    - Invalidate session with API
    - Remove from keyring
  - [ ] `IsAuthenticated() bool`
  - [ ] `RefreshSession() error`
    - Refresh before expiry
    - Update stored token
  - [ ] `GetCurrentUser() (*UserInfo, error)`

- [ ] 🏗️ **Create `internal/client/session.go`**
  - [ ] `saveSession(token string) error`
    - Encrypt token
    - Store in keyring (primary)
    - Fallback to encrypted file
  - [ ] `loadSession() (string, error)`
    - Try keyring first
    - Fall back to encrypted file
  - [ ] `clearSession() error`
    - Remove from keyring
    - Remove fallback file if exists
  - [ ] `isSessionValid(token string) bool`
    - Check expiry time
    - Optionally ping API

- [ ] 🏗️ **Create `internal/client/retry.go`**
  - [ ] `withRetry(fn func() error) error`
    - Use RetryConfig from errors package
    - Retry on retryable errors
    - Respect rate limit headers
  - [ ] `withRetryResult[T](fn func() (T, error)) (T, error)`
    - Generic version for functions returning values

- [ ] 🏗️ **Create `internal/client/ratelimit.go`**
  - [ ] `RateLimiter` struct:
    ```go
    type RateLimiter struct {
        tokens    int
        maxTokens int
        refillRate time.Duration
        mu        sync.Mutex
    }
    ```
  - [ ] `NewRateLimiter(maxTokens int, refillRate time.Duration) *RateLimiter`
  - [ ] `Wait(ctx context.Context) error` - block until token available
  - [ ] `TryAcquire() bool` - non-blocking
  - [ ] Handle 429 responses: parse Retry-After header

- [ ] 🧪 **Create `internal/client/client_test.go`**
  - [ ] `TestNewClient` - creates client
  - [ ] `TestClientClose` - closes cleanly

- [ ] 🧪 **Create `internal/client/auth_test.go`**
  - [ ] `TestLogin_Success` - mock successful login
  - [ ] `TestLogin_InvalidCredentials` - returns auth error
  - [ ] `TestLogin_NetworkError` - returns network error
  - [ ] `TestLoginWithSession_Valid` - uses stored session
  - [ ] `TestLoginWithSession_Expired` - returns error
  - [ ] `TestLogout` - clears session
  - [ ] `TestRefreshSession` - updates token

- [ ] 🧪 **Create `internal/client/retry_test.go`**
  - [ ] `TestWithRetry_Success` - no retry needed
  - [ ] `TestWithRetry_RetryThenSuccess` - retries and succeeds
  - [ ] `TestWithRetry_MaxRetries` - fails after max
  - [ ] `TestWithRetry_NonRetryable` - fails immediately

- [ ] 🧪 **Create `internal/client/ratelimit_test.go`**
  - [ ] `TestRateLimiter_Acquire` - basic acquisition
  - [ ] `TestRateLimiter_Wait` - blocks when empty
  - [ ] `TestRateLimiter_Refill` - tokens replenish

- [ ] 🔒🧪 **Create `tests/security/auth_test.go`**
  - [ ] `TestPasswordNeverStored`
    - Login with known password
    - Search all files for password string
    - Assert not found
  - [ ] `TestSessionTokenInKeyring`
    - Login successfully
    - Verify token is in keyring
    - Verify no token in plaintext files

### Acceptance Criteria
- [ ] Can authenticate with ProtonDrive
- [ ] Session persists across restarts
- [ ] Session refresh works
- [ ] Rate limiting prevents API abuse
- [ ] Retry logic handles transient failures
- [ ] Password never stored anywhere

---

## 2.2 FILE OPERATIONS

**Dependencies**: 2.1 (Client)  
**Output**: `internal/client/files.go`, `internal/client/upload.go`, `internal/client/download.go`  
**Estimated Time**: 1.5 days

### Tasks

- [ ] 🏗️ **Create `internal/client/files.go`**
  - [ ] `FileInfo` struct:
    ```go
    type FileInfo struct {
        ID       string
        Name     string
        Path     string
        Size     int64
        ModTime  time.Time
        IsFolder bool
        Hash     string
        ParentID string
    }
    ```
  - [ ] `ListFiles(ctx context.Context, path string) ([]*FileInfo, error)`
    - List contents of folder
    - Handle pagination if needed
  - [ ] `GetFileInfo(ctx context.Context, path string) (*FileInfo, error)`
  - [ ] `CreateFolder(ctx context.Context, path string) (*FileInfo, error)`
  - [ ] `DeleteFile(ctx context.Context, path string) error`
    - Handle both files and folders
  - [ ] `MoveFile(ctx context.Context, oldPath, newPath string) error`
  - [ ] `RenameFile(ctx context.Context, path, newName string) error`

- [ ] 🏗️ **Create `internal/client/upload.go`**
  - [ ] `Upload(ctx context.Context, localPath, remotePath string) error`
    - Read local file
    - Proton-API-Bridge handles encryption
    - Upload to ProtonDrive
  - [ ] `UploadWithProgress(ctx context.Context, local, remote string, progress chan<- Progress) error`
    - Report progress during upload
  - [ ] `Progress` struct:
    ```go
    type Progress struct {
        BytesComplete int64
        BytesTotal    int64
        Percentage    float64
    }
    ```
  - [ ] Handle large files:
    - Chunk into pieces (5-10MB based on profile)
    - Upload chunks sequentially or in parallel
    - Support resume from last successful chunk

- [ ] 🏗️ **Create `internal/client/download.go`**
  - [ ] `Download(ctx context.Context, remotePath, localPath string) error`
    - Download from ProtonDrive
    - Proton-API-Bridge handles decryption
    - Write to local file
  - [ ] `DownloadWithProgress(ctx context.Context, remote, local string, progress chan<- Progress) error`
  - [ ] Handle large files:
    - Download in chunks
    - Verify hash after complete
    - Support resume

- [ ] 🧪 **Create `internal/client/files_test.go`**
  - [ ] `TestListFiles` - returns file list
  - [ ] `TestListFiles_Empty` - empty folder
  - [ ] `TestGetFileInfo` - returns info
  - [ ] `TestGetFileInfo_NotFound` - returns error
  - [ ] `TestCreateFolder` - creates folder
  - [ ] `TestDeleteFile` - deletes file
  - [ ] `TestDeleteFolder` - deletes folder recursively
  - [ ] `TestMoveFile` - moves file
  - [ ] `TestRenameFile` - renames file

- [ ] 🧪 **Create `internal/client/upload_test.go`**
  - [ ] `TestUpload_SmallFile` - <1MB
  - [ ] `TestUpload_LargeFile` - >10MB
  - [ ] `TestUploadWithProgress` - progress reported
  - [ ] `TestUpload_NetworkError` - retries
  - [ ] `TestUpload_Resume` - resumes from checkpoint

- [ ] 🧪 **Create `internal/client/download_test.go`**
  - [ ] `TestDownload_SmallFile`
  - [ ] `TestDownload_LargeFile`
  - [ ] `TestDownloadWithProgress`
  - [ ] `TestDownload_NetworkError`
  - [ ] `TestDownload_Resume`
  - [ ] `TestDownload_VerifyHash` - hash matches

### Acceptance Criteria
- [ ] Can list files in ProtonDrive
- [ ] Can upload files (small and large)
- [ ] Can download files (small and large)
- [ ] Can create/delete/move/rename
- [ ] Progress reporting works
- [ ] Resume works for interrupted transfers
- [ ] Hash verification ensures integrity

---

## 2.3 SYNC ENGINE

**Dependencies**: 2.2 (File Operations), 1.5 (Storage)  
**Output**: `internal/sync/`  
**Estimated Time**: 2 days

### Tasks

- [ ] 🏗️ **Create `internal/sync/watcher.go`**
  - [ ] `Watcher` interface:
    ```go
    type Watcher interface {
        Start() error
        Stop() error
        Events() <-chan FileEvent
        Errors() <-chan error
    }
    ```
  - [ ] `FileEvent` struct:
    ```go
    type FileEvent struct {
        Path      string
        EventType EventType // Create, Modify, Delete, Rename
        OldPath   string    // For rename events
        Time      time.Time
    }
    ```
  - [ ] `FSNotifyWatcher` implementation:
    - Use fsnotify for inotify
    - Handle recursive directory watching
    - Debounce rapid events
  - [ ] `PollingWatcher` implementation:
    - Fall back for NFS/FUSE
    - Configurable interval
    - Compare file hashes
  - [ ] `NewWatcher(path string, usePolling bool, interval time.Duration) (Watcher, error)`
    - Auto-detect if polling needed
    - Handle inotify limit errors

- [ ] 🏗️ **Create `internal/sync/hasher.go`**
  - [ ] `HashFile(path string) (string, error)`
    - SHA256 hash of file content
  - [ ] `HashFileChunked(path string, chunkSize int) (string, error)`
    - For very large files
  - [ ] `CompareHashes(hash1, hash2 string) bool`

- [ ] 🏗️ **Create `internal/sync/engine.go`**
  - [ ] `SyncEngine` struct:
    ```go
    type SyncEngine struct {
        client   *client.Client
        store    storage.Store
        watcher  Watcher
        profile  *profile.Profile
        
        uploadQueue   chan SyncTask
        downloadQueue chan SyncTask
        
        status    SyncStatus
        statusMu  sync.RWMutex
        
        ctx       context.Context
        cancel    context.CancelFunc
        wg        sync.WaitGroup
    }
    ```
  - [ ] `NewSyncEngine(client, store, watcher, profile) (*SyncEngine, error)`
  - [ ] `Start() error`
    - Start watcher
    - Start worker pools
    - Begin initial sync
  - [ ] `Stop() error`
    - Cancel context
    - Wait for workers
    - Save state
  - [ ] `Pause() error`
  - [ ] `Resume() error`
  - [ ] `Status() SyncStatus`
  - [ ] `ForceSync() error` - trigger full sync

- [ ] 🏗️ **Create `internal/sync/workers.go`**
  - [ ] Upload worker pool:
    - Concurrent uploads based on profile
    - Process from uploadQueue
    - Update storage after success
  - [ ] Download worker pool:
    - Concurrent downloads based on profile
    - Process from downloadQueue
    - Update storage after success
  - [ ] `SyncTask` struct:
    ```go
    type SyncTask struct {
        Type      TaskType // Upload, Download, Delete
        LocalPath string
        RemotePath string
        Priority  int
    }
    ```

- [ ] 🏗️ **Create `internal/sync/detector.go`**
  - [ ] `DetectLocalChanges() ([]*SyncTask, error)`
    - Compare local files to stored metadata
    - Return tasks for changed files
  - [ ] `DetectRemoteChanges() ([]*SyncTask, error)`
    - List remote files
    - Compare to stored metadata
    - Return tasks for changes
  - [ ] `ReconcileChanges(local, remote []*SyncTask) ([]*SyncTask, []*Conflict, error)`
    - Identify conflicts
    - Merge non-conflicting changes

- [ ] 🏗️ **Create `internal/sync/conflict.go`**
  - [ ] `Conflict` struct:
    ```go
    type Conflict struct {
        FileID      string
        LocalPath   string
        RemotePath  string
        LocalHash   string
        RemoteHash  string
        LocalModTime  time.Time
        RemoteModTime time.Time
    }
    ```
  - [ ] `ConflictStrategy` enum:
    ```go
    type ConflictStrategy string
    const (
        ServerWins ConflictStrategy = "server_wins"
        LocalWins  ConflictStrategy = "local_wins"
        KeepBoth   ConflictStrategy = "keep_both"
        Manual     ConflictStrategy = "manual"
    )
    ```
  - [ ] `ResolveConflict(conflict *Conflict, strategy ConflictStrategy) (*SyncTask, error)`
    - ServerWins: download remote version
    - LocalWins: upload local version
    - KeepBoth: rename local, download remote
    - Manual: mark for user decision

- [ ] 🏗️ **Create `internal/sync/state.go`**
  - [ ] `SaveState() error` - persist to encrypted storage
  - [ ] `LoadState() error` - restore on startup
  - [ ] `UpdateFileState(path string, state FileState) error`
  - [ ] Handle crash recovery:
    - Detect incomplete operations
    - Resume or rollback

- [ ] 🧪 **Create `internal/sync/watcher_test.go`**
  - [ ] `TestFSNotifyWatcher_Create` - detects new file
  - [ ] `TestFSNotifyWatcher_Modify` - detects modification
  - [ ] `TestFSNotifyWatcher_Delete` - detects deletion
  - [ ] `TestFSNotifyWatcher_Rename` - detects rename
  - [ ] `TestPollingWatcher` - same tests
  - [ ] `TestWatcherFallback` - switches to polling

- [ ] 🧪 **Create `internal/sync/hasher_test.go`**
  - [ ] `TestHashFile` - correct hash
  - [ ] `TestHashFile_LargeFile` - handles large files
  - [ ] `BenchmarkHashFile` - measure throughput

- [ ] 🧪 **Create `internal/sync/engine_test.go`**
  - [ ] `TestSyncEngineStart` - starts successfully
  - [ ] `TestSyncEngineStop` - stops cleanly
  - [ ] `TestSyncEnginePauseResume` - pause and resume
  - [ ] `TestSyncEngine_LocalChange` - uploads new file
  - [ ] `TestSyncEngine_RemoteChange` - downloads new file
  - [ ] `TestSyncEngine_Conflict` - detects conflict

- [ ] 🧪 **Create `internal/sync/conflict_test.go`**
  - [ ] `TestResolveConflict_ServerWins`
  - [ ] `TestResolveConflict_LocalWins`
  - [ ] `TestResolveConflict_KeepBoth`

- [ ] 🔒🧪 **Create `tests/security/sync_test.go`**
  - [ ] `TestSyncStateEncrypted`
    - Run sync engine
    - Check state file is encrypted
  - [ ] `TestCachedFilesEncrypted`
    - Sync a file
    - Check cache is encrypted
  - [ ] `TestConflictLogNoPlaintext`
    - Create conflict
    - Check logs have no filename

### Acceptance Criteria
- [ ] File watcher detects all change types
- [ ] Polling fallback works for NFS
- [ ] Sync engine uploads local changes
- [ ] Sync engine downloads remote changes
- [ ] Conflicts detected and resolved
- [ ] State persists across restarts
- [ ] All state encrypted

---

## 2.4 COMMAND-LINE INTERFACE

**Dependencies**: 2.1 (Client), 2.3 (Sync Engine)  
**Output**: `cmd/protondrive/`  
**Estimated Time**: 1 day

### Tasks

- [ ] 🏗️ **Create `cmd/protondrive/main.go`**
  - [ ] Parse flags:
    ```go
    var (
        configPath = flag.String("config", "", "config file path")
        verbose    = flag.Bool("verbose", false, "verbose output")
        profile    = flag.String("profile", "auto", "performance profile")
        version    = flag.Bool("version", false, "show version")
        health     = flag.Bool("health", false, "show health status")
    )
    ```
  - [ ] Initialize components based on flags
  - [ ] Start sync engine or GUI

- [ ] 🏗️ **Create `cmd/protondrive/commands.go`**
  - [ ] `cmdLogin()` - interactive login
  - [ ] `cmdLogout()` - logout and clear session
  - [ ] `cmdStatus()` - show sync status
  - [ ] `cmdSync()` - trigger one-time sync
  - [ ] `cmdHealth()` - show health check
  - [ ] `cmdVersion()` - show version info

- [ ] 🏗️ **Create `cmd/protondrive/interactive.go`**
  - [ ] `promptUsername() string` - read from stdin
  - [ ] `promptPassword() string` - read without echo
  - [ ] `confirmAction(msg string) bool` - y/n prompt

- [ ] 🧪 **Create `cmd/protondrive/main_test.go`**
  - [ ] `TestFlagParsing` - all flags parsed correctly
  - [ ] `TestVersionFlag` - prints version
  - [ ] `TestHealthFlag` - prints health

- [ ] 🔒🧪 **Create `tests/security/cli_test.go`**
  - [ ] `TestVerboseOutputNoFilenames`
    - Run with --verbose
    - Capture output
    - Assert no plaintext filenames

### Acceptance Criteria
- [ ] CLI parses all flags correctly
- [ ] Login/logout work
- [ ] Status shows sync state
- [ ] Health check works
- [ ] Verbose mode has no plaintext filenames

---

## 2.5 OBSERVABILITY

**Dependencies**: 2.1 (Client), 1.2 (Errors)  
**Output**: `internal/observability/`  
**Estimated Time**: 0.5 days

### Tasks

- [ ] 🏗️ **Create `internal/observability/logger.go`**
  - [ ] `Logger` interface:
    ```go
    type Logger interface {
        Debug(msg string, fields ...Field)
        Info(msg string, fields ...Field)
        Warn(msg string, fields ...Field)
        Error(msg string, fields ...Field)
    }
    ```
  - [ ] `Field` struct for structured logging
  - [ ] Console logger implementation
  - [ ] Log levels configurable
  - [ ] **CRITICAL**: Never log filenames, only file IDs

- [ ] 🏗️ **Create `internal/observability/health.go`**
  - [ ] `HealthStatus` struct:
    ```go
    type HealthStatus struct {
        Overall    string            // healthy, degraded, unhealthy
        Components map[string]string // component -> status
        Timestamp  time.Time
    }
    ```
  - [ ] `CheckHealth() *HealthStatus`
    - Check database accessible
    - Check keyring available
    - Check network connectivity
    - Check disk space
  - [ ] `CheckComponent(name string) (string, error)`

- [ ] 🏗️ **Create `internal/observability/metrics.go`**
  - [ ] Internal metrics (not exported):
    - Files synced (up/down)
    - Bytes transferred
    - Errors count
    - Sync duration
  - [ ] `GetMetrics() *Metrics`

- [ ] 🧪 **Create `internal/observability/logger_test.go`**
  - [ ] `TestLogLevels` - respects level setting
  - [ ] `TestLoggerNoFilenames` - verify no plaintext

- [ ] 🧪 **Create `internal/observability/health_test.go`**
  - [ ] `TestCheckHealth` - returns status
  - [ ] `TestCheckComponent` - individual checks

### Acceptance Criteria
- [ ] Logger never outputs filenames
- [ ] Health check covers all components
- [ ] Metrics track key operations
- [ ] All observability is internal only

---

## PHASE 2 EXIT CHECKLIST

Before moving to Phase 3, verify:

- [ ] **Authentication works**
  - [ ] Can login via CLI
  - [ ] Session persists
  - [ ] Can logout

- [ ] **File operations work**
  - [ ] Can list files
  - [ ] Can upload files
  - [ ] Can download files
  - [ ] Can create/delete/move folders

- [ ] **Sync works**
  - [ ] Local changes sync up
  - [ ] Remote changes sync down
  - [ ] Conflicts detected

- [ ] **All tests passing**
  - [ ] Unit tests pass
  - [ ] Security tests pass
  - [ ] CI/CD green

- [ ] **Documentation updated**
  - [ ] CHANGELOG.md updated
  - [ ] This file updated with completion status

---

**Phase 2 Estimated Completion**: 6-8 days  
**Next Phase**: [PHASE_3.md](./PHASE_3.md) - GUI Development