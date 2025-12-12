# Phase 4: Testing & Hardening

**Duration**: 5-7 days  
**Status**: ❌ Blocked by Phase 3  
**Dependencies**: Phase 3 (GUI) complete  
**Unlocks**: Phase 5

---

## OVERVIEW

Comprehensive testing, performance optimization, and security audit.

**Entry Criteria**: 
- Phase 3 complete
- Full application functional
- All unit tests passing

**Exit Criteria**:
- All quality gates passed
- Performance targets met
- Security audit complete
- Ready for release

---

## QUALITY GATES

| Gate | Requirement | Measured By |
|------|-------------|-------------|
| Unit Test Coverage | ≥80% overall | `go test -cover` |
| Security Coverage | 100% for encryption | Coverage report |
| Integration Tests | All passing | CI/CD |
| E2E Tests | All passing | CI/CD |
| Performance | All targets met | Benchmarks |
| Security Audit | No critical issues | Manual review |
| Cross-Platform | All platforms tested | Test matrix |

---

## 4.1 UNIT TEST COVERAGE AUDIT

**Dependencies**: All code complete  
**Output**: Coverage report, missing tests  
**Estimated Time**: 1 day

### Tasks

- [ ] 🧪 **Run coverage analysis**
  - [ ] `go test -coverprofile=coverage.out ./...`
  - [ ] `go tool cover -html=coverage.out -o coverage.html`
  - [ ] Review coverage report

- [ ] 🧪 **Verify coverage requirements**
  - [ ] Overall coverage ≥80%
  - [ ] `internal/encryption/` = 100%
  - [ ] `internal/client/auth.go` = 100%
  - [ ] `internal/storage/` ≥90%
  - [ ] `internal/sync/` ≥80%
  - [ ] `internal/gui/` ≥60%

- [ ] 🧪 **Write missing tests**
  - [ ] Identify uncovered lines
  - [ ] Write tests for critical paths
  - [ ] Focus on error handling paths

- [ ] 🧪 **Add edge case tests**
  - [ ] Empty inputs
  - [ ] Very large inputs
  - [ ] Unicode/special characters in filenames
  - [ ] Concurrent access scenarios
  - [ ] Error conditions and recovery

- [ ] 🧪 **Add fuzzing tests**
  - [ ] `FuzzEncryptDecrypt` - random data encryption
  - [ ] `FuzzConfigParse` - random JSON parsing
  - [ ] `FuzzFilenameObfuscation` - random filename handling
  - [ ] `FuzzMetadataParsing` - random metadata

- [ ] 🧪 **Review test quality**
  - [ ] Tests are meaningful (not just for coverage)
  - [ ] Tests are deterministic (no random failures)
  - [ ] Tests clean up after themselves
  - [ ] Tests don't depend on execution order
  - [ ] Tests have clear assertions and error messages

### Acceptance Criteria
- [ ] Coverage requirements met for all packages
- [ ] All edge cases covered
- [ ] Fuzzing tests added for parsers and encryption
- [ ] No flaky tests
- [ ] Test report generated

---

## 4.2 INTEGRATION TESTS

**Dependencies**: All components complete  
**Output**: `tests/integration/`  
**Estimated Time**: 1 day

### Tasks

- [ ] 🧪 **Create `tests/integration/setup_test.go`**
  - [ ] Test fixtures setup
  - [ ] Mock server setup (if needed)
  - [ ] Cleanup functions
  - [ ] Shared test utilities

- [ ] 🧪 **Create `tests/integration/auth_flow_test.go`**
  - [ ] `TestAuthFlow_LoginLogout`
    - Login with valid credentials
    - Verify session stored in keyring
    - Logout
    - Verify session cleared
  - [ ] `TestAuthFlow_SessionPersistence`
    - Login
    - Stop app
    - Restart app
    - Verify still logged in (no re-auth needed)
  - [ ] `TestAuthFlow_SessionRefresh`
    - Login
    - Wait for token near expiry
    - Verify automatic refresh happens
    - Verify new token stored
  - [ ] `TestAuthFlow_InvalidCredentials`
    - Login with wrong password
    - Verify error displayed
    - Verify no session stored
  - [ ] `TestAuthFlow_KeyringFallback`
    - Disable keyring (mock)
    - Login
    - Verify fallback storage used

