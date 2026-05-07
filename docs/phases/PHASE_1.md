# Phase 1: Foundation & Infrastructure

**Duration**: 5-6 days
**Status**: ⬅️ CURRENT (~65% Complete)
**Dependencies**: Phase 0 (Complete)
**Unlocks**: Phase 2

---

## VERIFICATION STATUS (2024-12-11)

| Component | Completion | Build Status | Notes |
|-----------|------------|--------------|-------|
| 1.1 Config | 80% | ✅ PASSING | Tests pass, missing paths.go |
| 1.2 Errors | 70% | ❌ BUILD FAIL | Missing `import "errors"` |
| 1.3 Testing | 60% | ❌ BUILD FAIL | Wrong import paths |
| 1.4 Encryption | 60% | ❌ BUILD FAIL | Missing crypto imports |
| 1.5 Storage | 40% | ❌ BUILD FAIL | Depends on broken modules |
| 1.6 Profile | 70% | ❌ BUILD FAIL | Wrong import path |
| 1.7 CI/CD | 90% | ✅ DEFINED | Cannot run due to build failures |

### Critical Blockers
1. `internal/errors/errors.go` - Missing `import "errors"`
2. `internal/encryption/keys.go` - Missing `import "crypto/aes"` and `import "crypto/cipher"`
3. Multiple files use `github.com/yourusername/` instead of `github.com/donniedice/`

---

## OVERVIEW

Build the core infrastructure that all other components depend on.

**Entry Criteria**:
- Phase 0 complete
- Go module initialized
- Directory structure exists

**Exit Criteria**:
- All tasks complete
- CI/CD pipeline passing
- 100% test coverage on `internal/encryption/`
- All security tests passing

---

## INTERNAL DEPENDENCIES

```
1.1 Config ─────────────────┐
1.2 Errors ─────────────────┼──► 1.4 Encryption ──► 1.5 Storage
1.3 Test Infrastructure ────┘           │
                                        │
1.6 Profile (needs 1.1) ◄───────────────┘
                │
                ▼
        1.7 CI/CD (needs all)
```

**Parallel work possible**: 1.1, 1.2, 1.3 can be done simultaneously.

---

## 1.1 CONFIGURATION SYSTEM

**Dependencies**: None  
**Output**: `internal/config/`  
**Estimated Time**: 0.5 days  
**Status**: ✅ 100% Complete

### Tasks

- [x] 🏗️ **Create `internal/config/config.go`** ✅ VERIFIED
  - [x] Define `Config` struct
    > **Verified**: Struct exists with SyncDirectory, PerformanceProfile, VerboseLogging, DiskType fields
  - [x] Implement `LoadConfig(baseDir string)` ✅
    - [x] Handle file not found (create default) ✅
    - [x] Handle invalid JSON (return error) ✅
    - [x] Handle missing fields (use defaults) ✅
  - [x] Implement `(c *Config) Save(baseDir string)` ✅
  - [x] Implement `Validate() error` ✅
  - [x] Implement `NewConfig()` ✅
  - [x] Handle XDG paths via `GetDefaultConfigPath()` ✅
  - [x] Create directory if not exists ✅

- [x] 🏗️ **Create `internal/config/paths.go`** ✅ IMPLEMENTED
  > Provides XDG-compliant, auto-creating, testable path helpers
  - [x] `ConfigDir() string` → `filepath.Dir(GetConfigPath(""))` ✅
  - [x] `DataDir() string` → `GetDataDir(baseDir string)` ✅
  - [x] `CacheDir() string` → `GetCacheDir(baseDir string)` ✅
  - [x] `ConfigPath() string` → `GetConfigPath(baseDir)` ✅
  - [x] Respect XDG environment variables if set ✅

- [x] 🧪 **Create `internal/config/config_test.go`** ✅ VERIFIED - 12 tests passing
  - [x] All standard config tests fully implemented ✅

- [x] 🔒🧪 **Create `tests/security/config_test.go`** ✅ VERIFIED
  - [x] `TestConfigContainsNoSensitiveData` ✅

