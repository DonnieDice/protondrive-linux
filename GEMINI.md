# ProtonDrive Linux Client - Project Context

**Version**: 11.1 - SIMPLIFIED CRYPTO STACK (Proton Official Libraries)  
**Last Updated**: 2024-12-10  
**Stack**: Go + Fyne + GopenPGP (Proton Official)  
**Security Posture**: Zero-Trust, End-to-End Encrypted Everything

---

## DOCUMENT PURPOSE

This is the **architectural reference document** for ProtonDrive Linux. It defines:

- **What** we're building and **why**
- Architectural decisions and rationale  
- Technology choices and trade-offs
- Design philosophy and principles
- Zero-trust security requirements
- Testing strategy and quality standards

**This document is NOT for:**
- Task tracking → See **TASKS.md**
- Operational procedures → See **AGENTS.md**
- User documentation → See **README.md**
- Code tutorials → See **docs/**

**Read this document to understand the project. Read TASKS.md to see what needs doing.**

---

## TABLE OF CONTENTS

1. [Strategic Pivot](#strategic-pivot)
2. [Project Overview](#project-overview)
3. [Zero-Trust Privacy Philosophy](#zero-trust-privacy-philosophy)
4. [Technology Choices](#technology-choices)
5. [Architecture](#architecture)
6. [Universal Hardware Compatibility](#universal-hardware-compatibility)
7. [Key Subsystems](#key-subsystems)
8. [Testing Strategy & Philosophy](#testing-strategy--philosophy)
9. [Zero-Trust Security Model](#zero-trust-security-model)
10. [Error Handling & Resilience](#error-handling--resilience)
11. [Observability & Diagnostics](#observability--diagnostics)
12. [Dependency Management & Tech Debt](#dependency-management--tech-debt)
13. [Project Structure](#project-structure)
14. [Migration Plan](#migration-plan)
15. [Performance Targets](#performance-targets)
16. [Success Criteria](#success-criteria)
17. [Risk Register & Mitigations](#risk-register--mitigations)
18. [Accessibility & Internationalization](#accessibility--internationalization)

---

## GAP ANALYSIS SUMMARY

**Gaps identified and addressed in v10.0-v11.0:**

| Gap | Impact | Resolution |
|-----|--------|------------|
| Third-party crypto bloat | High | **v11.0**: Use Proton's official GopenPGP |
| SQLCipher CGO complexity | Medium | **v11.0**: GopenPGP handles local encryption |
| Too many dependencies | Medium | **v11.0**: Reduced from ~15 to 5-6 |
| No error handling strategy | High | Added Section 10: Error Handling & Resilience |
| Missing observability/diagnostics | Medium | Added Section 11: Observability & Diagnostics |
| No tech debt tracking | Medium | Added Section 12: Dependency Management & Tech Debt |
| Fyne GUI limitations not addressed | High | Enhanced Technology Choices with mitigation strategies |
| No graceful degradation strategy | High | Added fallback patterns throughout |
| Missing retry/backoff specifications | Medium | Added to sync engine and API communication |
| No accessibility considerations | Medium | Added Section 18: Accessibility & Internationalization |
| Keyring fallback not specified | High | Enhanced credential storage with fallback chain |
| fsnotify limitations not documented | Medium | Added polling fallback for NFS/FUSE |
| Risk register missing | Medium | Added Section 17: Risk Register & Mitigations |

---

## STRATEGIC PIVOT

### Why We're Changing

**From**: TypeScript/Electron  
**To**: Go/Fyne

### Rationale

| Concern | Electron | Go + Fyne | Impact |
|---------|----------|-----------|--------|
| Binary Size | 60-80MB | 10-20MB | 70% smaller |
| RAM Usage | 80-150MB | 20-50MB | 60-75% less |
| Startup Time | 1-2s | <500ms | 4x faster |
| Distribution | Complex | Single binary | Trivial |
| Cross-compile | Difficult | Built-in | Easy |
| ProtonDrive API | Build from scratch | Use Proton-API-Bridge | Weeks saved |

### The Deciding Factor

**Proton-API-Bridge** (Go library) already implements:
- ProtonDrive authentication (SRP protocol)
- End-to-end encryption/decryption
- API communication with rate limiting
- Error handling and retries

Building this from scratch in TypeScript would take months. In Go, we can leverage it immediately.

---

## PROJECT OVERVIEW

### What We're Building

**ProtonDrive Linux** - Native desktop client for ProtonDrive on Linux with **zero-trust, end-to-end encryption for all local storage**.

**Core Features:**
- Two-way file synchronization
- End-to-end encryption (zero-knowledge)
- **All local data encrypted (database, cache, temporary files)**
- Selective sync (choose folders)
- Conflict resolution
- Offline mode support
- Native GUI (not web-based)

**Target Users:**
- Linux users (Ubuntu, Fedora, Arch, etc.)
- Privacy-conscious individuals
- Raspberry Pi / low-resource device users
- People wanting "Dropbox experience" with ProtonDrive

### Design Goals

1. **Universal Hardware Compatibility**
   - Runs on Raspberry Pi 1 (512MB RAM) to workstations
   - Adaptive performance based on detected hardware
   - No artificial minimum requirements

2. **Zero-Trust End-to-End Privacy**
   - All encryption happens client-side
   - No plaintext ever sent to servers
   - **No plaintext stored locally (database, logs, cache)**
   - No telemetry or usage tracking
   - Verified through rigorous privacy and security testing

3. **Native Performance**
   - Fast startup (<500ms)
   - Low memory footprint (<50MB typical)
   - Efficient sync (only changed blocks)
   - Validated by comprehensive performance and unit testing

4. **Simple Distribution**
   - Single binary, no installation required
   - Works on any Linux distro
   - No dependencies to install

5. **Graceful Degradation** *(NEW)*
   - Application continues functioning when components fail
   - Fallback strategies for all critical paths
   - Clear user feedback when operating in degraded mode

---

## ZERO-TRUST PRIVACY PHILOSOPHY

### Core Principle

**User privacy is paramount. We trust nothing, encrypt everything locally.**

### Zero-Trust Requirements

**CRITICAL**: If an attacker gains access to:
- User's home directory
- Application memory dump (unlikely but possible)
- Local database files
- Cache files
- Log files
- Temporary files

They should find **ONLY encrypted data**. No plaintext filenames, no plaintext content, no metadata that reveals file structure or usage patterns.

### Threat Model

**Assumptions:**
- Attacker has read access to user's home directory (`~/.config`, `~/.local`, `~/.cache`)
- Attacker has access to all application files (database, cache, logs)
- Attacker does NOT have user's password
- Attacker does NOT have access to OS keyring (requires OS-level authentication)
- Attacker does NOT have active memory access (but may have memory dumps)

**Goal**: Even with full filesystem access, attacker cannot read filenames, file metadata, content, or usage patterns.

### What We DON'T Do

❌ **No Telemetry** - We don't track usage, features, or behavior  
❌ **No Analytics** - We don't collect statistics  
❌ **No Crash Reports** - We don't automatically send error data  
❌ **No Plaintext Logging** - Logs are encrypted or contain no sensitive data  
❌ **No Plaintext Database** - All database entries with sensitive data encrypted  
❌ **No Plaintext Cache** - All cached file content encrypted

### What We DO

✅ **Local-only state** - All data processing happens on your machine  
✅ **Encrypted sync** - Only encrypted data sent to ProtonDrive  
✅ **Encrypted local storage** - Database, cache, logs all encrypted  
✅ **Open source** - Anyone can audit the code  
✅ **Memory wiping** - Sensitive data cleared from RAM when done  
✅ **Opt-in debugging** - Users can enable verbose mode if needed

### Local Storage Encryption Requirements

**All persistent local data with sensitive information MUST be encrypted:**

| Data Type | Storage Location | Encryption Required | Key Source |
|-----------|------------------|---------------------|------------|
| File metadata (names, paths, sizes) | SQLite database | ✅ MANDATORY | User password derived key |
| File sync state | SQLite database | ✅ MANDATORY | User password derived key |
| File content cache | `~/.cache/protondrive/` | ✅ MANDATORY | User password derived key |
| Temporary files | `/tmp` or similar | ✅ MANDATORY | User password derived key |
| Debug logs (if persisted) | `~/.local/share/protondrive/logs/` | ✅ MANDATORY | User password derived key |
| Credentials/tokens | OS keyring | ✅ YES (via OS) | OS keyring encryption |
| User preferences | `~/.config/protondrive/config.json` | ⚠️ NON-SENSITIVE ONLY | N/A |

### What Can Be Stored Unencrypted

**Configuration file (`config.json`) may contain NON-SENSITIVE data only:**
- Sync directory path (e.g., `~/ProtonDrive`) - already visible in filesystem
- Performance profile selection (`low`, `standard`, `high`)
- UI preferences (theme, language, window size)
- Last sync timestamp (unix epoch, no file identifiers)
- Non-sensitive application settings

**CANNOT be stored unencrypted:**
- Filenames, file paths, or any file identifiers
- File sizes, hashes, modification times, or any file metadata
- Sync state, conflict information, or any usage data
- User credentials, tokens, or session data
- Encryption keys, passphrases, or key derivation parameters

### Development vs Production

**During Development:**
- Developers can enable debug mode locally
- Debug output goes to console (not persistent files)
- Debug output must NOT contain plaintext filenames or content
- Use encrypted file IDs or hashes in debug output
- Used only for troubleshooting during development

**In Production:**
- No logs written to disk by default
- Users can optionally enable verbose mode for support
- Even verbose mode is **opt-in**, **temporary**, and **encrypted if persisted**
- Verbose output contains no plaintext sensitive data (use file IDs only)

### Debugging Philosophy

When users encounter issues:
1. User **explicitly enables** verbose mode via CLI flag (`--verbose`)
2. Debug output goes to console (user sees it in real-time)
3. Debug output contains **encrypted references only** (file IDs, not names)
4. User can share specific output if they choose
5. If logs must be persisted for troubleshooting, they are **encrypted**
6. **Never automatic, always user-controlled**

**Example safe debug output:**
```
[INFO] Syncing file ID: a3f5b8c2d1e4 (size: 1.2MB)
[DEBUG] Upload progress: file ID a3f5b8c2d1e4: 45%
[ERROR] Conflict detected for file ID: a3f5b8c2d1e4
```

**NEVER output:**
```
[INFO] Syncing vacation_photos.zip (size: 1.2MB)  ❌ PRIVACY VIOLATION
```

### Memory Security

**Sensitive data in RAM:**
- Stored in `[]byte` slices that can be zeroed after use
- Use `crypto/subtle` for constant-time operations
- Minimize lifetime of plaintext in memory
- Force garbage collection after sensitive operations
- Zero out slices immediately with `defer` pattern

**Example:**
```go
plaintextData := decryptFile(encryptedData, key)
defer func() {
    for i := range plaintextData {
        plaintextData[i] = 0
    }
    runtime.GC()
}()
// Use plaintextData...
```

---

## TECHNOLOGY CHOICES

### Go Language

**Why Go over TypeScript/JavaScript:**

✅ **Simplicity** - Easier to learn, maintain, less boilerplate  
✅ **Performance** - Compiled, native speed, no V8 overhead  
✅ **Concurrency** - Goroutines built-in (perfect for sync operations)  
✅ **Single binary** - No runtime dependencies  
✅ **Cross-compilation** - Build for all architectures easily  
✅ **Proton's Own Libraries** - GopenPGP, go-proton-api are official Proton Go libraries  
✅ **Memory safety** - Better control over sensitive data cleanup  
✅ **Strong typing** - Catch encryption errors at compile time

❌ **Trade-off**: Smaller ecosystem than JavaScript

### Fyne GUI Framework

**Why Fyne over Qt/GTK/Electron:**

✅ **Pure Go** - Minimal C bindings, easier to build/distribute  
✅ **Cross-platform** - Same code works everywhere  
✅ **Modern look** - Material Design style  
✅ **Lightweight** - Much smaller than Electron  
✅ **Easy API** - Simple to learn and use  
✅ **Memory efficient** - Important for low-end hardware

**Known Limitations and Mitigations:**

| Limitation | Impact | Mitigation Strategy |
|------------|--------|---------------------|
| No native file dialogs | Medium | Use zenity/kdialog via exec, or custom browser |
| Layout system quirks | Medium | Use explicit sizing where needed |
| Less mature than Qt/GTK | Medium | Architecture isolates GUI for potential swap |

**Fyne Fallback Strategy:**
- If Fyne proves unsuitable, GTK4 via gotk4 is fallback
- Core sync engine and encryption are GUI-agnostic

### Cryptography: Proton's Official Libraries

**CRITICAL DECISION: Use Proton's own crypto libraries, not third-party packages.**

Proton maintains two official Go cryptography libraries that power all their apps:

#### 1. GopenPGP (`github.com/ProtonMail/gopenpgp/v3`)

**What it is:**
- High-level OpenPGP library maintained by Proton
- Powers Proton Mail, Proton Drive iOS/Android/Bridge apps
- Independently security audited (SEC Consult, 2019)
- Built on Proton's fork of golang crypto library

**What it provides:**
- Key generation (RSA, ECC Curve25519)
- Encrypt/decrypt messages and files
- Sign/verify signatures
- Session key management
- Streaming encryption for large files
- RFC 9580 (latest OpenPGP standard) support with Argon2 + AEAD

**Why use it:**
✅ **Official** - Same library Proton uses in production  
✅ **Audited** - Independent security review  
✅ **Maintained** - Active development, regular releases  
✅ **Complete** - Handles all OpenPGP operations  
✅ **Go-native** - No CGO required for core crypto  

```go
import "github.com/ProtonMail/gopenpgp/v3/crypto"
import "github.com/ProtonMail/gopenpgp/v3/profile"

// Use RFC 9580 profile (Argon2 for password protection, AEAD encryption)
pgp := crypto.PGPWithProfile(profile.RFC9580())

// Encrypt with password
encHandle, _ := pgp.Encryption().Password(password).New()
encrypted, _ := encHandle.Encrypt(plaintext)

// Decrypt with password
decHandle, _ := pgp.Decryption().Password(password).New()
decrypted, _ := decHandle.Decrypt(encrypted, crypto.Armor)
```

#### 2. go-proton-api (`github.com/ProtonMail/go-proton-api`)

**What it is:**
- Official Proton API client library
- Handles authentication (SRP protocol)
- API communication with rate limiting and retries
- Used by Proton-API-Bridge

#### 3. Proton-API-Bridge (`github.com/henrybear327/Proton-API-Bridge`)

**What it is:**
- Bridge library that combines go-proton-api with ProtonDrive-specific logic
- Handles the complex encryption scheme for Drive files
- Powers rclone's ProtonDrive backend
- MIT licensed, actively maintained

**What it provides:**
- ProtonDrive authentication
- File upload/download with E2E encryption
- Folder operations
- Link/share management
- Caching and session management

### Local Database Encryption

**For local metadata storage, two options:**

#### Option A: Application-Level Encryption with GopenPGP (Recommended)

Use GopenPGP's password-based encryption for local database:

```go
// Encrypt database content before writing
pgp := crypto.PGPWithProfile(profile.RFC9580())
encHandle, _ := pgp.Encryption().Password(userPassword).New()
encryptedData, _ := encHandle.Encrypt(dbContent)

// Store encryptedData to disk
```

**Advantages:**
- Pure Go, no CGO
- Same crypto library as remote encryption
- Consistent security model
- Simpler build process

#### Option B: SQLCipher (Alternative)

If SQL query performance on encrypted data is critical:
- Use `github.com/mutecomm/go-sqlcipher/v4`
- Requires CGO
- More complex cross-compilation

**Decision: Start with Option A (GopenPGP).** Simpler, consistent, and sufficient for our metadata storage needs. SQLCipher can be added later if query performance becomes an issue.

### Credential Storage

**Simple approach using OS keyring:**

```go
import "github.com/zalando/go-keyring"

// Store
keyring.Set("protondrive-linux", "session", encryptedSession)

// Retrieve  
session, err := keyring.Get("protondrive-linux", "session")
```

**Fallback:** If keyring unavailable, encrypt credentials file with GopenPGP using password derived from user input.

### File Watching

**Primary: fsnotify** (`github.com/fsnotify/fsnotify`)
- Standard Go file watching library
- Uses inotify on Linux

**Fallback:** Polling for NFS/FUSE filesystems where inotify doesn't work.

### Dependency Summary

**Core dependencies (minimal, official where possible):**

```go
require (
    // Proton official libraries
    github.com/ProtonMail/gopenpgp/v3      // Crypto (Proton official)
    github.com/henrybear327/Proton-API-Bridge // Drive API bridge
    
    // GUI
    fyne.io/fyne/v2                         // GUI framework
    
    // Utilities
    github.com/fsnotify/fsnotify            // File watching
    github.com/zalando/go-keyring           // Credential storage
    
    // Database (if using SQLCipher)
    // github.com/mutecomm/go-sqlcipher/v4  // Optional, adds CGO
    
    // Testing
    github.com/stretchr/testify             // Test assertions
)
```

**Total: 5-6 direct dependencies** (vs. bloated alternatives with dozens)

### Why This Approach Works

1. **Proton's crypto is battle-tested** - Millions of users, security audits
2. **Consistency** - Same encryption for local and remote data
3. **Minimal dependencies** - Less attack surface, easier maintenance
4. **Official support** - Proton maintains the core crypto libraries
5. **Pure Go where possible** - Simpler builds, better cross-compilation

---

## ARCHITECTURE

### High-Level Overview

```
┌─────────────────────────────────────────────┐
│           GUI Layer (Fyne)                  │
│  - Login screen                             │
│  - File list view (decrypted in memory)     │
│  - Settings                                 │
│  - Tray icon                                │
└─────────────┬───────────────────────────────┘
              │ Function calls
┌─────────────┴───────────────────────────────┐
│        Application Layer (Go)               │
│  - Sync manager                             │
│  - Conflict resolver                        │
│  - Performance profiler                     │
│  - Configuration                            │
│  - Local encryption layer                   │
│  - Error handling & recovery                │
└─────────────┬───────────────────────────────┘
              │ Encrypted writes
┌─────────────┴───────────────────────────────┐
│      Local Storage (Encrypted)              │
│  - SQLite database (SQLCipher)              │
│  - File cache (AES-256-GCM encrypted)       │
│  - Logs (AES-256-GCM encrypted if persisted)│
└─────────────────────────────────────────────┘

              ┌─────────────────────────────┐
              │  Proton-API-Bridge Library  │
              │  - Authentication (SRP)     │
              │  - E2E Encryption (Remote)  │
              │  - API communication        │
              │  - Rate limiting & retries  │
              └─────────────┬───────────────┘
                            │ HTTPS
              ┌─────────────┴───────────────┐
              │      ProtonDrive API        │
              └─────────────────────────────┘
```

### Key Architectural Principles

1. **Single Process** - No IPC complexity like Electron
2. **Direct Calls** - GUI calls app layer directly (no message passing)
3. **Goroutines** - Concurrent sync operations using channels
4. **Stateless UI** - GUI reflects current state, doesn't manage it
5. **Layered** - Clear separation of concerns
6. **Encrypted Everything** - All local persistent data encrypted
7. **Zero-Trust** - Assume storage is compromised, encrypt accordingly
8. **Defense in Depth** - Multiple layers of encryption and security
9. **Graceful Degradation** - Fallbacks for all critical components *(NEW)*
10. **Fail-Safe Defaults** - Secure by default, explicit opt-in for less secure *(NEW)*

### Encryption Layers

**Two independent encryption layers:**

**Layer 1: ProtonDrive E2E Encryption (Remote)**
- Purpose: Encrypt file content for transmission to ProtonDrive servers
- Encryption key: Derived from user's ProtonDrive password
- Implementation: Handled automatically by Proton-API-Bridge
- Protects against: Server-side breaches, network interception

**Layer 2: Local Storage Encryption (Local)**
- Purpose: Encrypt metadata, cache, and logs on user's device
- Encryption key: Derived from same user password (synchronized)
- Implementation: Our code using SQLCipher + AES-256-GCM
- Protects against: Local filesystem access, stolen devices, malware

---

## UNIVERSAL HARDWARE COMPATIBILITY

### Philosophy

**"If it runs Linux, it should run ProtonDrive Linux"**

No artificial minimum requirements. Application adapts to whatever hardware it finds.

### Performance Profiles

System is classified at startup into one of three profiles based on detected hardware:

#### Low-End Profile (< 4GB RAM)
- **Target**: Raspberry Pi, old laptops, embedded systems
- **Concurrency**: 1 upload, 2 downloads max
- **Cache**: 50MB (encrypted)
- **Chunk size**: 5MB
- **GUI**: Disable animations, simple rendering
- **Encryption**: Optimized for low CPU (prefer hardware AES if available)
- **Database**: WAL mode with less frequent syncs
- **Argon2id**: 32MB memory, 3 iterations, parallelism 1

#### Standard Profile (4-8GB RAM)
- **Target**: Most modern desktop/laptop systems
- **Concurrency**: 3 uploads, 5 downloads
- **Cache**: 100MB (encrypted)
- **Chunk size**: 5MB
- **GUI**: Enable animations
- **Encryption**: Balanced performance and security
- **Database**: Standard configuration
- **Argon2id**: 64MB memory, 4 iterations, parallelism 2

#### High-End Profile (> 8GB RAM)
- **Target**: Workstations, servers, high-performance systems
- **Concurrency**: 5 uploads, 10 downloads
- **Cache**: 200MB (encrypted)
- **Chunk size**: 10MB
- **GUI**: Full effects and animations
- **Encryption**: Maximum security (stronger KDF iterations if CPU allows)
- **Database**: Aggressive caching
- **Argon2id**: 128MB memory, 6 iterations, parallelism 4

### Storage Optimization

Application detects storage type (SSD vs HDD/SD card) and adjusts:

**SSD Detected:**
- More frequent writes (flash wear leveling handles it)
- Smaller write batches
- Aggressive database sync for data integrity
- Real-time file watching

**HDD/SD Card Detected:**
- Batch writes together to reduce seeks
- Larger buffers
- Write-Ahead Logging (WAL) mode
- Optimize for sequential writes
- Less frequent polling (preserve SD card lifespan on Raspberry Pi)

### Multi-Architecture Support

Build targets with native binaries:
- **x86_64** (amd64) - Intel/AMD 64-bit, most desktops/laptops
- **ARM64** (aarch64) - Raspberry Pi 3+, modern ARM devices
- **ARMv7** (armhf) - Raspberry Pi 2, older 32-bit ARM
- **ARMv6** (armel) - Raspberry Pi 1, very old ARM (if feasible)

Each architecture gets optimized binary through Go's cross-compilation. AES-NI and other CPU features detected at runtime.

---

## KEY SUBSYSTEMS

### 1. Sync Engine

**Responsibilities:**
- Watch local filesystem for changes (fsnotify)
- Detect remote changes via ProtonDrive API polling
- Queue uploads/downloads based on performance profile
- Handle resumable transfers with chunking
- Manage conflicts with user-defined strategies
- **Encrypt all metadata before storing in database**

**Design:**
- Worker pool pattern with goroutines
- Buffered channels for upload/download queues
- Semaphores to limit concurrency based on profile
- Context for graceful shutdown
- **Encryption wrapper for all database writes**
- **Cache all file content encrypted**

**Key Operations:**
- Local change detected → Hash file → Check if changed → Encrypt → Upload
- Remote change detected → Download encrypted → Decrypt → Write to disk
- Conflict detected → Apply resolution strategy → Log to encrypted database

**File Watching Strategy:** *(ENHANCED)*

```go
// Primary: fsnotify (inotify on Linux)
// Fallback: Polling for NFS/FUSE/unsupported filesystems

type FileWatcher interface {
    Watch(path string) error
    Events() <-chan FileEvent
    Errors() <-chan error
    Close() error
}

// Automatic fallback chain:
// 1. Try fsnotify (inotify)
// 2. If "no space left on device" or NFS detected → switch to polling
// 3. Polling interval: configurable, default 30s for HDD, 10s for SSD
```

**fsnotify Limitations and Mitigations:**
- **Limit**: `fs.inotify.max_user_watches` (default ~124K on Linux)
- **Mitigation**: Guide users to increase limit, or fall back to polling
- **NFS/FUSE**: Not supported by inotify → automatic polling fallback
- **Recursive watching**: Not built-in → implement manual directory tree walking

### 2. Conflict Resolver

**Strategies:**
- **Server wins** - Overwrite local with remote version
- **Local wins** - Overwrite remote with local version
- **Keep both** - Rename one with timestamp suffix
- **Manual** - Prompt user to choose (GUI dialog)

**Design:**
- Detect conflicts by comparing timestamps + content hashes
- Apply strategy based on user preference (stored in config)
- **Log conflict resolutions to encrypted database**
- Display filenames in GUI only (decrypted in memory, never logged)
- Support conflict history for user review

**Conflict Detection:**
```
Local modified time > Last sync time AND
Remote modified time > Last sync time AND
Content hash differs
→ CONFLICT
```

### 3. Configuration Manager

**Responsibilities:**
- Load/save user preferences
- Detect system capabilities (RAM, CPU, storage type)
- Select appropriate performance profile automatically
- Validate configuration on load
- **Manage encryption keys securely**
- Store non-sensitive settings only

**Storage Locations:**
- Config file: `~/.config/protondrive-linux/config.json` (non-sensitive only)
- Credentials: OS keyring via Proton-API-Bridge
- Encryption key: OS keyring (never written to disk in plaintext)
- State database: `~/.local/share/protondrive-linux/state.db` (encrypted with SQLCipher)

**Configuration File Contents (Unencrypted):**
```json
{
  "sync_directory": "/home/user/ProtonDrive",
  "performance_profile": "auto",
  "ui_theme": "dark",
  "language": "en",
  "last_sync_timestamp": 1701234567,
  "kdf_algorithm": "argon2id",
  "schema_version": 1
}
```

**NEVER in configuration file:**
- Filenames, paths to specific files
- File metadata, sizes, hashes
- Credentials, tokens, encryption keys
- Sync state for specific files

### 4. Local Encryption Layer

**CRITICAL SUBSYSTEM FOR ZERO-TRUST PRIVACY**

**Approach: Use GopenPGP for consistency with ProtonDrive encryption**

**Responsibilities:**
- Derive encryption key from user password (RFC 9580 profile uses Argon2)
- Store encrypted session in OS keyring
- Encrypt/decrypt local metadata files
- Encrypt/decrypt cache files
- Securely wipe keys and plaintext from memory

**Key Management with GopenPGP:**
```go
import (
    "github.com/ProtonMail/gopenpgp/v3/crypto"
    "github.com/ProtonMail/gopenpgp/v3/profile"
)

// RFC 9580 profile automatically uses Argon2 for password-based encryption
pgp := crypto.PGPWithProfile(profile.RFC9580())

// Encrypt local data
func encryptLocalData(data []byte, password []byte) ([]byte, error) {
    encHandle, err := pgp.Encryption().Password(password).New()
    if err != nil {
        return nil, err
    }
    message, err := encHandle.Encrypt(data)
    if err != nil {
        return nil, err
    }
    return message.Bytes(), nil
}

// Decrypt local data
func decryptLocalData(encrypted []byte, password []byte) ([]byte, error) {
    decHandle, err := pgp.Decryption().Password(password).New()
    if err != nil {
        return nil, err
    }
    result, err := decHandle.Decrypt(encrypted, crypto.Bytes)
    if err != nil {
        return nil, err
    }
    return result.Bytes(), nil
}
```

**Why this works:**
- RFC 9580 profile uses **Argon2** for key derivation automatically
- Uses **AES-256 with OCB mode (AEAD)** for encryption
- Same library used for ProtonDrive remote encryption
- No separate KDF configuration needed - GopenPGP handles it
- Security-audited implementation

**Local Storage Structure:**
```
~/.local/share/protondrive-linux/
├── metadata.gpg          # Encrypted file metadata (JSON encrypted with GopenPGP)
├── sync_state.gpg        # Encrypted sync state
└── salt                  # Public salt (needed for key derivation)

~/.cache/protondrive-linux/
├── a3f5b8c2d1e4.gpg     # Encrypted cache file (filename is SHA256 of path)
└── ...

~/.config/protondrive-linux/
└── config.json          # Non-sensitive settings only (sync path, theme, etc.)
```

**Cache File Encryption:**
```
Original filename: vacation_photos.zip
Cache filename: ~/.cache/protondrive/a3f5b8c2d1e4.gpg
(Filename is SHA256 hash of original path, content is GopenPGP encrypted)
```

**Design Principles:**
- Use same password as ProtonDrive account (single password for user)
- GopenPGP handles Argon2 key derivation internally
- Key cached in OS keyring (encrypted by OS)
- All persistent data encrypted with GopenPGP
- Authenticated encryption (AEAD) prevents tampering

### 5. Credential Storage *(ENHANCED)*

**Primary: OS Secret Service (D-Bus)**

Using `github.com/zalando/go-keyring` for cross-platform keyring access:

```go
import "github.com/zalando/go-keyring"

// Store credential
err := keyring.Set("protondrive-linux", "master-key", base64Key)

// Retrieve credential
key, err := keyring.Get("protondrive-linux", "master-key")

// Delete credential
err := keyring.Delete("protondrive-linux", "master-key")
```

**Fallback Chain:** *(NEW)*

```
1. Secret Service D-Bus API (GNOME Keyring, KWallet, KeePassXC)
   ↓ (if unavailable)
2. File-based encrypted store (~/.config/protondrive-linux/keystore.enc)
   - Encrypted with key derived from password
   - User warned about reduced security
   ↓ (if password not cached)
3. Prompt user for password on each startup
   - Least convenient but most secure
```

**Keyring Requirements:**
- Secret Service daemon must be running (gnome-keyring-daemon, KWallet, etc.)
- D-Bus session bus must be available
- User must be logged into GUI session

**Handling Keyring Unavailability:**
```go
func getKeyringWithFallback() (Keyring, error) {
    // Try Secret Service first
    if keyring.Available() {
        return NewSecretServiceKeyring(), nil
    }
    
    // Fallback to encrypted file
    log.Warn("Secret Service unavailable, using encrypted file storage")
    return NewEncryptedFileKeyring(), nil
}
```

### 6. Performance Profiler

**Responsibilities:**
- Detect total RAM, available RAM, CPU cores
- Identify CPU architecture (x86_64, ARM, etc.)
- Test storage type (SSD vs HDD via I/O patterns)
- Detect hardware AES support (AES-NI on x86, crypto extensions on ARM)
- Select appropriate performance profile automatically
- Adjust concurrency limits dynamically based on load
- **Optimize encryption based on CPU capabilities**

**Design:**
- Run detection at startup (adds <50ms to startup time)
- Re-evaluate if performance degrades (high CPU/memory usage)
- Can be manually overridden in settings
- Detect hardware AES support for 3-5x faster encryption
- Log profile selection (non-sensitive) for troubleshooting

**Hardware Detection:**
- RAM: Read `/proc/meminfo` on Linux
- CPU: Read `/proc/cpuinfo` for cores and features
- Storage: Perform small I/O test to determine SSD vs HDD
- AES-NI: Check CPU flags for `aes` support

### 7. GUI Layer

**Responsibilities:**
- Display sync status (syncing, paused, error)
- Show file list with icons and status
- Handle user interactions (clicks, settings changes)
- System tray integration with status icon
- Desktop notifications for sync events
- **Never persist sensitive data from GUI**
- **Decrypt filenames for display only, never log**

**Design:**
- Fyne framework for native widgets (Material Design)
- Reactive UI (reflects application state from app layer)
- Minimal state in GUI layer (stateless where possible)
- Calls app layer for all operations (sync, settings, etc.)
- **Filenames decrypted in memory for display, immediately discarded**
- **No logging of GUI events that contain filenames**

**GUI Components:**
- Login screen (username/password entry)
- Main window (file list, sync status)
- Settings panel (preferences, profile selection)
- Tray icon (quick status, pause/resume)
- Notifications (sync complete, conflicts, errors)

**Privacy in GUI:**
- File list populated from encrypted database
- Filenames decrypted in memory for display
- When logging GUI events, use file IDs only
- Never persist GUI state with filenames

---

## TESTING STRATEGY & PHILOSOPHY

### Core Principle

**Comprehensive testing is fundamental to delivering on our promises of privacy, performance, and reliability.**

Testing must validate:
1. Functional correctness
2. Privacy guarantees (no plaintext leakage)
3. Performance targets
4. Security requirements
5. Cross-platform compatibility

### Types of Testing

#### 1. Unit Tests (Foundation)

**Purpose**: Verify correctness of individual functions, methods, and components in isolation.

**Coverage Requirements:**
- **Overall Codebase**: 80% minimum for all Go packages
- **Security-Critical Components**: 100% coverage (encryption, key management, authentication)
- **GUI Code**: 60% minimum (acknowledging difficulty of UI testing)

**Testing Techniques:**
- Extensive mocking with `testify/mock`
- Dependency injection to isolate units
- Table-driven tests for comprehensive input coverage
- Benchmark tests for performance-critical code
- Fuzzing for encryption/parsing functions

**Key Unit Test Areas:**

**a) Local Encryption Layer (100% coverage required)**
```
Tests for internal/encryption/:
- TestKeyDerivation: Verify Argon2id produces consistent keys
- TestKeyDerivationFallback: Verify PBKDF2 fallback works
- TestDatabaseEncryption: Verify SQLCipher initialization and access
- TestCacheEncryption: Verify file encryption/decryption correctness
- TestMemoryWiping: Verify sensitive data is zeroed after use
- TestKeyRotation: Verify key rotation without data loss
- BenchmarkEncryption: Ensure encryption performance targets met
- FuzzEncryptDecrypt: Fuzz test for edge cases
```

**b) Sync Engine**
```
Tests for internal/sync/:
- TestFileWatcher: Mock fsnotify, verify change detection
- TestFileWatcherFallback: Verify polling fallback works
- TestUploadQueue: Verify worker pool behavior, concurrency limits
- TestDownloadQueue: Verify resumable downloads, chunking
- TestConflictDetection: Various conflict scenarios
- TestMetadataStorage: Verify all metadata encrypted before storage
- BenchmarkHashingSpeed: Verify >100 MB/s target met
```

**c) Configuration Manager**
```
Tests for internal/config/:
- TestConfigLoad: Valid and invalid config files
- TestProfileDetection: Mock hardware detection, verify profile selection
- TestNonSensitiveOnly: Verify no sensitive data in config.json
- TestKeyringIntegration: Mock OS keyring access
- TestKeyringFallback: Verify encrypted file fallback
```

**d) Conflict Resolver**
```
Tests for internal/conflict/:
- TestServerWins: Verify server wins strategy
- TestLocalWins: Verify local wins strategy
- TestKeepBoth: Verify rename logic
- TestManualResolution: Verify user prompt behavior
```

**e) Performance Profiler**
```
Tests for internal/profile/:
- TestRAMDetection: Mock /proc/meminfo parsing
- TestCPUDetection: Mock /proc/cpuinfo parsing
- TestStorageTypeDetection: Mock I/O patterns
- TestAESNIDetection: Verify hardware AES detection
```

**f) GUI Layer**
```
Tests for internal/gui/:
- TestLoginScreen: Verify input validation, error display
- TestFileListDisplay: Verify list population, sorting
- TestTrayIcon: Verify status updates
- TestSettings: Verify preference persistence
```

**Example Unit Test Structure:**
```go
package encryption

import (
    "testing"
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/mock"
)

func TestKeyDerivationArgon2id(t *testing.T) {
    tests := []struct {
        name     string
        password string
        salt     []byte
        memory   uint32
        iterations uint32
        parallelism uint8
    }{
        {"standard profile", "testpass123", []byte("randomsalt16byte"), 64*1024, 4, 2},
        {"low-end profile", "testpass123", []byte("randomsalt16byte"), 32*1024, 3, 1},
        {"high-end profile", "testpass123", []byte("randomsalt16byte"), 128*1024, 6, 4},
    }
    
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            key := deriveKeyArgon2id(tt.password, tt.salt, tt.memory, tt.iterations, tt.parallelism)
            assert.Len(t, key, 32, "Key should be 256 bits")
            
            // Verify deterministic
            key2 := deriveKeyArgon2id(tt.password, tt.salt, tt.memory, tt.iterations, tt.parallelism)
            assert.Equal(t, key, key2, "Same inputs should produce same key")
        })
    }
}

func TestCacheEncryption(t *testing.T) {
    plaintext := []byte("sensitive file content")
    key := make([]byte, 32) // 256-bit key
    rand.Read(key)
    
    // Encrypt
    encrypted, err := encryptCache(plaintext, key)
    assert.NoError(t, err)
    assert.NotEqual(t, plaintext, encrypted, "Encrypted data should differ from plaintext")
    
    // Decrypt
    decrypted, err := decryptCache(encrypted, key)
    assert.NoError(t, err)
    assert.Equal(t, plaintext, decrypted, "Decrypted data should match original")
}

func TestMemoryWiping(t *testing.T) {
    sensitive := []byte("password123")
    original := make([]byte, len(sensitive))
    copy(original, sensitive)
    
    // Wipe memory
    wipeSlice(sensitive)
    
    // Verify all bytes are zero
    for i, b := range sensitive {
        assert.Equal(t, byte(0), b, "Byte %d not wiped", i)
    }
    assert.NotEqual(t, original, sensitive, "Memory should be wiped")
}
```

#### 2. Integration Tests

**Purpose**: Verify different modules interact correctly end-to-end.

**Key Integration Tests:**

**a) Database + Encryption Integration**
```
- Test full cycle: Create database → Encrypt data → Store → Retrieve → Decrypt
- Verify encrypted database cannot be opened without key
- Test wrong key fails gracefully
- Test concurrent access with encryption
```

**b) Sync Engine + Proton-API-Bridge Integration**
```
- Use mock HTTP server to simulate ProtonDrive API
- Test full upload flow: Local file → Hash → Encrypt → API call
- Test full download flow: API call → Decrypt → Write to disk
- Test error handling and retries
```

**c) GUI + Application Layer Integration**
```
- Test login flow: GUI input → Auth → Success/Error display
- Test file list: Database query → Decrypt → Display in GUI
- Test settings: GUI change → Config save → Reload
```

**d) Cache + Encryption Integration**
```
- Test cache write: Plaintext → Encrypt → Write to disk
- Test cache read: Read from disk → Decrypt → Verify plaintext
- Verify cache filenames are hashed (no plaintext names)
```

#### 3. End-to-End (E2E) / UI Tests

**Purpose**: Simulate real user workflows from start to finish.

**E2E Test Scenarios:**

**a) First-Time User Flow**
```
1. Launch application
2. No config exists
3. Show login screen
4. Enter credentials
5. Authenticate with ProtonDrive
6. Select sync directory
7. Begin initial sync
8. Verify files synchronized
9. Verify database encrypted
```

**b) Sync Workflow**
```
1. Application running
2. User creates new file locally
3. Sync engine detects change
4. File uploaded to ProtonDrive
5. Metadata stored in encrypted database
6. Verify remote file matches local
```

**c) Conflict Resolution**
```
1. Same file modified locally and remotely
2. Conflict detected on next sync
3. User notified via GUI notification
4. User chooses resolution strategy
5. Resolution applied and logged (encrypted)
6. Verify correct file version kept
```

**d) Offline Mode**
```
1. Application running with internet connection
2. Network disconnected
3. User makes local changes
4. Changes queued for sync
5. Network restored
6. Queued changes synchronized
7. Verify no data loss
```

**e) Graceful Degradation** *(NEW)*
```
1. Application running
2. Keyring becomes unavailable
3. Application switches to encrypted file storage
4. User notified of degraded mode
5. Verify functionality continues
6. Keyring restored
7. Application returns to normal mode
```

#### 4. Security & Privacy Tests

**Purpose**: Verify zero-trust requirements are met, no plaintext leakage.

**Critical Security Tests:**

**a) Database Encryption Verification**
```go
func TestDatabaseIsEncrypted(t *testing.T) {
    // Create database with test data
    db := createTestDatabase()
    storeTestFile(db, "secret_document.pdf", metadata)
    db.Close()
    
    // Try to open database without key
    rawDB, err := sql.Open("sqlite3", dbPath)
    assert.NoError(t, err)
    
    // Should not be able to read any data
    rows, err := rawDB.Query("SELECT * FROM files")
    assert.Error(t, err, "Should fail to query encrypted database")
    
    // Open raw database file
    fileBytes, _ := ioutil.ReadFile(dbPath)
    
    // Verify no plaintext filenames in raw bytes
    assert.NotContains(t, string(fileBytes), "secret_document.pdf")
    assert.NotContains(t, string(fileBytes), "vacation")
    assert.NotContains(t, string(fileBytes), "photo")
}
```

**b) Cache Encryption Verification**
```go
func TestCacheFilesEncrypted(t *testing.T) {
    // Create cached file
    plaintext := []byte("This is sensitive file content")
    cacheFile := cacheEncryptedFile("document.txt", plaintext)
    
    // Read raw cache file
    rawBytes, _ := ioutil.ReadFile(cacheFile)
    
    // Verify no plaintext content
    assert.NotContains(t, string(rawBytes), "sensitive")
    assert.NotContains(t, string(rawBytes), "content")
    
    // Verify filename is hashed, not original
    assert.NotContains(t, cacheFile, "document.txt")
}
```

**c) Log Content Verification**
```go
func TestLogsContainNoPlaintext(t *testing.T) {
    // Enable logging
    enableVerboseMode()
    
    // Perform operations with files
    syncFile("my_private_file.txt")
    resolveConflict("secret_document.pdf")
    
    // Read log output
    logContent := getLogOutput()
    
    // Verify no plaintext filenames
    assert.NotContains(t, logContent, "my_private_file")
    assert.NotContains(t, logContent, "secret_document")
    
    // Verify file IDs used instead
    assert.Contains(t, logContent, "file ID:")
}
```

**d) Memory Wiping Verification**
```go
func TestSensitiveDataWipedFromMemory(t *testing.T) {
    // Allocate sensitive data
    password := []byte("super_secret_password")
    
    // Use password
    usePassword(password)
    
    // Verify memory wiped
    for _, b := range password {
        assert.Equal(t, byte(0), b, "Password not wiped from memory")
    }
}
```

**e) Configuration File Content Verification**
```go
func TestConfigContainsNoSensitiveData(t *testing.T) {
    // Create config with sensitive operations
    config := createConfig()
    config.addSyncedFile("passwords.txt")
    config.save()
    
    // Read raw config file
    configBytes, _ := ioutil.ReadFile(configPath)
    configContent := string(configBytes)
    
    // Verify no sensitive data
    assert.NotContains(t, configContent, "passwords.txt")
    assert.NotContains(t, configContent, "password")
    assert.NotContains(t, configContent, "token")
    assert.NotContains(t, configContent, "credential")
    
    // Verify only non-sensitive data present
    assert.Contains(t, configContent, "sync_directory")
    assert.Contains(t, configContent, "performance_profile")
}
```

#### 5. Performance Tests

**Purpose**: Validate performance targets are met across all hardware profiles.

**Performance Test Categories:**

**a) Startup Time Benchmarks**
```go
func BenchmarkColdStart(b *testing.B) {
    for i := 0; i < b.N; i++ {
        start := time.Now()
        app := launchApplication()
        elapsed := time.Since(start)
        app.Shutdown()
        
        assert.Less(b, elapsed, 500*time.Millisecond, "Cold start too slow")
    }
}
```

**b) Memory Usage Tests**
```go
func TestMemoryUsageLowEnd(t *testing.T) {
    app := launchWithProfile(ProfileLowEnd)
    time.Sleep(5 * time.Second)
    
    var m runtime.MemStats
    runtime.ReadMemStats(&m)
    memoryMB := m.Alloc / 1024 / 1024
    
    assert.Less(t, memoryMB, uint64(30), "Low-end profile exceeds 30MB")
}
```

**c) Encryption Performance**
```go
func BenchmarkFileEncryption(b *testing.B) {
    data := make([]byte, 10*1024*1024) // 10MB file
    key := make([]byte, 32)
    rand.Read(data)
    rand.Read(key)
    
    b.ResetTimer()
    for i := 0; i < b.N; i++ {
        encrypted, _ := encryptCache(data, key)
        _ = encrypted
    }
    
    // Should achieve >100 MB/s with AES-NI
    mbPerSec := float64(len(data)*b.N) / b.Elapsed().Seconds() / 1024 / 1024
    assert.Greater(b, mbPerSec, 100.0, "Encryption too slow")
}
```

#### 6. Cross-Platform Tests

**Purpose**: Ensure application works correctly on all target platforms.

**Platform Test Matrix:**
- **x86_64**: Ubuntu 22.04, Fedora 39, Arch Linux
- **ARM64**: Raspberry Pi OS (64-bit)
- **ARMv7**: Raspberry Pi OS (32-bit)
- **ARMv6**: Raspberry Pi OS (legacy)

### Testing Principles & Best Practices

**Shift Left**: Identify and fix defects early through comprehensive unit testing before integration.

**Automated First**: Prioritize automated tests over manual testing for consistent, repeatable validation.

**Reliability**: Tests must be stable, deterministic, and provide consistent results across environments.

**Maintainability**: Tests should be clear, readable, and easy to maintain as codebase evolves.

**Privacy Verification**: Every feature that handles sensitive data must have corresponding privacy tests.

**Performance Validation**: All performance targets validated through benchmarks and profiling.

**Continuous Testing**: Tests run automatically on every commit via CI/CD pipeline.

---

## ERROR HANDLING & RESILIENCE *(NEW SECTION)*

### Error Handling Philosophy

**Principle**: Errors are expected. Handle them gracefully, never crash, always inform the user.

### Error Categories

| Category | Examples | Handling Strategy |
|----------|----------|-------------------|
| **Transient** | Network timeout, API rate limit | Retry with exponential backoff |
| **Recoverable** | Keyring unavailable, disk full | Fallback + user notification |
| **Permanent** | Invalid credentials, corrupt database | Clear error message + recovery steps |
| **Fatal** | Encryption key compromised | Secure shutdown + data protection |

### Retry Strategy

**Exponential Backoff with Jitter:**

```go
type RetryConfig struct {
    MaxAttempts     int           // Default: 5
    InitialDelay    time.Duration // Default: 1s
    MaxDelay        time.Duration // Default: 30s
    Multiplier      float64       // Default: 2.0
    JitterFraction  float64       // Default: 0.1
}

func (c *RetryConfig) NextDelay(attempt int) time.Duration {
    delay := float64(c.InitialDelay) * math.Pow(c.Multiplier, float64(attempt))
    if delay > float64(c.MaxDelay) {
        delay = float64(c.MaxDelay)
    }
    jitter := delay * c.JitterFraction * (rand.Float64()*2 - 1)
    return time.Duration(delay + jitter)
}
```

**Retry Scenarios:**
- API 429 (Too Many Requests): Respect `Retry-After` header
- API 5xx: Retry with backoff
- Network timeout: Retry immediately once, then backoff
- Database locked: Retry with short backoff

### Circuit Breaker Pattern

**Prevent cascading failures:**

```go
type CircuitBreaker struct {
    FailureThreshold int           // Default: 5
    ResetTimeout     time.Duration // Default: 60s
    State            CircuitState  // Closed, Open, HalfOpen
}

// States:
// Closed: Normal operation, requests pass through
// Open: Failures exceeded threshold, requests fail fast
// HalfOpen: After timeout, allow one request to test recovery
```

### Graceful Degradation

**Feature Fallback Chain:**

```
Full Functionality
    ↓ (keyring unavailable)
Encrypted File Storage Mode
    ↓ (filesystem issues)
Read-Only Mode (view cached files)
    ↓ (cache corrupted)
Login-Only Mode (re-authenticate to recover)
```

**User Communication:**
- Clear banner showing degraded mode
- Explanation of what's not working
- Steps to restore full functionality

### Error Reporting (Privacy-Safe)

**What we include in error reports:**
- Error code and category
- Component that failed
- Timestamp
- Performance profile
- Architecture (x86_64, ARM, etc.)
- OS version

**What we NEVER include:**
- Filenames or paths
- File contents
- User credentials
- Encryption keys
- Any PII

---

## OBSERVABILITY & DIAGNOSTICS *(NEW SECTION)*

### Logging Architecture

**Log Levels:**
- **ERROR**: Something failed, may need user action
- **WARN**: Something unexpected, but recovered
- **INFO**: Normal operation milestones
- **DEBUG**: Detailed troubleshooting (opt-in only)
- **TRACE**: Extremely verbose (developer mode only)

**Default Production**: INFO and above, console only (no file persistence)

**Structured Logging:**

```go
type LogEntry struct {
    Timestamp   time.Time
    Level       LogLevel
    Component   string      // e.g., "sync", "encryption", "gui"
    Operation   string      // e.g., "upload", "decrypt"
    FileID      string      // Encrypted file identifier, NEVER filename
    DurationMs  int64       // Operation duration
    Error       string      // Error message (sanitized)
    TraceID     string      // For correlating related operations
}
```

### Metrics (Internal Only)

**Collected metrics (never transmitted):**
- Sync operations per minute
- Average upload/download time
- Cache hit rate
- Memory usage
- CPU usage during sync
- Encryption throughput

**Metrics Storage:**
- In-memory only (not persisted)
- Rolling window (last hour)
- Available via debug endpoint or CLI flag

### Health Checks

**Components monitored:**
- Database connectivity
- Keyring availability
- Network connectivity
- Disk space
- ProtonDrive API availability

**Health Check Endpoint (CLI):**

```bash
$ protondrive-linux --health
{
  "status": "healthy",
  "components": {
    "database": "ok",
    "keyring": "ok",
    "network": "ok",
    "disk_space": "ok",
    "api": "ok"
  },
  "last_sync": "2024-12-10T12:34:56Z",
  "uptime": "3h 24m"
}
```

### Diagnostic Mode

**Enable with:**
```bash
$ protondrive-linux --verbose --diagnostic
```

**Diagnostic Output:**
- Extended logging (DEBUG level)
- Performance metrics
- Component health
- Configuration dump (sensitive data redacted)
- System information

**Privacy Guarantee:**
- Diagnostic output NEVER contains filenames
- User must explicitly enable
- Output goes to console only
- User controls what they share

---

## DEPENDENCY MANAGEMENT & TECH DEBT *(NEW SECTION)*

### Dependency Inventory

**Minimal, official-first approach:**

| Dependency | Version | Purpose | License | Risk |
|------------|---------|---------|---------|------|
| **GopenPGP** | v3.x | Cryptography (Proton official) | MIT | Very Low (Proton maintained, audited) |
| **Proton-API-Bridge** | latest | ProtonDrive API | MIT | Low (powers rclone, actively maintained) |
| Fyne | v2.x | GUI framework | BSD-3 | Medium (limitations documented) |
| fsnotify | latest | File watching | BSD-3 | Low (mature library) |
| go-keyring | latest | Credential storage | MIT | Low (Zalando maintained) |
| testify | latest | Testing | MIT | Low |

**Optional (only if SQL query performance needed):**
| go-sqlcipher | v4 | Encrypted database | BSD-3 | Low (adds CGO complexity) |

**Total: 5-6 dependencies** (vs. typical 15-20 for similar projects)

### Dependency Update Policy

**Schedule:**
- **Security patches**: Immediate (within 24 hours)
- **Minor updates**: Monthly review
- **Major updates**: Quarterly evaluation with testing

**Update Process:**
1. Review changelog for breaking changes
2. Run full test suite
3. Test on all target platforms
4. Update dependency inventory
5. Document any migration steps

### Tech Debt Tracking

**Current Tech Debt:**

| Item | Priority | Impact | Effort | Notes |
|------|----------|--------|--------|-------|
| Fyne table widget limitations | Medium | Custom implementation needed | 2 weeks | May need fork |
| SQLCipher CGO dependency | Low | Complicates cross-compilation | N/A | Acceptable trade-off |
| No recursive fsnotify | Medium | Manual directory walking | 1 week | Upstream issue #18 |
| Argon2id hardware optimization | Low | Could be faster on ARM | 3 days | Future enhancement |

**Tech Debt Guidelines:**
- Document all known limitations
- Track in TECH_DEBT.md
- Review quarterly
- Prioritize security-related debt

### Go Module Best Practices

```go
// go.mod
module github.com/yourorg/protondrive-linux

go 1.21

require (
    github.com/henrybear327/Proton-API-Bridge v1.0.0
    fyne.io/fyne/v2 v2.4.0
    github.com/mutecomm/go-sqlcipher/v4 v4.4.2
    github.com/fsnotify/fsnotify v1.7.0
    github.com/zalando/go-keyring v0.2.3
    github.com/stretchr/testify v1.8.4
    golang.org/x/crypto v0.16.0
)
```

**Commands:**
```bash
# Update all dependencies
go get -u ./...

# Update specific dependency
go get -u github.com/fsnotify/fsnotify

# Audit for vulnerabilities
go install golang.org/x/vuln/cmd/govulncheck@latest
govulncheck ./...

# Verify dependencies
go mod verify
```

---

## ZERO-TRUST SECURITY MODEL

### Threat Model Summary

**Attacker Capabilities:**
- Full read access to user's filesystem
- Access to application files (database, cache, logs, config)
- Potentially access to memory dumps (less likely)

**Attacker Limitations:**
- Does NOT have user's password
- Does NOT have access to OS keyring (requires OS authentication)
- Does NOT have active memory access (running process)

**Security Goal:** Even with filesystem access, attacker finds only encrypted data. No plaintext filenames, content, or metadata.

### Defense Layers

**Layer 1: ProtonDrive E2E Encryption (Remote)**
- **Purpose**: Protect data in transit and on ProtonDrive servers
- **Implementation**: Proton-API-Bridge handles this automatically
- **Key Management**: Key derived from ProtonDrive password
- **Algorithms**: AES-256, RSA-4096 (as per ProtonDrive spec)

**Layer 2: Local Database Encryption (SQLCipher)**
- **Purpose**: Protect file metadata on local disk
- **Implementation**: SQLCipher with AES-256-GCM
- **Key Storage**: OS keyring (with encrypted file fallback)
- **Database**: All tables encrypted at page level

**Layer 3: Cache Encryption (AES-256-GCM)**
- **Purpose**: Protect cached file content
- **Implementation**: Custom encryption using Go crypto libraries
- **Filename Obfuscation**: SHA256 hash of original path
- **Key Storage**: OS keyring (same as database key)

**Layer 4: Memory Security**
- **Purpose**: Minimize plaintext exposure in RAM
- **Implementation**: Immediate zeroing of sensitive byte slices
- **Tools**: `defer` for cleanup, `runtime.GC()` for forced collection
- **Constant-time Operations**: Use `crypto/subtle` to prevent timing attacks

### Key Management

**Using GopenPGP (RFC 9580 Profile):**

The RFC 9580 profile in GopenPGP automatically handles:
- **Argon2** for password-to-key derivation
- **AES-256-OCB (AEAD)** for encryption
- **Proper salt handling**

```
User Password (entered once at login)
    ↓
GopenPGP RFC 9580 Profile
(Internally uses Argon2 + AEAD)
    ↓
Encrypted data written to disk
    ↓
Session info stored in OS Keyring
    ↓
On restart: retrieve from keyring or re-enter password
```

**Salt Storage:**
- Salt stored alongside encrypted data (standard OpenPGP format)
- GopenPGP handles salt management automatically
- No manual salt configuration needed

**Session Management:**
- Encrypted session tokens stored in OS keyring
- If keyring unavailable, fall back to password prompt each session
- Session wiped from memory at shutdown

### Network Security

**TLS/HTTPS:**
- All API communication over HTTPS (TLS 1.3)
- Certificate pinning via Proton-API-Bridge
- No plaintext ever transmitted over network
- Only encrypted ProtonDrive payloads sent

**API Communication:**
- ProtonDrive receives only encrypted file content
- ProtonDrive receives encrypted metadata (as per their E2E spec)
- No plaintext filenames sent to servers
- Rate limiting and retry logic in Proton-API-Bridge

---

## PROJECT STRUCTURE

```
protondrive-linux/
├── go.mod, go.sum              # Dependency management
├── main.go                     # Application entry point
│
├── cmd/                        # Command-line tools
│   └── protondrive/
│       └── main.go             # CLI interface
│
├── internal/                   # Private application code
│   ├── encryption/             # Local encryption layer
│   │   ├── keys.go            # Key derivation (Argon2id, PBKDF2)
│   │   ├── database.go        # SQLCipher wrapper
│   │   ├── cache.go           # Cache file encryption
│   │   ├── memory.go          # Memory security utilities
│   │   └── *_test.go          # Comprehensive unit tests
│   ├── sync/                   # Sync engine
│   │   ├── engine.go          # Main sync logic
│   │   ├── watcher.go         # File system watcher (fsnotify + polling)
│   │   ├── uploader.go        # Upload worker pool
│   │   ├── downloader.go      # Download worker pool
│   │   ├── retry.go           # Retry logic with backoff
│   │   └── *_test.go
│   ├── gui/                    # Fyne GUI components
│   │   ├── login.go           # Login screen
│   │   ├── mainwindow.go      # Main application window
│   │   ├── settings.go        # Settings panel
│   │   ├── tray.go            # System tray icon
│   │   └── *_test.go
│   ├── config/                 # Configuration management
│   │   ├── config.go          # Config file handling
│   │   ├── keyring.go         # OS keyring integration
│   │   ├── fallback.go        # Encrypted file fallback
│   │   └── *_test.go
│   ├── client/                 # Proton-API-Bridge wrapper
│   │   ├── client.go          # API client
│   │   ├── auth.go            # Authentication
│   │   ├── ratelimit.go       # Rate limiting
│   │   └── *_test.go
│   ├── storage/                # Database layer
│   │   ├── db.go              # Database initialization
│   │   ├── files.go           # File metadata operations
│   │   ├── conflicts.go       # Conflict history
│   │   ├── migration.go       # Schema migrations
│   │   └── *_test.go
│   ├── profile/                # Performance profiling
│   │   ├── detector.go        # Hardware detection
│   │   ├── profiles.go        # Profile definitions
│   │   └── *_test.go
│   ├── conflict/               # Conflict resolution
│   │   ├── resolver.go        # Resolution strategies
│   │   ├── detector.go        # Conflict detection
│   │   └── *_test.go
│   ├── errors/                 # Error handling (NEW)
│   │   ├── errors.go          # Custom error types
│   │   ├── recovery.go        # Recovery strategies
│   │   ├── circuit.go         # Circuit breaker
│   │   └── *_test.go
│   └── observability/          # Logging & diagnostics (NEW)
│       ├── logger.go          # Structured logging
│       ├── metrics.go         # Internal metrics
│       ├── health.go          # Health checks
│       └── *_test.go
│
├── pkg/                        # Public libraries (if any)
│
├── tests/                      # Test files
│   ├── e2e/                   # End-to-end tests
│   ├── security/              # Security-specific tests
│   └── performance/           # Performance benchmarks
│
├── scripts/                    # Build & utility scripts
│   ├── build-all.sh           # Cross-compile for all architectures
│   ├── test.sh                # Run all tests
│   ├── bench.sh               # Run benchmarks
│   └── security-scan.sh       # Run security tests
│
├── docs/                       # Documentation
│   ├── ARCHITECTURE.md        # Detailed architecture
│   ├── SECURITY.md            # Security details
│   ├── TESTING.md             # Testing guide
│   ├── API.md                 # API documentation
│   └── CONTRIBUTING.md        # Contribution guidelines
│
├── .agent_logs/                # AI agent session logs
│
├── CLAUDE.md                   # This file (project context)
├── AGENT.md                    # AI agent operational rules
├── TASKS.md                    # Task list & status
├── TECH_DEBT.md               # Technical debt tracking (NEW)
├── README.md                   # User documentation
├── LICENSE                     # GPLv3
├── SECURITY.md                 # Security policy
├── CODE_OF_CONDUCT.md          # Community guidelines
└── .gitignore                  # Git ignore rules
```

---

## MIGRATION PLAN

### Phase 1: Backup & Branch

```bash
# Backup existing Electron project
git checkout -b electron-backup
git push origin electron-backup

# Create clean Go branch
git checkout main
git checkout -b go-pivot
```

### Phase 2: Clean Slate

**Remove (Electron artifacts):**
- `node_modules/`, `package.json`, `package-lock.json`
- `tsconfig.json`, `webpack.config.js`, `forge.config.js`
- `src/` directory (all TypeScript code)
- `.eslintrc.json`, `.prettierrc`, `jest.config.js`

**Keep (Project documentation):**
- `README.md` (update tech stack section)
- `LICENSE`, `SECURITY.md`, `CODE_OF_CONDUCT.md`
- `.gitignore` (update for Go)
- `docs/` content (update as needed)
- This file (`CLAUDE.md`)

### Phase 3: Initialize Go Project

```bash
# Initialize Go module
go mod init github.com/yourusername/protondrive-linux

# Create directory structure
mkdir -p cmd/protondrive
mkdir -p internal/{encryption,sync,gui,config,client,storage,profile,conflict,errors,observability}
mkdir -p tests/{e2e,security,performance}
mkdir -p pkg scripts docs

# Add dependencies (minimal, official-first)
go get github.com/ProtonMail/gopenpgp/v3@latest           # Proton's crypto library
go get github.com/henrybear327/Proton-API-Bridge@latest   # Drive API bridge
go get fyne.io/fyne/v2@latest                             # GUI framework
go get github.com/fsnotify/fsnotify@latest                # File watching
go get github.com/zalando/go-keyring@latest               # Credential storage
go get github.com/stretchr/testify@latest                 # Testing

# Optional: Only if SQL query performance is critical
# go get github.com/mutecomm/go-sqlcipher/v4@latest       # Adds CGO
```

### Phase 4: Incremental Development with Testing

**Week 1: Foundation + Encryption**
- Set up project structure
- Implement local encryption layer (internal/encryption/)
- Write unit tests for encryption (100% coverage required)
- Implement Argon2id key derivation with PBKDF2 fallback
- Test database encryption with SQLCipher

**Week 2: Basic CLI + Authentication**
- Implement Proton-API-Bridge wrapper (internal/client/)
- Create basic CLI for authentication
- Write unit tests for authentication flow
- Test connection to ProtonDrive API
- Verify encrypted communication
- Implement keyring with fallback

**Week 3: Sync Engine Foundation**
- Implement file watcher with polling fallback (internal/sync/)
- Create upload/download workers with retry logic
- Write unit tests for sync logic
- Implement metadata storage in encrypted database
- Test encrypted cache storage

**Week 4: GUI Foundation**
- Create login screen (internal/gui/)
- Build main window with file list
- Implement settings panel
- Write GUI unit tests
- Test decryption for display

**Week 5: Conflict Resolution + Integration**
- Implement conflict detection and resolution
- Write comprehensive integration tests
- Test E2E workflows (first run, sync, conflicts)
- Run security verification tests
- Performance benchmarking

**Week 6: Polish + Security Audit**
- Code review focusing on security
- Run all security tests (privacy verification)
- Performance optimization based on benchmarks
- Documentation updates
- Prepare for release

### Phase 5: Testing & Distribution

**Testing Matrix:**
- Test on Ubuntu 22.04, Fedora 39, Arch Linux (x86_64)
- Test on Raspberry Pi 3+ (ARM64)
- Test on Raspberry Pi 2 (ARMv7)
- Verify 80% code coverage across all packages
- Run full security test suite
- Performance benchmarking on all profiles

**Build Release Binaries:**
```bash
# Build for all architectures
./scripts/build-all.sh

# Produces:
# protondrive-linux-amd64
# protondrive-linux-arm64
# protondrive-linux-armv7
# protondrive-linux-armv6
```

---

## PERFORMANCE TARGETS

### Startup Time
- **Cold start**: < 500ms (includes key derivation)
- **Warm start**: < 200ms (key already in memory)
- **Database unlock**: < 100ms (SQLCipher initialization)

### Memory Usage
- **Low-end profile**: < 30MB (including encryption overhead)
- **Standard profile**: < 50MB
- **High-end profile**: < 80MB
- **Memory properly freed**: No leaks, garbage collection effective

### Binary Size
- **Single binary**: < 20MB (includes SQLCipher)
- **No unpacking needed**: Instant run
- **All dependencies included**: No external libraries required

### Encryption Performance
- **Key derivation (Argon2id)**: < 500ms (standard profile)
- **Database unlock**: < 100ms (SQLCipher open)
- **File encryption**: > 100 MB/s (with AES-NI, ~50 MB/s without)
- **File decryption**: > 100 MB/s (with AES-NI)
- **Memory wipe**: < 50ms (zero out sensitive data)

### UI Responsiveness
- **FPS**: 60 on all hardware
- **First paint**: < 100ms
- **Interaction delay**: < 50ms
- **File list rendering**: < 100ms for 1000 files

### Sync Performance
- **File hashing**: > 100 MB/s (limited by disk I/O)
- **Upload throughput**: Limited by network and ProtonDrive API
- **Download throughput**: Limited by network and ProtonDrive API
- **Change detection**: < 1s after file modification
- **Encryption overhead**: < 5% of total sync time

---

## SUCCESS CRITERIA

### Must Have (MVP)

**Core Functionality:**
- Authenticate with ProtonDrive account (SRP protocol)
- List files in ProtonDrive with encrypted local storage
- Upload files to ProtonDrive with E2E encryption
- Download files from ProtonDrive with decryption
- Two-way sync (local ↔ remote) with conflict detection
- Detect and handle conflicts with user-chosen strategy

**Privacy & Security:**
- All local data encrypted (database, cache, logs if persisted)
- No plaintext filenames in logs or config
- Credentials stored in OS keyring (with fallback)
- Memory wiping of sensitive data
- Security tests pass (no plaintext leakage)

**Performance:**
- Run on Raspberry Pi with 1GB RAM
- Startup time < 500ms on modern hardware
- Memory usage < 50MB on standard profile
- Single binary distribution (no dependencies)

**Resilience:**
- Graceful degradation when keyring unavailable
- Retry logic for transient failures
- Clear error messages for user
- Health check endpoint

**Testing:**
- 80% unit test coverage overall
- 100% coverage on security-critical components
- All security tests passing
- Integration tests passing
- E2E tests passing

### Should Have (v1.0)

**Enhanced Functionality:**
- Selective sync (choose which folders to sync)
- Pause/resume sync with state preservation
- System tray integration with status icon
- Desktop notifications
- Bandwidth limits
- Retry failed transfers with exponential backoff

**User Experience:**
- Settings UI for all preferences
- Progress indicators
- Conflict resolution UI
- Auto-start on login (optional)

**Quality:**
- Detailed documentation
- Packaging for major distros (deb, rpm, AUR)
- Logging framework with verbosity levels
- Crash recovery

### Nice to Have (v1.x)

**Advanced Features:**
- File versioning UI
- Share link generation
- Multiple account support
- LAN sync
- Incremental updates (delta sync)
- Smart sync (download on-demand)
- Encrypted search

---

## RISK REGISTER & MITIGATIONS *(NEW SECTION)*

### Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Fyne proves unsuitable for production | Medium | High | GUI layer isolated; GTK4/gotk4 as fallback |
| ProtonDrive API changes break bridge | Low | High | Pin to stable version; monitor upstream |
| SQLCipher 4.x → 5.x migration needed | Low | Medium | Include migration tool from v1.0 |
| Performance targets missed on Pi | Medium | Medium | Profile early; optimize critical paths |
| Keyring unavailable on minimal distros | High | Medium | Encrypted file fallback implemented |
| fsnotify limits hit with large folders | Medium | Low | Polling fallback; document inotify tuning |

### Security Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Memory not properly wiped | Low | High | Unit tests verify wiping; code review |
| Plaintext leak in logs | Low | High | Privacy tests catch leaks; structured logging |
| Key derivation too weak | Low | High | Argon2id with OWASP-recommended params |
| SQLCipher misconfiguration | Low | High | Security tests verify encryption; defaults |

### Operational Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| User loses password | Medium | High | Clear documentation; no recovery possible |
| Corrupt database | Low | High | WAL mode; periodic integrity checks |
| Upgrade breaks existing data | Medium | Medium | Schema versioning; migration tests |

---

## ACCESSIBILITY & INTERNATIONALIZATION *(NEW SECTION)*

### Accessibility Goals

**Keyboard Navigation:**
- All functions accessible via keyboard
- Tab order follows logical flow
- Keyboard shortcuts for common actions

**Screen Reader Support:**
- Fyne widgets have accessibility labels
- Status changes announced
- Error messages accessible

**Visual Accessibility:**
- High contrast mode support
- Configurable font sizes
- Color not sole indicator of status

### Internationalization (i18n)

**Supported Languages (MVP):**
- English (default)

**Future Languages:**
- Community-contributed translations
- Use Go i18n libraries (e.g., `go-i18n`)
- All user-facing strings externalized

**RTL Support:**
- Planned for v1.x
- Fyne has basic RTL support

### Implementation

```go
// internal/i18n/i18n.go
type Localizer struct {
    bundle *i18n.Bundle
    lang   string
}

func (l *Localizer) T(key string, args ...interface{}) string {
    // Return translated string with args interpolated
}
```

---

## DOCUMENT MAINTENANCE

### Update This Document When:
- Architecture changes significantly
- Technology choices change
- New major subsystem added
- Security model changes
- Performance targets adjusted
- Testing strategy evolves
- New risks identified
- Dependencies updated

### Update Frequency
- **Minor updates**: As needed during development
- **Major updates**: At phase transitions
- **Review**: Every 3 months minimum

### Version History

**v11.1 (2024-12-10)** - Document Split
- Separated tasks into TASKS.md
- CLAUDE.md is now pure architectural reference
- Removed checkbox-style items (moved to TASKS.md)

**v11.0 (2024-12-10)** - Simplified Crypto Stack
- Replaced third-party crypto with Proton's official GopenPGP library
- Removed SQLCipher requirement (GopenPGP handles local encryption)
- Reduced dependencies from ~15 to 5-6
- Unified encryption approach: GopenPGP for both local and remote
- RFC 9580 profile automatically provides Argon2 + AEAD
- Updated architecture to reflect simpler crypto stack
- Cleaner, more maintainable dependency tree

**v10.0 (2024-12-10)** - Comprehensive Gap Analysis
- Added error handling and resilience strategy
- Added observability and diagnostics section
- Added tech debt tracking
- Enhanced Fyne limitations with mitigations
- Added keyring fallback chain
- Added risk register
- Added accessibility section

**v9.0 (2024-12-09)** - Zero-Trust E2E Compliance
- Added comprehensive zero-trust local storage requirements
- Added detailed testing strategy with unit test coverage
- Added security tests for privacy verification
- Added local encryption layer subsystem

**v8.0 (2024-12-09)** - Strategic Pivot
- Changed from TypeScript/Electron to Go/Fyne
- Added rationale for technology choices
- Updated architecture for Go/Fyne

---

## RELATED DOCUMENTS

| Document | Purpose |
|----------|---------|
| **TASKS.md** | Task list with checkboxes and status tracking |
| **AGENT.md** | AI agent operations: session logging, memory, changelog |
| **CHANGELOG.md** | Project change history (Added/Changed/Fixed/Removed) |
| **README.md** | User-facing documentation |
| **SECURITY.md** | Security policy and disclosure |
| **TECH_DEBT.md** | Technical debt tracking |
| **docs/** | Architecture, testing, and contribution guides |

### Agent Operations (AGENT.md)

The agent uses three systems to maintain context and prevent confusion:

1. **Session Log** (`.agent_logs/session_*.log`) - Real-time logging to prevent loops
2. **Memory File** (`.agent_logs/MEMORY.md`) - Persistent context across sessions  
3. **Changelog** (`CHANGELOG.md`) - Track project changes for users

See AGENTS.md for operational details.

---

## SUMMARY

**ProtonDrive Linux** is a native Linux client for ProtonDrive, built with Go and Fyne, prioritizing:

1. **Zero-Trust Privacy**: All local data encrypted, no plaintext anywhere
2. **Universal Hardware**: Runs on Raspberry Pi to workstations
3. **Native Performance**: <500ms startup, <50MB memory
4. **Simple Distribution**: Single binary, no dependencies
5. **Comprehensive Testing**: 80% coverage, security verified
6. **Graceful Degradation**: Continues functioning when components fail
7. **Open Source**: Community-driven, transparent development

**Key Innovation**: Unlike the Electron approach, this Go-based client leverages Proton-API-Bridge for ProtonDrive integration while adding a local encryption layer using Proton's own GopenPGP library to ensure true zero-trust privacy.

---

**Document Version**: 11.1  
**Last Updated**: 2024-12-10  
**Type**: Architectural Reference (not task tracking)  
**License**: GPLv3

---

*This document defines the vision, principles, and technical approach for ProtonDrive Linux. For current tasks, see TASKS.md.*