- [ ] 🧪 **Create `tests/integration/sync_flow_test.go`**
  - [ ] `TestSyncFlow_InitialSync`
    - Fresh install (empty local)
    - Login
    - Verify all remote files downloaded
    - Verify metadata stored
  - [ ] `TestSyncFlow_LocalCreate`
    - Create local file
    - Wait for sync
    - Verify file uploaded to ProtonDrive
  - [ ] `TestSyncFlow_LocalModify`
    - Modify existing local file
    - Wait for sync
    - Verify changes uploaded
  - [ ] `TestSyncFlow_LocalDelete`
    - Delete local file
    - Wait for sync
    - Verify remote file deleted
  - [ ] `TestSyncFlow_RemoteCreate`
    - Create remote file (via API)
    - Wait for sync detection
    - Verify file downloaded locally
  - [ ] `TestSyncFlow_RemoteModify`
    - Modify remote file
    - Wait for sync
    - Verify local file updated
  - [ ] `TestSyncFlow_RemoteDelete`
    - Delete remote file
    - Wait for sync
    - Verify local file deleted
  - [ ] `TestSyncFlow_Rename`
    - Rename local file
    - Verify remote renamed
    - Rename remote file
    - Verify local renamed
  - [ ] `TestSyncFlow_Move`
    - Move file to different folder
    - Verify move synced both ways

- [ ] 🧪 **Create `tests/integration/conflict_test.go`**
  - [ ] `TestConflict_Detection`
    - Modify same file locally and remotely
    - Verify conflict detected
    - Verify conflict recorded in storage
  - [ ] `TestConflict_ServerWins`
    - Create conflict
    - Set strategy to server_wins
    - Resolve conflict
    - Verify local overwritten with remote
  - [ ] `TestConflict_LocalWins`
    - Create conflict
    - Set strategy to local_wins
    - Resolve conflict
    - Verify remote overwritten with local
  - [ ] `TestConflict_KeepBoth`
    - Create conflict
    - Set strategy to keep_both
    - Resolve conflict
    - Verify both files exist (one renamed)
  - [ ] `TestConflict_Manual`
    - Create conflict
    - Set strategy to manual
    - Verify user prompted (mock)

- [ ] 🧪 **Create `tests/integration/offline_test.go`**
  - [ ] `TestOffline_LocalChanges`
    - Go offline (mock network)
    - Make local changes
    - Verify changes queued
    - Go online
    - Verify changes synced
  - [ ] `TestOffline_QueuePersistence`
    - Go offline
    - Queue changes
    - Restart app
    - Go online
    - Verify queued changes still sync
  - [ ] `TestOffline_ConflictOnReconnect`
    - Go offline
    - Make local changes
    - Remote changes happen (via API)
    - Go online
    - Verify conflicts handled

- [ ] 🧪 **Create `tests/integration/error_recovery_test.go`**
  - [ ] `TestErrorRecovery_NetworkFailure`
    - Start upload
    - Simulate network failure mid-upload
    - Verify retry with backoff
    - Restore network
    - Verify eventual success
  - [ ] `TestErrorRecovery_PartialUpload`
    - Start large file upload
    - Interrupt at 50%
    - Resume upload
    - Verify file complete and correct
  - [ ] `TestErrorRecovery_PartialDownload`
    - Same for downloads
  - [ ] `TestErrorRecovery_CorruptCache`
    - Corrupt cache file on disk
    - Trigger cache read
    - Verify graceful handling (re-download)
  - [ ] `TestErrorRecovery_CorruptStorage`
    - Corrupt storage file
    - Start app
    - Verify graceful recovery or clear error

### Acceptance Criteria
- [ ] All integration tests pass
- [ ] Tests cover all sync scenarios
- [ ] Tests cover all error scenarios
- [ ] Tests are reliable (no flaky tests)
- [ ] Tests run in reasonable time (<5 min total)

---

## 4.3 END-TO-END TESTS

**Dependencies**: Full application working  
**Output**: `tests/e2e/`  
**Estimated Time**: 1 day

### Tasks

- [ ] 🧪 **Create `tests/e2e/setup_test.go`**
  - [ ] E2E test environment setup
  - [ ] Test user credentials (dedicated test account)
  - [ ] Cleanup between tests
  - [ ] Screenshot capture on failure (if GUI testing)