### Acceptance Criteria
- [x] Config loads from correct XDG path ✅
- [x] Missing config creates valid default ✅
- [x] Invalid config returns clear error ✅
- [x] No sensitive data ever written to config file ✅


## 1.2 ERROR HANDLING

**Dependencies**: None  
**Output**: `internal/errors/`  
**Estimated Time**: 0.5 days  
**Status**: ✅ 100% Complete

### Tasks

- [x] 🏗️ Create `internal/errors/errors.go`  
  - [x] Define SafeError and predefined error codes  
  - [x] Implement Error(), Unwrap(), NewSafeError(), Wrap()  
  - [x] Implement Is and As wrappers (fixed missing `import "errors"`)  
  - [x] Implement sensitive-data masking

- [x] 🏗️ Create `internal/errors/messages.go`  
  - [x] Map error codes to user-friendly messages  
  - [x] Map error codes to recovery suggestions  
  - [x] Implement `UserMessage(err)`  
  - [x] Implement `RecoverySuggestion(err)`

- [x] 🏗️ Create `internal/errors/retry.go`  
  - [x] RetryConfig struct  
  - [x] DefaultRetryConfig()  
  - [x] IsRetryable(err error) logic using SafeError.IsTemporary  
  - [x] NextDelay() with exponential backoff + jitter  
  - [x] Deterministic jitter implementation via LCG

- [x] 🧪 Create `internal/errors/errors_test.go`  
  - [x] Now builds and runs after import fix

- [x] 🧪 Create `internal/errors/retry_test.go`  
  - [x] Tests exponential backoff  
  - [x] Tests jitter bounds  
  - [x] Tests retryability  
  - [x] Tests default retry configuration

### Acceptance Criteria
- [x] All errors have safe messages suitable for logging  
- [x] No sensitive data ever appears in SafeError output  
- [x] Retry logic handles transient network conditions  
- [x] All error types unwrap correctly  
- [x] Full test coverage for error lifecycle, messages, and retry logic


---



## 1.3 TESTING INFRASTRUCTURE

**Dependencies**: None
**Output**: `internal/testutil/`, `tests/security/`
**Estimated Time**: 0.5 days
**Status**: ⚠️ 60% Complete - BUILD FAILURE

> **⚠️ BLOCKER**: Wrong import path `github.com/yourusername/` in testutil.go and helpers.go
> **⚠️ BLOCKER**: Missing `import "crypto/rand"` in tests/security/helpers.go

### Tasks

- [x] 🏗️ **Create `internal/testutil/testutil.go`** ✅ EXISTS (with build error)
  > **Verified**: File exists with mock implementations but has wrong import paths
  - [ ] `TempDir(t *testing.T) string` - Not found in current implementation
  - [ ] `TempFile(t *testing.T, content []byte) string` - Not found
  - [ ] `TempFileWithName(t *testing.T, name string, content []byte) string` - Not found
  - [ ] `AssertFileExists(t *testing.T, path string)` - Not found
  - [ ] `AssertFileNotExists(t *testing.T, path string)` - Not found
  - [ ] `AssertFileContains(t *testing.T, path string, substr string)` - Not found
  - [ ] `AssertFileNotContains(t *testing.T, path string, substr string)` - Not found
  - [ ] `ReadFile(t *testing.T, path string) []byte` - Not found

- [x] 🏗️ **Create `internal/testutil/mocks.go`** ✅ MERGED into testutil.go
  - [x] `MockProtonClient` ✅ Exists
  - [x] `MockEncryptionClient` ✅ Exists
  - [ ] `MockStore` interface implementation - Not found
  - [ ] `MockKeyring` interface implementation - Not found

- [x] 🔒 **Create `tests/security/helpers.go`** ✅ EXISTS (with build errors)
  - [x] `AssertFileIsEncrypted(t *testing.T, path string, correctKey, incorrectKey []byte, decryptFunc)` ✅
    > Uses decrypt function to verify encryption works with correct key, fails with incorrect
  - [x] `AssertFileContainsNoPlaintext(t *testing.T, path string, sensitiveStrings []string)` ✅
  - [x] `AssertMemoryWiped(t *testing.T, data []byte)` ✅
  - [ ] `AssertNoPlaintextInOutput(t *testing.T, output string, sensitive []string)` - Not implemented
  - [x] `GenerateTestKey(t *testing.T) []byte` ✅ Bonus helper
  - [x] `GenerateIncorrectKey(t *testing.T, correctKey []byte) []byte` ✅ Bonus helper

