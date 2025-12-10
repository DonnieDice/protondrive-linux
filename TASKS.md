# ProtonDrive Linux - Task List

**Last Updated**: 2024-12-10  
**Project Phase**: Foundation & Core Integration  
**Technology Stack**: Go + Fyne + GopenPGP (Proton Official)  
**Estimated Timeline**: 6 weeks to MVP

---

## PHASES OVERVIEW

| Phase | Description | Duration | Status |
|-------|-------------|----------|--------|
| 0 | Migration & Setup | 1-2 days | ✅ Complete |
| 1 | Project Foundation + Encryption | 4-5 days | ⬅️ Current |
| 2 | Core Integration | 3-5 days | Not Started |
| 3 | GUI Development | 5-7 days | Not Started |
| 4 | Sync Engine | 7-10 days | Not Started |
| 5 | Testing & Optimization | 5-7 days | Not Started |
| 6 | Distribution | 3-5 days | Not Started |

**Total**: ~28-41 days (6 weeks)

---

## LEGEND

```
[ ] Not Started
[⏳] In Progress  
[✅] Complete
[🔄] Needs Revision
[❌] Blocked

🏗️ Infrastructure    🔒 Security-Critical
📝 Documentation     🧪 Testing
🔍 Research          🚀 Release
```

---

## DEPENDENCY SUMMARY

**Core (5-6 total):**
```go
require (
    github.com/ProtonMail/gopenpgp/v3      // Proton crypto (OFFICIAL)
    github.com/henrybear327/Proton-API-Bridge // Drive API
    fyne.io/fyne/v2                         // GUI
    github.com/fsnotify/fsnotify            // File watching
    github.com/zalando/go-keyring           // Credentials
    github.com/stretchr/testify             // Testing
)
```

---

## PHASE 0: MIGRATION & SETUP ✅ COMPLETE

- [✅] 🏗️ Backup Electron project (git branch)
- [✅] 🏗️ Clean Electron artifacts
- [✅] 🏗️ Initialize Go module
- [✅] 🏗️ Create directory structure
- [✅] 📝 Update README.md with new tech stack
- [✅] 🔍 Review project context documents

---

## PHASE 1: FOUNDATION + ENCRYPTION (4-5 DAYS) ⬅️ CURRENT

### 1.1 Configuration System
- [✅] 🏗️ Create `internal/config/config.go`
- [✅] 🏗️ Define `Config` struct
- [✅] 🏗️ Load from `~/.config/protondrive-linux/config.json`
- [✅] 🏗️ Implement validation and defaults
- [✅] 🧪 Write config tests
- [ ] 🔒 Audit: ensure no sensitive data stored unencrypted
- [ ] 🧪 Test: verify no filenames/credentials in config.json

### 1.2 Local Encryption Layer (GopenPGP)
**Using Proton's official crypto library - RFC 9580 profile (Argon2 + AEAD automatic)**

- [ ] 🔒 Create `internal/encryption/` package
- [ ] 🔒 Implement GopenPGP wrapper (`gopenpgp.go`)
  - [ ] Initialize PGP with RFC 9580 profile
  - [ ] Password-based encryption (Argon2 handled internally)
  - [ ] Password-based decryption
  - [ ] Streaming encryption for large files
- [ ] 🔒 Implement keyring integration (`keyring.go`)
  - [ ] Store session in OS keyring (primary)
  - [ ] Encrypted file fallback (secondary)
  - [ ] Password prompt fallback (tertiary)
- [ ] 🔒 Implement local storage encryption (`storage.go`)
  - [ ] Encrypt metadata files (.gpg format)
  - [ ] Encrypt sync state files
  - [ ] Filename obfuscation (SHA256 hash)
- [ ] 🔒 Implement memory security (`memory.go`)
  - [ ] Secure byte slice wiping
  - [ ] Defer cleanup patterns
  - [ ] Force garbage collection
- [ ] 🧪 Write comprehensive tests (100% coverage required)
  - [ ] TestGopenPGPEncryptDecrypt
  - [ ] TestKeyringIntegration
  - [ ] TestKeyringFallback
  - [ ] TestFilenameObfuscation
  - [ ] TestMemoryWiping
  - [ ] BenchmarkEncryption (target: >100 MB/s with AES-NI)