- [ ] 🧪 **Create `tests/e2e/first_run_test.go`**
  - [ ] `TestE2E_FirstRun`
    - Clean install (no existing config)
    - Launch application
    - Verify login screen displayed
    - Enter test credentials
    - Login succeeds
    - Select sync folder
    - Initial sync starts
    - Files appear in sync folder
    - Verify all files synced correctly

- [ ] 🧪 **Create `tests/e2e/daily_use_test.go`**
  - [ ] `TestE2E_CreateFile`
    - App running and synced
    - Create new file in sync folder
    - Wait for sync indicator
    - Verify file exists in ProtonDrive (via API check)
  - [ ] `TestE2E_ModifyFile`
    - Modify existing synced file
    - Wait for sync
    - Verify remote file has new content
  - [ ] `TestE2E_DeleteFile`
    - Delete file locally
    - Wait for sync
    - Verify file deleted remotely
  - [ ] `TestE2E_LargeFile`
    - Create large file (100MB)
    - Verify progress displayed
    - Verify upload completes
    - Verify file correct remotely
  - [ ] `TestE2E_ManyFiles`
    - Create 100 small files
    - Verify all sync correctly
    - Verify reasonable time

- [ ] 🧪 **Create `tests/e2e/gui_test.go`**
  - [ ] `TestE2E_GUI_Login`
    - Launch GUI
    - Enter credentials
    - Click login
    - Verify main view displayed
  - [ ] `TestE2E_GUI_FileList`
    - View file list
    - Verify files displayed
    - Click folder to navigate
    - Verify navigation works
  - [ ] `TestE2E_GUI_Settings`
    - Open settings
    - Change theme
    - Verify theme applied
    - Save settings
    - Restart
    - Verify settings persisted
  - [ ] `TestE2E_GUI_TrayIcon`
    - Verify tray icon appears
    - Click tray icon
    - Verify menu appears
    - Click "Pause"
    - Verify sync paused

- [ ] 🧪 **Create `tests/e2e/conflict_test.go`**
  - [ ] `TestE2E_Conflict_UserResolution`
    - Create conflict scenario
    - Verify conflict notification
    - Open conflict in UI
    - Select resolution
    - Verify resolved correctly

### Acceptance Criteria
- [ ] All E2E tests pass
- [ ] Tests represent real user workflows
- [ ] Tests complete in reasonable time
- [ ] Tests are reliable on CI

---

## 4.4 PERFORMANCE TESTS

**Dependencies**: Full application working  
**Output**: `tests/performance/`, benchmark results  
**Estimated Time**: 1 day

### Tasks

- [ ] ⚡ **Create `tests/performance/startup_test.go`**
  - [ ] `BenchmarkColdStart`
    - Clear all caches
    - Measure time to main window
    - **Target: <500ms**
  - [ ] `BenchmarkWarmStart`
    - Normal start (caches warm)
    - Measure time to main window
    - **Target: <200ms**
  - [ ] `BenchmarkLoginTime`
    - Measure authentication time
    - **Target: <2s**

- [ ] ⚡ **Create `tests/performance/memory_test.go`**
  - [ ] `TestMemoryUsage_Idle`
    - Start app, login, idle
    - Measure memory usage
    - **Target (Standard profile): <50MB**
  - [ ] `TestMemoryUsage_LowEnd`
    - Use low-end profile
    - **Target: <30MB**
  - [ ] `TestMemoryUsage_HighEnd`
    - Use high-end profile
    - **Target: <80MB**
  - [ ] `TestMemoryUsage_LargeFileList`
    - Load 10,000 files
    - Measure memory
    - Verify no memory leak
  - [ ] `TestMemoryUsage_LongRunning`
    - Run for 1 hour with activity
    - Check for memory leaks
    - Verify stable memory

- [ ] ⚡ **Create `tests/performance/throughput_test.go`**
  - [ ] `BenchmarkEncryption`
    - Encrypt 1GB of data
    - Measure throughput
    - **Target: >100 MB/s (with AES-NI)**
  - [ ] `BenchmarkDecryption`
    - Same for decryption
    - **Target: >100 MB/s**
  - [ ] `BenchmarkHashing`
    - Hash 1GB of data
    - **Target: >100 MB/s**
  - [ ] `BenchmarkUpload`
    - Upload large file
    - Measure throughput (network limited)
  - [ ] `BenchmarkDownload`
    - Download large file
    - Measure throughput

