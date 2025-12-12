# ProtonDrive Linux - Master Task List

**Last Updated**: 2024-12-11  
**Project Phase**: Planning Complete → Ready for Implementation  
**Technology Stack**: Go + Fyne + GopenPGP (Proton Official)  
**Architecture Reference**: See `CLAUDE.md`

---

## OVERVIEW

This is the **master task list**. Each phase has a dedicated detailed document.

**Rule**: Tasks must be completed in dependency order. No skipping phases.

---

## PHASES

| Phase | Name | Status | Details |
|-------|------|--------|---------|
| 0 | Project Setup | ✅ **Complete** | N/A - Done |
| 1 | Foundation & Infrastructure | ⬅️ **CURRENT** | [PHASE_1.md](./docs/phases/PHASE_1.md) |
| 2 | Core API & Sync Engine | ❌ Blocked | [PHASE_2.md](./docs/phases/PHASE_2.md) |
| 3 | GUI Development | ❌ Blocked | [PHASE_3.md](./docs/phases/PHASE_3.md) |
| 4 | Testing & Hardening | ❌ Blocked | [PHASE_4.md](./docs/phases/PHASE_4.md) |
| 5 | Distribution & Release | ❌ Blocked | [PHASE_5.md](./docs/phases/PHASE_5.md) |

**Total Estimated Timeline**: 25-35 days (~5-7 weeks)

---

## DEPENDENCY GRAPH

```
Phase 0 ✅
    │
    ▼
Phase 1 (Foundation) ⬅️ CURRENT
    ├── Config, Errors, Test Infrastructure (parallel)
    ├── Encryption (needs Errors, Test Infra)
    ├── Storage (needs Encryption)
    ├── Profile (needs Config)
    └── CI/CD (needs all above)
            │
            ▼
Phase 2 (Core API & Sync)
    ├── Proton Client (needs Encryption, Storage)
    ├── File Operations (needs Client)
    ├── Sync Engine (needs File Ops, Storage)
    └── CLI (needs Client, Sync)
            │
            ▼
Phase 3 (GUI)
    ├── App Framework, Login, Main View
    ├── Settings, Tray, Notifications
    └── All GUI components
            │
            ▼
Phase 4 (Testing & Hardening)
    ├── Coverage Audit, Integration Tests
    ├── E2E Tests, Performance Tests
    ├── Security Audit, Cross-Platform Tests
    └── All quality gates
            │
            ▼
Phase 5 (Release)
    ├── Packaging (deb, rpm, flatpak, appimage)
    ├── CI/CD Release Pipeline
    ├── Documentation
    └── v1.0.0 Release
```

---

## LEGEND

```
[ ] Not Started
[⏳] In Progress  
[✅] Complete
[❌] Blocked (dependency not met)

🏗️ Infrastructure/Code    🔒 Security-Critical (100% test coverage required)
📝 Documentation          🧪 Testing
🔍 Research               🚀 Release
⚡ Performance-Critical
```

---

## PHASE SUMMARIES

### Phase 0: Project Setup ✅ COMPLETE

- [✅] Go module initialized
- [✅] Directory structure created
- [✅] Documentation files created (CLAUDE.md, TASKS.md, AGENT.md, CHANGELOG.md, README.md)

---

### Phase 1: Foundation & Infrastructure

**Goal**: Core infrastructure that all other components depend on.

| Section | Description | Status |
|---------|-------------|--------|
| 1.1 | Configuration System | [ ] |
| 1.2 | Error Handling | [ ] |
| 1.3 | Testing Infrastructure | [ ] |
| 1.4 | Encryption Layer (GopenPGP) 🔒 | [ ] |
| 1.5 | Storage Layer (Encrypted) | [ ] |
| 1.6 | Performance Profiler | [ ] |
| 1.7 | CI/CD Foundation | [ ] |

**Exit Criteria**: CI/CD green, 100% coverage on encryption, all security tests passing.

➡️ **Details**: [PHASE_1.md](./docs/phases/PHASE_1.md)

---

### Phase 2: Core API & Sync Engine

**Goal**: ProtonDrive integration and sync functionality.

| Section | Description | Status |
|---------|-------------|--------|
| 2.1 | Proton Client Wrapper | [ ] |
| 2.2 | File Operations | [ ] |
| 2.3 | Sync Engine | [ ] |
| 2.4 | Command-Line Interface | [ ] |
| 2.5 | Observability (Logging, Health) | [ ] |

**Exit Criteria**: Can authenticate, list files, sync files via CLI.

➡️ **Details**: [PHASE_2.md](./docs/phases/PHASE_2.md)

---

### Phase 3: GUI Development

**Goal**: Fyne-based graphical user interface.

| Section | Description | Status |
|---------|-------------|--------|
| 3.1 | Application Framework | [ ] |
| 3.2 | Login Screen | [ ] |
| 3.3 | Main View (File Browser) | [ ] |
| 3.4 | Settings Panel | [ ] |
| 3.5 | System Tray | [ ] |
| 3.6 | Notifications | [ ] |

**Exit Criteria**: Full GUI functional, usable by end users.

➡️ **Details**: [PHASE_3.md](./docs/phases/PHASE_3.md)

---

### Phase 4: Testing & Hardening

**Goal**: Comprehensive testing, optimization, security audit.

| Section | Description | Status |
|---------|-------------|--------|
| 4.1 | Unit Test Coverage Audit | [ ] |
| 4.2 | Integration Tests | [ ] |
| 4.3 | End-to-End Tests | [ ] |
| 4.4 | Performance Tests | [ ] |
| 4.5 | Security Audit | [ ] |
| 4.6 | Cross-Platform Tests | [ ] |

**Exit Criteria**: All quality gates passed, ready for release.

➡️ **Details**: [PHASE_4.md](./docs/phases/PHASE_4.md)

---

### Phase 5: Distribution & Release

**Goal**: Package, document, and release v1.0.0.

| Section | Description | Status |
|---------|-------------|--------|
| 5.1 | Packaging | [ ] |
| 5.2 | CI/CD Release Pipeline | [ ] |
| 5.3 | Documentation | [ ] |
| 5.4 | v1.0.0 Release | [ ] |

**Exit Criteria**: v1.0.0 published, available for download.

➡️ **Details**: [PHASE_5.md](./docs/phases/PHASE_5.md)

---

## QUICK REFERENCE

### Security Tests (must all pass)

| Test | Location | Verifies |
|------|----------|----------|
| `TestConfigContainsNoSensitiveData` | `tests/security/` | No credentials in config |
| `TestEncryptedDataNotPlaintext` | `tests/security/` | Encryption works |
| `TestMemoryWipedAfterUse` | `tests/security/` | Memory cleanup |
| `TestStorageFileIsEncrypted` | `tests/security/` | Database encrypted |
| `TestCacheFilesAreEncrypted` | `tests/security/` | Cache encrypted |
| `TestPasswordNeverStored` | `tests/security/` | Password not on disk |
| `TestVerboseOutputNoFilenames` | `tests/security/` | Logs safe |

### Performance Targets

| Metric | Target |
|--------|--------|
| Cold start | <500ms |
| Warm start | <200ms |
| Memory (Standard) | <50MB |
| Encryption throughput | >100 MB/s |
| Binary size | <20MB |

### Coverage Requirements

| Package | Minimum Coverage |
|---------|------------------|
| `internal/encryption/` | 100% |
| `internal/client/auth.go` | 100% |
| All other packages | 80% |
| GUI packages | 60% |

---

**Document Version**: 3.0  
**Last Updated**: 2024-12-11