### 1.3 Performance Profiling
- [✅] 🏗️ Create `internal/profile/detector.go`
- [✅] 🔍 Detect RAM, CPU cores, storage type
- [✅] 🏗️ Select performance profile (Low/Standard/High)
- [✅] 🧪 Write detection tests
- [ ] 🔍 Detect hardware AES support (AES-NI/ARM crypto)

### 1.4 Database Layer (Encrypted with GopenPGP)
**Note: Using file-based encrypted storage, NOT SQLCipher**

- [ ] 🏗️ Create `internal/storage/` package
- [ ] 🏗️ Implement encrypted JSON storage
  - [ ] Load: Read file → Decrypt with GopenPGP → Parse JSON
  - [ ] Save: Serialize JSON → Encrypt with GopenPGP → Write file
- [ ] 🏗️ Define data models (`models.go`)
  - [ ] FileMetadata struct
  - [ ] SyncState struct
  - [ ] ConflictRecord struct
- [ ] 🏗️ Implement CRUD operations
- [ ] 🧪 Write storage tests
- [ ] 🧪 Test: verify storage cannot be read without password

### 1.5 Error Handling
- [✅] 🏗️ Define custom error types (`internal/errors/`)
- [✅] 🏗️ Create error wrapper
- [✅] 🔒 Ensure errors contain no sensitive data (file IDs only)
- [✅] 🧪 Write error handling tests

### 1.6 Testing Infrastructure
- [✅] 🏗️ Set up test helpers (`internal/testutil/`)
- [✅] 🏗️ Create mock ProtonClient
- [ ] 🏗️ Create mock encryption layer
- [✅] 🏗️ Prepare test fixtures
- [ ] 🔒 Create security test helpers (`tests/security/`)

---

## PHASE 2: CORE INTEGRATION (3-5 DAYS)

### 2.1 Proton Client Wrapper
- [✅] 🔍 Research Proton-API-Bridge
- [✅] 📝 Create `internal/client/client.go`
- [✅] 🏗️ Implement client initialization
- [✅] 🏗️ Implement authentication
- [ ] 🔒 Implement session management
  - [ ] Store tokens in OS keyring
  - [ ] Never store passwords
  - [ ] Auto-refresh tokens
- [ ] 🏗️ Add error handling

### 2.2 Session Management
- [ ] 📝 Create `internal/client/session.go`
  - [ ] Token storage in keyring
  - [ ] Token refresh logic
  - [ ] Re-authentication on failure
- [ ] 📝 Create `internal/client/keyring.go`
  - [ ] Primary: OS Secret Service
  - [ ] Fallback: GopenPGP encrypted file
- [ ] 🧪 Security testing
  - [ ] Verify credentials never stored
  - [ ] Test session refresh
  - [ ] Test keyring fallback

### 2.3 File Operations
- [ ] 📝 Create `internal/client/files.go`
  - [ ] ListFiles
  - [ ] CreateFolder
  - [ ] UploadFile (with progress)
  - [ ] DownloadFile (with progress)
  - [ ] DeleteFile
  - [ ] MoveFile
- [ ] 🏗️ Handle large files (chunking)
- [ ] 🏗️ Add rate limiting
- [ ] 🔒 Encrypt all metadata before storing
- [ ] 🧪 Write file operation tests

### 2.4 Network & Retry Logic
- [ ] 📝 Create `internal/client/retry.go`
  - [ ] Exponential backoff
  - [ ] Max retry attempts
  - [ ] Jitter to prevent thundering herd
- [ ] 📝 Create `internal/client/ratelimit.go`
  - [ ] Token bucket algorithm
  - [ ] Respect API limits
- [ ] 🧪 Test error scenarios

### 2.5 Command-Line Interface
- [ ] 🏗️ Create `cmd/protondrive/main.go`
- [ ] 🏗️ Implement flags: `--verbose`, `--config`, `--profile`, `--version`, `--health`
- [ ] 🔒 Ensure verbose output has no plaintext filenames
- [ ] 📝 Add help text
- [ ] 🧪 Write CLI tests

---

## PHASE 3: GUI DEVELOPMENT (5-7 DAYS)

### 3.1 Application Window
- [ ] 🏗️ Create `internal/gui/app.go`
- [ ] 🏗️ Initialize Fyne application
- [ ] 🏗️ Set window properties