- [ ] ⚡ **Create `tests/performance/sync_test.go`**
  - [ ] `BenchmarkInitialSync`
    - Sync 1,000 files initially
    - Measure time
  - [ ] `BenchmarkIncrementalSync`
    - Change 10 files
    - Measure time to detect and sync
  - [ ] `BenchmarkConflictDetection`
    - Measure time to detect conflicts

- [ ] ⚡ **Create `tests/performance/profile_test.go`**
  - [ ] Test on simulated low-end hardware
    - Limit CPU
    - Limit memory
    - Verify app still works
  - [ ] Test profile auto-selection
    - Mock hardware detection
    - Verify correct profile selected

### Performance Targets Summary

| Metric | Target | Priority |
|--------|--------|----------|
| Cold start | <500ms | P0 |
| Warm start | <200ms | P0 |
| Memory (Standard) | <50MB | P0 |
| Memory (Low-End) | <30MB | P0 |
| Encryption throughput | >100 MB/s | P1 |
| Hashing throughput | >100 MB/s | P1 |
| Binary size | <20MB | P1 |

### Acceptance Criteria
- [ ] All P0 performance targets met
- [ ] All P1 targets met or justified exceptions
- [ ] No memory leaks
- [ ] Performance documented

---

## 4.5 SECURITY AUDIT

**Dependencies**: All code complete  
**Output**: `SECURITY_AUDIT.md`  
**Estimated Time**: 1 day

### Tasks

- [ ] 🔒 **Run automated security scans**
  - [ ] `govulncheck ./...` - no vulnerabilities
  - [ ] `staticcheck ./...` - no issues
  - [ ] Review all dependencies for CVEs

- [ ] 🔒 **Run all security tests**
  - [ ] `go test ./tests/security/...`
  - [ ] All tests must pass
  - [ ] Review test coverage of security code

- [ ] 🔒 **Code review: Encryption**
  - [ ] GopenPGP used correctly
  - [ ] RFC 9580 profile configured
  - [ ] No custom crypto
  - [ ] Key derivation secure (Argon2)
  - [ ] Memory wiped after use

- [ ] 🔒 **Code review: Credential handling**
  - [ ] Passwords never stored
  - [ ] Passwords wiped from memory
  - [ ] Session tokens in keyring only
  - [ ] Fallback storage encrypted

- [ ] 🔒 **Code review: Logging**
  - [ ] Grep for `fmt.Print`, `log.Print` 
  - [ ] No filenames in logs
  - [ ] No credentials in logs
  - [ ] Only file IDs logged

- [ ] 🔒 **Code review: Error messages**
  - [ ] Errors don't leak sensitive data
  - [ ] User-facing errors are safe

- [ ] 🔒 **Verify no analytics/telemetry**
  - [ ] Search for analytics libraries
  - [ ] Search for tracking code
  - [ ] Verify no phone-home

- [ ] 🔒 **Verify network security**
  - [ ] All network calls to ProtonDrive only
  - [ ] TLS used for all connections
  - [ ] Certificate validation enabled
  - [ ] No insecure endpoints

- [ ] 🔒 **Verify data at rest**
  - [ ] Database encrypted
  - [ ] Cache files encrypted
  - [ ] Config has no sensitive data
  - [ ] No temp files with plaintext

- [ ] 🔒 **Verify data in memory**
  - [ ] Sensitive data wiped after use
  - [ ] No sensitive data in core dumps (if possible)

- [ ] 📝 **Create `SECURITY_AUDIT.md`**
  - [ ] Document all findings
  - [ ] Document security architecture
  - [ ] Document threat model
  - [ ] Document any accepted risks
  - [ ] Sign-off from reviewer

### Security Checklist

| Item | Status | Notes |
|------|--------|-------|
| No plaintext credentials stored | [ ] | |
| All local data encrypted | [ ] | |
| Memory wiped after use | [ ] | |
| No filenames in logs | [ ] | |
| No analytics/telemetry | [ ] | |
| All network traffic encrypted | [ ] | |
| Only connects to ProtonDrive | [ ] | |
| No known vulnerabilities | [ ] | |
| Code review complete | [ ] | |