- [ ] 🧪 **Create `tests/security/helpers_test.go`** ❌ NOT IMPLEMENTED
  - [ ] No tests for the security helpers yet

### Acceptance Criteria
- [x] Test helpers simplify common test patterns ✅ Partial - mocks exist
- [ ] Mocks available for all major interfaces - Missing MockStore, MockKeyring
- [x] Security helpers can verify encryption and wiping ✅
- [ ] All helpers themselves have tests - No helpers_test.go

---

## 1.4 LOCAL ENCRYPTION LAYER 🔒

**Dependencies**: 1.2 (Errors), 1.3 (Test Infrastructure)
**Output**: `internal/encryption/`
**Estimated Time**: 1.5 days
**Coverage Requirement**: 100%
**Status**: ⚠️ 60% Complete - BUILD FAILURE

> **⚠️ BLOCKER**: Missing `import "crypto/aes"` and `import "crypto/cipher"` in keys.go (lines 60, 65, 85, 90)
> **Note**: Implementation uses PBKDF2+AES-GCM instead of GopenPGP RFC 9580 as specified in CLAUDE.md

### Tasks

- [ ] 🔒 **Create `internal/encryption/gopenpgp.go`** ❌ NOT IMPLEMENTED
  > **Architecture Decision**: Current implementation uses PBKDF2+AES-GCM in keys.go instead of GopenPGP
  - [ ] Initialize GopenPGP with RFC 9580 profile - Not implemented
  - [ ] All GopenPGP functions - Not implemented

- [x] 🔒 **Create `internal/encryption/keys.go`** ✅ EXISTS (Alternative Implementation)
  > **Verified**: Uses PBKDF2 with SHA256 for key derivation, AES-256-GCM for encryption
  - [x] `GenerateSalt() ([]byte, error)` ✅ 16-byte cryptographic salt
  - [x] `DeriveKey(password, salt []byte, iterations int) ([]byte, error)` ✅ PBKDF2-SHA256, 256-bit key
  - [x] `WipeKey(key []byte)` ✅ Zeroes memory
  - [x] `EncryptBytes(plaintext, key []byte) ([]byte, error)` ⚠️ Missing aes/cipher imports
  - [x] `DecryptBytes(ciphertext, key []byte) ([]byte, error)` ⚠️ Missing aes/cipher imports
  - [x] Constants: KeySize=32, DefaultPBKDF2Iterations=256000, SaltSize=16 ✅

- [x] 🔒 **Create `internal/encryption/keyring.go`** ✅ EXISTS
  > File exists but functionality needs verification after build fix

- [ ] 🔒 **Create `internal/encryption/fallback.go`** ❌ NOT IMPLEMENTED
  - [ ] Fallback storage path - Not implemented
  - [ ] `StoreFallback`, `RetrieveFallback`, `DeleteFallback`, `FallbackExists` - Not implemented

- [x] 🔒 **Create `internal/encryption/memory.go`** ✅ EXISTS
  - [x] `WipeKey(key []byte)` ✅ In keys.go - zeroes all bytes
  - [ ] `WipeString(s *string)` - Not found
  - [ ] `SecureBytes` type - Not found
  - [ ] `WithSecureBytes(data []byte, fn func([]byte) error) error` - Not found

- [ ] 🔒 **Create `internal/encryption/filename.go`** ❌ NOT IMPLEMENTED
  - [ ] `ObfuscateFilename(path string) string` - Not implemented
  - [ ] `GenerateCachePath(cacheDir, originalPath string) string` - Not implemented

- [x] 🔒 **Create `internal/encryption/database.go`** ✅ EXISTS (Bonus)
  > Database encryption wrapper exists

- [x] 🔒 **Create `internal/encryption/cache.go`** ✅ EXISTS (Bonus)
  > Cache encryption functionality exists