### 3.2 Login Screen
- [ ] 🏗️ Create `internal/gui/login.go`
  - [ ] Username/password fields
  - [ ] Login button
  - [ ] Error display
  - [ ] Loading indicator
- [ ] 🔒 Ensure password never logged
- [ ] 🧪 Test login UI

### 3.3 Main View (File List)
- [ ] 🏗️ Create `internal/gui/filelist.go`
  - [ ] Tree view for folders
  - [ ] File list with sorting
  - [ ] Sync status indicators
- [ ] 🔒 Decrypt filenames in memory only
- [ ] 🧪 Test file list display

### 3.4 Toolbar & Actions
- [ ] 🏗️ Implement toolbar
  - [ ] Upload, Download
  - [ ] New Folder, Delete
  - [ ] Settings, Refresh
- [ ] 🧪 Test toolbar actions

### 3.5 Settings Dialog
- [ ] 🏗️ Create `internal/gui/settings.go`
  - [ ] Sync directory chooser
  - [ ] Performance profile selector
  - [ ] Theme toggle
  - [ ] About section
- [ ] 🔒 Add "Clear Session Data" button
- [ ] 🔒 Add "Delete All Local Data" option
- [ ] 🧪 Test settings UI

### 3.6 System Tray
- [ ] 🏗️ Create `internal/gui/tray.go`
- [ ] 🏗️ Add tray icon with menu
- [ ] 🏗️ Handle tray events

### 3.7 Notifications
- [ ] 🏗️ Implement desktop notifications
- [ ] 🔒 Ensure notifications have no filenames

---

## PHASE 4: SYNC ENGINE (7-10 DAYS)

### 4.1 File Watcher
- [ ] 🏗️ Create `internal/sync/watcher.go`
  - [ ] Primary: fsnotify (inotify)
  - [ ] Fallback: polling for NFS/FUSE
- [ ] 🏗️ Monitor sync directory
- [ ] 🏗️ Ignore temp/system files
- [ ] 🧪 Test file watcher

### 4.2 Sync Manager
- [ ] 🏗️ Create `internal/sync/manager.go`
  - [ ] Worker pools based on profile
  - [ ] Event queue processing
  - [ ] Graceful shutdown
- [ ] 🏗️ Implement upload workers
- [ ] 🏗️ Implement download workers
- [ ] 🔒 Encrypt all sync state
- [ ] 🧪 Test sync manager

### 4.3 Conflict Resolution
- [ ] 🏗️ Create `internal/sync/conflict.go`
  - [ ] Detect conflicts
  - [ ] Strategies: Server Wins, Local Wins, Keep Both, Manual
  - [ ] User notification
- [ ] 🔒 Log conflicts with file IDs only
- [ ] 🧪 Test conflict scenarios

### 4.4 Change Detection
- [ ] 🏗️ Create `internal/sync/hash.go`
  - [ ] SHA-256 file hashing
  - [ ] Hash caching (encrypted)
  - [ ] Large file optimization
- [ ] 🧪 Test hashing (target: >100 MB/s)

### 4.5 Sync State & Recovery
- [ ] 🏗️ Implement state machine
- [ ] 🏗️ Crash recovery
- [ ] 🏗️ Pause/Resume
- [ ] 🔒 Encrypt all state data

---

## PHASE 5: TESTING & OPTIMIZATION (5-7 DAYS)

### 5.1 Unit Tests
- [ ] 🧪 Coverage audit (target: 80% overall, 100% security)
- [ ] 🧪 Package-specific tests

### 5.2 Integration Tests
- [ ] 🧪 Create `tests/integration/`
  - [ ] Full auth flow
  - [ ] E2E file operations
  - [ ] Sync cycles
  - [ ] Encryption verification

### 5.3 Security Tests
- [ ] 🔒 Create `tests/security/`
- [ ] 🔒 TestStorageIsEncrypted
- [ ] 🔒 TestCacheFilesEncrypted
- [ ] 🔒 TestLogsContainNoPlaintext
- [ ] 🔒 TestMemoryWiping
- [ ] 🔒 TestConfigNoSensitiveData

### 5.4 Performance Tests
- [ ] 🧪 Create `tests/performance/`
- [ ] 🧪 BenchmarkColdStart (<500ms)
- [ ] 🧪 BenchmarkWarmStart (<200ms)
- [ ] 🧪 TestMemoryUsage per profile
- [ ] 🧪 BenchmarkEncryption (>100 MB/s)