### Acceptance Criteria
- [ ] All automated scans pass
- [ ] All security tests pass
- [ ] Code review complete
- [ ] No critical or high severity issues
- [ ] SECURITY_AUDIT.md created and signed off

---

## 4.6 CROSS-PLATFORM TESTS

**Dependencies**: Packages available for testing  
**Output**: Test matrix results  
**Estimated Time**: 1 day

### Tasks

- [ ] 🧪 **Test on Ubuntu 22.04 LTS (x86_64)**
  - [ ] Install from .deb
  - [ ] Run all functionality tests
  - [ ] Verify GUI displays correctly
  - [ ] Verify tray icon works
  - [ ] Verify notifications work
  - [ ] Check system integration

- [ ] 🧪 **Test on Ubuntu 24.04 LTS (x86_64)**
  - [ ] Same tests as above

- [ ] 🧪 **Test on Fedora 39 (x86_64)**
  - [ ] Install from .rpm
  - [ ] Run all functionality tests
  - [ ] Verify GUI/tray/notifications
  - [ ] Check SELinux compatibility

- [ ] 🧪 **Test on Arch Linux (x86_64)**
  - [ ] Install from binary or AUR
  - [ ] Run all functionality tests
  - [ ] Verify latest library compatibility

- [ ] 🧪 **Test on Raspberry Pi OS (ARM64)**
  - [ ] Install ARM64 binary
  - [ ] Verify profile auto-selects low-end
  - [ ] Test sync functionality
  - [ ] Verify performance acceptable
  - [ ] Check memory usage

- [ ] 🧪 **Test on Raspberry Pi OS (ARMv7)**
  - [ ] Install ARM32 binary
  - [ ] Same tests as ARM64
  - [ ] Verify 32-bit works

- [ ] 🧪 **Verify hardware detection**
  - [ ] RAM detection works on all platforms
  - [ ] CPU core detection works
  - [ ] Storage type detection works
  - [ ] AES-NI detection works (x86_64)
  - [ ] ARM crypto detection works (ARM)

- [ ] 🧪 **Verify keyring integration**
  - [ ] GNOME Keyring (Ubuntu, Fedora GNOME)
  - [ ] KWallet (KDE systems)
  - [ ] Fallback when no keyring

- [ ] 📝 **Document platform-specific issues**
  - [ ] Any workarounds needed
  - [ ] Any limitations
  - [ ] Minimum requirements confirmed

### Test Matrix

| Platform | Arch | Status | Notes |
|----------|------|--------|-------|
| Ubuntu 22.04 | x86_64 | [ ] | |
| Ubuntu 24.04 | x86_64 | [ ] | |
| Fedora 39 | x86_64 | [ ] | |
| Arch Linux | x86_64 | [ ] | |
| Raspberry Pi OS | ARM64 | [ ] | |
| Raspberry Pi OS | ARMv7 | [ ] | |

### Acceptance Criteria
- [ ] All platforms in matrix tested
- [ ] No critical bugs on any platform
- [ ] Hardware detection works everywhere
- [ ] Keyring integration works or falls back
- [ ] Platform issues documented

---

## PHASE 4 EXIT CHECKLIST

Before moving to Phase 5, verify:

- [ ] **Coverage requirements met**
  - [ ] Overall ≥80%
  - [ ] Encryption = 100%
  - [ ] Coverage report generated

- [ ] **All tests passing**
  - [ ] Unit tests pass
  - [ ] Integration tests pass
  - [ ] E2E tests pass
  - [ ] Security tests pass
  - [ ] Performance tests pass

- [ ] **Performance targets met**
  - [ ] Cold start <500ms
  - [ ] Warm start <200ms
  - [ ] Memory <50MB (standard)
  - [ ] Encryption >100 MB/s

- [ ] **Security audit complete**
  - [ ] No critical issues
  - [ ] SECURITY_AUDIT.md created
  - [ ] All findings addressed

- [ ] **Cross-platform verified**
  - [ ] All platforms tested
  - [ ] Issues documented

- [ ] **Documentation updated**
  - [ ] CHANGELOG.md updated
  - [ ] Test reports generated
  - [ ] This file updated with completion status

---

**Phase 4 Estimated Completion**: 5-7 days  
**Next Phase**: [PHASE_5.md](./PHASE_5.md) - Distribution & Release