- [x] 🧪 **Create `internal/encryption/keys_test.go`** ✅ EXISTS (cannot run due to build failure)
- [x] 🧪 **Create `internal/encryption/keyring_test.go`** ✅ EXISTS
- [x] 🧪 **Create `internal/encryption/database_test.go`** ✅ EXISTS
- [x] 🧪 **Create `internal/encryption/cache_test.go`** ✅ EXISTS

- [ ] 🧪 **Create `internal/encryption/gopenpgp_test.go`** ❌ NOT IMPLEMENTED (gopenpgp.go doesn't exist)
- [ ] 🧪 **Create `internal/encryption/fallback_test.go`** ❌ NOT IMPLEMENTED (fallback.go doesn't exist)
- [ ] 🧪 **Create `internal/encryption/memory_test.go`** ❌ NOT IMPLEMENTED (memory.go partial)
- [ ] 🧪 **Create `internal/encryption/filename_test.go`** ❌ NOT IMPLEMENTED (filename.go doesn't exist)

- [ ] 🔒🧪 **Create `tests/security/encryption_test.go`** ❌ NOT IMPLEMENTED
  - [ ] `TestEncryptedDataNotPlaintext` - Not created
  - [ ] `TestMemoryWipedAfterUse` - Not created

### Acceptance Criteria
- [ ] Encryption/decryption works with GopenPGP RFC 9580 - Using PBKDF2+AES-GCM instead
- [ ] Keyring stores credentials when available - Partial implementation
- [ ] Fallback works when keyring unavailable - Not implemented
- [x] Memory wiping zeroes sensitive data ✅ WipeKey() implemented
- [ ] Filename obfuscation produces hashes - Not implemented
- [ ] 100% test coverage - Cannot test due to build failure
- [ ] Benchmark shows >100 MB/s on AES-NI hardware - Cannot benchmark

---

## 1.5 STORAGE LAYER (ENCRYPTED)

**Dependencies**: 1.4 (Encryption)
**Output**: `internal/storage/`
**Estimated Time**: 1 day
**Status**: ⚠️ 40% Complete - BUILD FAILURE

> **⚠️ BLOCKER**: Depends on broken `internal/encryption` module (wrong import paths in db_test.go)

### Tasks

- [x] 🏗️ **Create `internal/storage/models.go`** ✅ VERIFIED
  - [x] `FileMetadata` struct ✅
    > **Verified**: Struct exists with ID, Name, Path, Size, Hash, ModTime, RemoteID, SyncStatus, LastSyncTime, IsDir, ParentID fields
  - [ ] `SyncState` struct - ❌ NOT IMPLEMENTED
  - [ ] `ConflictRecord` struct - ❌ NOT IMPLEMENTED

- [x] 🏗️ **Create `internal/storage/db.go`** ✅ EXISTS
  > Database wrapper exists but full Store interface not implemented

- [ ] 🏗️ **Create `internal/storage/store.go`** ❌ NOT IMPLEMENTED
  - [ ] `Store` interface - Not defined
  - [ ] `EncryptedStore` implementation - Not implemented
  - [ ] `NewEncryptedStore(dataDir string, password []byte)` - Not implemented
  - [ ] Concurrent access handling (mutex) - Unknown
  - [ ] Atomic saves - Unknown

- [ ] 🏗️ **Create `internal/storage/cache.go`** ❌ NOT IMPLEMENTED
  - [ ] `Cache` interface - Not defined
  - [ ] `EncryptedCache` implementation - Not implemented
  - [ ] LRU eviction - Not implemented

- [x] 🧪 **Create `internal/storage/db_test.go`** ✅ EXISTS (cannot run due to build failure)
  > Has wrong import path: `github.com/yourusername/protondrive-linux/internal/encryption`

- [ ] 🧪 **Create `internal/storage/store_test.go`** ❌ NOT IMPLEMENTED (store.go doesn't exist)
- [ ] 🧪 **Create `internal/storage/cache_test.go`** ❌ NOT IMPLEMENTED (cache.go doesn't exist)

- [ ] 🔒🧪 **Create `tests/security/storage_test.go`** ❌ NOT IMPLEMENTED
  - [ ] `TestStorageFileIsEncrypted` - Not created
  - [ ] `TestCacheFilesAreEncrypted` - Not created
  - [ ] `TestCacheFilenamesObfuscated` - Not created

### Acceptance Criteria
- [ ] Store persists all metadata encrypted - Partial (models exist, store interface not implemented)
- [ ] Store survives restart with correct password - Not implemented
- [ ] Wrong password fails gracefully - Not implemented
- [ ] Cache stores encrypted content - Not implemented
- [ ] Cache filenames are hashed - Not implemented
- [ ] LRU eviction works - Not implemented
- [ ] All security tests pass - No security tests

---

## 1.6 PERFORMANCE PROFILER

**Dependencies**: 1.1 (Config)
**Output**: `internal/profile/`
**Estimated Time**: 0.5 days
**Status**: ⚠️ 70% Complete - BUILD FAILURE

> **⚠️ BLOCKER**: Wrong import path `github.com/yourusername/protondrive-linux/internal/config` in detector.go:12

### Tasks

- [x] 🏗️ **Create `internal/profile/detector.go`** ✅ VERIFIED
  - [x] `DetectRAM()` → via `DetectSystemCapabilities()` using gopsutil ✅
    > Uses `github.com/shirou/gopsutil/v3/mem` - returns TotalRAMGB as float64
  - [x] `DetectCPUCores()` → via `DetectSystemCapabilities()` using gopsutil ✅
    > Uses `github.com/shirou/gopsutil/v3/cpu` - returns logical core count
  - [ ] `DetectStorageType(path string)` ⚠️ PLACEHOLDER
    > `isSSDFromConfig()` only reads from config, no actual SSD/HDD detection
  - [x] `DetectAESSupport() bool` → `detectHardwareAES()` ✅
    > Parses `/proc/cpuinfo` for "aes" flag on amd64, "crypto"/"neon" on ARM
  - [x] `SystemCapabilities` struct ✅ (TotalRAMGB, NumCPU, IsSSD, Architecture, HasHardwareAES)
  - [x] `SuggestPerformanceProfile(caps *SystemCapabilities) PerformanceProfile` ✅
    > Selects LowEnd/Standard/HighEnd based on RAM and CPU cores

- [x] 🏗️ **Create `internal/profile/profiles.go`** → `internal/config/profiles.go` ✅ EXISTS
  > Profile definitions exist in config package instead of profile package
  - [x] Profile constants: LowEnd, Standard, HighEnd ✅
  - [x] Profile selection logic ✅ in detector.go

- [x] 🧪 **Create `internal/profile/detector_test.go`** ✅ EXISTS (cannot run due to build failure)

- [x] 🧪 **Create `internal/config/profiles_test.go`** ✅ EXISTS
  > Tests for capabilities in config package

### Acceptance Criteria
- [x] Hardware detection works on Linux ✅ Via gopsutil
- [x] Profile selection matches hardware ✅ RAM/CPU-based selection
- [x] Profiles have appropriate resource limits ✅ Defined in config/profiles.go
- [x] AES detection identifies hardware support ✅ Parses /proc/cpuinfo

---

## 1.7 CI/CD FOUNDATION

**Dependencies**: 1.1-1.6 (all must have tests)
**Output**: `.github/workflows/ci.yml`
**Estimated Time**: 0.5 days
**Status**: ✅ 90% Complete - Pipeline Defined

> **Note**: Pipeline is well-defined but cannot pass due to build failures in other modules

### Tasks

- [x] 🏗️ **Create `.github/workflows/ci.yml`** ✅ VERIFIED - Comprehensive pipeline
  - [x] Trigger on push/PR to main, alpha, dev branches ✅
  - [x] **Test job** ✅
    > Includes: checkout, setup-go, apt deps, mod download/verify, go vet, staticcheck, tests with race+coverage, codecov upload
  - [x] **Lint job** ✅ (merged into test job)
    > go vet and staticcheck both run in test job
  - [x] **Security job** ✅
    > Separate job with govulncheck + security tests (continue-on-error while tests being built)
  - [x] **Build job** ✅ Multi-architecture
    > Matrix build: linux-amd64, linux-arm64, linux-armv7 with cross-compilation support

- [x] 🏗️ **Configure coverage requirements** ⚠️ PARTIAL
  - [ ] Check overall coverage ≥80% - ⚠️ COMMENTED OUT (line 59)
  - [ ] Check `internal/encryption/` = 100% - Not implemented

- [x] 🏗️ **Configure artifact upload** ✅
  - [x] Upload coverage report ✅ via Codecov
  - [x] Upload build artifacts ✅ per architecture

- [x] **Bonus Features Implemented**:
  - [x] Release job ✅ - Creates checksums and uploads release assets
  - [x] Benchmark job ✅ - Runs on main branch only

- [ ] 📝 **Create `docs/CI_CD.md`** ❌ NOT IMPLEMENTED
  - [ ] Document pipeline structure
  - [ ] Document coverage requirements
  - [ ] Document how to run locally

- [ ] 🧪 **Verify pipeline works** ❌ CANNOT VERIFY
  - [ ] Pipeline cannot pass due to build failures in internal packages

### Acceptance Criteria
- [x] Pipeline runs on every push/PR ✅ Configured for main, alpha, dev
- [ ] Tests, lint, security all pass - Cannot pass due to build failures
- [ ] Coverage requirements enforced - Threshold check commented out
- [x] Build produces working binary ✅ Build job configured correctly
- [ ] Documentation complete - docs/CI_CD.md not created

---

## PHASE 1 EXIT CHECKLIST

Before moving to Phase 2, verify:

- [ ] **All code complete**
  - [x] `internal/config/` complete ✅ Tests passing
  - [ ] `internal/errors/` complete ⚠️ BUILD FAILURE - missing import
  - [ ] `internal/testutil/` complete ⚠️ BUILD FAILURE - wrong import paths
  - [ ] `internal/encryption/` complete ⚠️ BUILD FAILURE - missing imports
  - [ ] `internal/storage/` complete ⚠️ BUILD FAILURE - depends on broken modules
  - [ ] `internal/profile/` complete ⚠️ BUILD FAILURE - wrong import path

- [ ] **All tests passing**
  - [ ] `go test ./...` passes ❌ Build failures in 5 modules
  - [ ] No race conditions (`go test -race`) ❌ Cannot run

- [ ] **Coverage requirements met**
  - [ ] Overall ≥80% ❌ Cannot measure (build failures)
  - [ ] `internal/encryption/` = 100% ❌ Cannot measure

- [ ] **Security tests passing**
  - [ ] All `tests/security/` tests pass ❌ No tests implemented yet
  - [ ] No vulnerabilities from govulncheck ❌ Cannot run (build failures)

- [ ] **CI/CD operational**
  - [ ] Pipeline green on main branch ❌ Will fail due to build errors
  - [ ] All jobs passing ❌

- [ ] **Documentation updated**
  - [ ] CHANGELOG.md updated
  - [x] This file updated with completion status ✅

---

## CRITICAL FIXES REQUIRED BEFORE PHASE 1 CAN BE COMPLETED

1. **Add missing imports** (10 minutes):
   - `internal/errors/errors.go`: Add `import "errors"`
   - `internal/encryption/keys.go`: Add `import "crypto/aes"` and `import "crypto/cipher"`
   - `tests/security/helpers.go`: Add `import "crypto/rand"`

2. **Fix import paths** (30 minutes):
   Replace `github.com/yourusername/protondrive-linux` with `github.com/donniedice/protondrive-linux` in:
   - `main.go:5`
   - `internal/client/client.go:13-15`
   - `internal/profile/detector.go:12`
   - `internal/testutil/testutil.go`
   - `internal/storage/db_test.go:15`
   - `tests/security/helpers.go:11`

3. **After fixes, run**: `go build ./... && go test ./...`

---

**Phase 1 Estimated Completion**: 5-6 days (Currently ~65% complete)
**Blocking Issue**: Critical build failures prevent testing and verification
**Next Phase**: [PHASE_2.md](./PHASE_2.md) - Core API & Sync Engine