### 5.5 Cross-Platform Tests
- [ ] 🧪 Test on Ubuntu, Fedora, Arch (x86_64)
- [ ] 🧪 Test on Raspberry Pi (ARM64, ARMv7)
- [ ] 🧪 Test hardware AES detection

### 5.6 CI/CD Pipeline
- [ ] 🏗️ Create `.github/workflows/ci.yml`
  - [ ] Test job (go test, go vet, staticcheck)
  - [ ] Security job (govulncheck)
  - [ ] Build job (linux-amd64, linux-arm64, linux-armv7)
  - [ ] Release job (on tag)
  - [ ] Benchmark job (main branch only)
- [ ] 🏗️ Configure code coverage reporting
- [ ] 🏗️ Set up artifact uploads

### 5.7 Privacy Audit
- [ ] 🔍 Grep for `log.Print*` (should be 0 in production)
- [ ] 🔍 Verify no analytics/telemetry
- [ ] 🔍 Verify no crash reporting
- [ ] 🔍 Network calls are ProtonDrive only
- [ ] 📝 Create `PRIVACY_AUDIT.md`

---

## PHASE 6: DISTRIBUTION (3-5 DAYS)

### 6.1 Package Formats
- [ ] 🏗️ Build `.deb` (Debian/Ubuntu)
- [ ] 🏗️ Build `.rpm` (Fedora/openSUSE)
- [ ] 🏗️ Build Flatpak
- [ ] 🏗️ Build AppImage

### 6.2 Release Automation
- [ ] 🏗️ CI/CD pipeline (GitHub Actions)
- [ ] 🏗️ Cross-compilation scripts
- [ ] 🏗️ Signed releases

### 6.3 Documentation
- [ ] 📝 Complete README.md
- [ ] 📝 Create user manual
- [ ] 📝 Installation guides per distro
- [ ] 📝 Security documentation

### 6.4 Release
- [ ] 🚀 Final QA
- [ ] 🚀 Create GitHub release
- [ ] 🚀 Announce release

---

## PRIORITY MATRIX

### P0 - Critical (MVP Blockers)
- [ ] GopenPGP encryption layer
- [ ] Encrypted local storage
- [ ] Memory security (wiping)
- [ ] Basic authentication
- [ ] Basic file operations
- [ ] Basic sync engine
- [ ] Security tests passing

### P1 - High (MVP Quality)
- [ ] Conflict resolution
- [ ] Performance profiling
- [ ] GUI implementation
- [ ] System tray
- [ ] Unit tests (80% coverage)

### P2 - Medium (v1.0)
- [ ] Selective sync
- [ ] Desktop notifications
- [ ] Advanced settings
- [ ] Performance optimization

### P3 - Low (Future)
- [ ] File versioning UI
- [ ] Share link generation
- [ ] Multiple accounts
- [ ] LAN sync

---

## CRITICAL PATH

```
1. Encryption Layer (Phase 1.2) ──┐
                                  ├─→ 3. Auth + File Ops (Phase 2)
2. Storage Layer (Phase 1.4) ─────┘              │
                                                 ↓
                              4. Sync Engine (Phase 4)
                                                 │
                                                 ↓
                              5. Security Tests (Phase 5.3)
                                                 │
                                                 ↓
                              6. Release (Phase 6)
```

---

## NOTES

### Key Simplifications (v11.0)
1. **GopenPGP replaces multiple crypto packages** - RFC 9580 profile handles Argon2 + AEAD automatically
2. **No SQLCipher** - Using GopenPGP-encrypted JSON files instead (simpler, no CGO)
3. **5-6 dependencies total** - Down from ~15 in original plan
4. **Consistent crypto** - Same library for local and remote encryption

### Dependencies Removed
- ~~SQLCipher~~ (CGO complexity)
- ~~golang.org/x/crypto~~ (GopenPGP includes this)
- ~~Manual Argon2 setup~~ (RFC 9580 handles it)

### Testing Requirements
- **Overall coverage**: 80% minimum
- **Security-critical**: 100% coverage
- **GUI code**: 60% minimum

---

**Document Version**: 2.0 - GopenPGP Edition  
**Last Updated**: 2024-12-10  
**Maintained By**: Project team