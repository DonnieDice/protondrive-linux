# ProtonDrive Linux Client - Project Context for AI Agent

**Version**: 5.0  
**Last Updated**: 2024-11-29  
**Phase**: Core Services Implementation (Phase 2)  
**Project Health**: 9.5/10

---

## WHAT THIS DOCUMENT IS

This is the complete project context for Gemini AI agent. It explains WHY decisions were made, WHAT the architecture is, HOW to build it, and ALL tasks to completion. This is NOT user documentation - that's in README.md. This is NOT operational rules - that's in agent-docs.md.

**Purpose**: Help AI agent understand project context, implement features correctly, and track progress to completion.

---

## PROJECT OVERVIEW

### What We're Building

ProtonDrive Linux is an unofficial, open-source desktop client for ProtonDrive targeting Linux users exclusively. Native GUI application providing seamless file synchronization with ProtonDrive's zero-knowledge encryption.

**Critical Design Goal**: Universal hardware compatibility - runs on ANY Linux device (Raspberry Pi to workstations) with adaptive performance.

### Why Linux Only

**Decision**: Focus exclusively on Linux platform.

**Reasoning**:
- ProtonDrive lacks official Linux client
- Linux community values privacy and open source
- Focused development yields better quality
- Avoids cross-platform complexity
- Electron handles different Linux distros
- Linux runs on widest hardware range

### Why Electron

**Decision**: Use Electron instead of native Qt/GTK or Tauri.

**Reasoning**:
- Mature ecosystem with extensive libraries
- TypeScript/JavaScript enables rapid development
- ProtonDrive SDK is JavaScript-based (perfect integration)
- Cross-distro compatibility without rebuilding
- Multi-architecture support (x86_64, ARM64, ARMv7)
- Rich UI with React
- Well-tested security model

**Trade-offs Accepted**:
- Higher base RAM (50-80MB) vs native (10-20MB)
- Larger installer (60-80MB) vs native (5-10MB)
- Worth it: Development speed + SDK integration

---

## UNIVERSAL HARDWARE COMPATIBILITY

### Design Philosophy

**"If it runs Linux, it should run ProtonDrive Linux"**

No artificial hardware requirements. Application adapts to available resources.

### How to Build for Universal Compatibility

#### 1. Adaptive Resource Management

**Implementation Pattern**:
```typescript
// Detect system capabilities at startup
interface SystemCapabilities {
  totalRAM: number        // MB
  availableRAM: number    // MB at startup
  cpuCores: number
  architecture: string    // x86_64, ARM64, ARMv7
  storageType: string     // Estimated: SSD, HDD, eMMC
}

// Adjust behavior based on hardware
class PerformanceProfile {
  static detect(): PerformanceProfile {
    const caps = this.getSystemCapabilities()
    
    if (caps.totalRAM < 4096) {
      return new LowEndProfile()    // 2-4GB RAM
    } else if (caps.totalRAM < 8192) {
      return new StandardProfile()  // 4-8GB RAM
    } else {
      return new HighEndProfile()   // 8GB+ RAM
    }
  }
}

class LowEndProfile extends PerformanceProfile {
  maxConcurrentUploads = 1
  maxConcurrentDownloads = 2
  cacheSizeMB = 50
  enableAnimations = false
  chunkSizeMB = 5
  maxMemoryUsageMB = 100
}

class StandardProfile extends PerformanceProfile {
  maxConcurrentUploads = 3
  maxConcurrentDownloads = 5
  cacheSizeMB = 100
  enableAnimations = true
  chunkSizeMB = 5
  maxMemoryUsageMB = 150
}

class HighEndProfile extends PerformanceProfile {
  maxConcurrentUploads = 5
  maxConcurrentDownloads = 10
  cacheSizeMB = 200
  enableAnimations = true
  chunkSizeMB = 10
  maxMemoryUsageMB = 200
}
```

#### 2. Graceful Degradation Strategy

**Rule**: Never fail hard on resource constraints. Always provide reduced functionality.

**Examples**:
```typescript
// Animation handling
if (performanceProfile.enableAnimations) {
  // Full animations
  transition: 'all 0.3s ease'
} else {
  // Instant, no animation
  transition: 'none'
}

// Cache management
if (memoryUsage > profile.maxMemoryUsageMB * 0.8) {
  // Aggressively clear cache
  cache.clear()
}

// Concurrent operations
const maxConcurrent = Math.min(
  profile.maxConcurrentUploads,
  Math.floor(availableRAM / 50) // 50MB per upload
)
```

#### 3. Storage Type Optimization

**Problem**: HDD vs SSD performance varies 10x.

**Solution**: Detect and optimize:
```typescript
// Estimate storage type from write performance
async function detectStorageType(): Promise<'SSD' | 'HDD' | 'UNKNOWN'> {
  const testFile = path.join(app.getPath('temp'), 'storage-test')
  const testData = Buffer.alloc(10 * 1024 * 1024) // 10MB
  
  const start = performance.now()
  await fs.writeFile(testFile, testData)
  await fs.fsync(testFile)
  const duration = performance.now() - start
  
  await fs.unlink(testFile)
  
  // SSD: <50ms, HDD: >200ms for 10MB sync write
  if (duration < 100) return 'SSD'
  if (duration > 150) return 'HDD'
  return 'UNKNOWN'
}

// Adjust database behavior
if (storageType === 'HDD') {
  // Batch writes more aggressively
  db.pragma('synchronous = NORMAL') // vs FULL for SSD
  db.pragma('journal_mode = WAL')   // Better for HDD
  db.pragma('cache_size = -4000')   // 4MB cache (smaller for HDD)
} else {
  db.pragma('synchronous = FULL')
  db.pragma('cache_size = -8000')   // 8MB cache
}
```

#### 4. Architecture-Specific Builds

**Multi-architecture support**:
- x86_64: Intel/AMD processors
- ARM64: Raspberry Pi 3+, modern ARM SBCs
- ARMv7: Raspberry Pi 2, older ARM devices

**Electron Forge Configuration**:
```javascript
// forge.config.js
module.exports = {
  makers: [
    {
      name: '@electron-forge/maker-appimage',
      config: {
        options: {
          arch: ['x64', 'arm64', 'armv7l']
        }
      }
    }
  ]
}
```

#### 5. Memory Management Strategies

**Critical Rules**:
- Never load entire files into memory (use streams)
- Clear caches proactively when approaching limits
- Use weak references for large objects
- Monitor memory usage continuously

**Implementation**:
```typescript
// Memory monitor service
class MemoryMonitor {
  private interval: NodeJS.Timeout
  
  start() {
    this.interval = setInterval(() => {
      const usage = process.memoryUsage()
      const heapUsedMB = usage.heapUsed / 1024 / 1024
      
      if (heapUsedMB > performanceProfile.maxMemoryUsageMB * 0.9) {
        logger.warn('High memory usage, clearing caches')
        this.clearCaches()
      }
    }, 10000) // Check every 10s.
  }
  
  clearCaches() {
    // Clear various caches
    thumbnailCache.clear()
    metadataCache.clear()
    // Force garbage collection if available
    if (global.gc) global.gc()
  }
}
```

#### 6. CPU Optimization

**Strategies**:
- Detect CPU core count and adjust parallelism
- Use Web Workers for CPU-intensive tasks
- Throttle on single-core systems

```typescript
const cpuCores = os.cpus().length

// Adjust worker pool size
const workerPoolSize = Math.max(1, Math.floor(cpuCores / 2))

// Throttle expensive operations on low-core systems
if (cpuCores <= 2) {
  // Single-threaded processing
  processQueue.concurrency = 1
} else {
  processQueue.concurrency = Math.min(cpuCores - 1, 4)
}
```

---

## ARCHITECTURE DECISIONS

### Overall Architecture Pattern

```
┌─────────────────────────────────────────┐
│         Renderer Process (React)        │
│   - UI Components                       │
│   - Zustand State (lightweight)         │
│   - No Node.js Access (security)        │
└──────────────┬──────────────────────────┘
               │ IPC (contextBridge)
┌──────────────┴──────────────────────────┐
│           Preload Script                │
│   - Secure IPC Bridge                   │
│   - Input Validation (Zod)              │
└──────────────┬──────────────────────────┘
               │
┌──────────────┴──────────────────────────┐
│         Main Process (Node.js)          │
│   - Window Management                   │
│   - Service Layer (business logic)      │
│   - Database Access (SQLite)            │
│   - File System Operations              │
│   - ProtonDrive SDK Integration         │
│   - Performance Profiling               │
└─────────────────────────────────────────┘
```

### State Management: Zustand

**Why Zustand over Redux**:
- Lightweight (4KB vs 20KB+)
- Minimal overhead on low-end hardware
- Simple API, less boilerplate
- TypeScript-first
- No Provider hell

### Database: SQLite with better-sqlite3

**Why SQLite**:
- Serverless, no separate process
- ACID transactions
- Synchronous API (simpler code)
- Efficient on embedded systems (Raspberry Pi uses SQLite)
- Small memory footprint (<10MB)

**Optimization for HDD**:
```sql
PRAGMA synchronous = NORMAL;  -- Balance safety/speed
PRAGMA journal_mode = WAL;     -- Better concurrent access
PRAGMA temp_store = MEMORY;    -- Faster temp operations
PRAGMA cache_size = -4000;     -- 4MB cache for HDD
```

### Logging: Winston

**Configuration**:
- File rotation to prevent disk space issues
- Structured JSON logging
- Adjustable log levels (error/warn/info/debug)
- Minimal overhead (<1MB RAM)

### Network: axios + p-queue + axios-retry

**Rate Limiting** (p-queue):
- Prevents API throttling
- Adaptive concurrency based on hardware profile
- Low-end: 1-2 concurrent, High-end: 5-10 concurrent

**Retry Logic** (axios-retry):
- Exponential backoff
- Essential for unreliable connections (WiFi on Raspberry Pi)

---

## SECURITY ARCHITECTURE

### Context Isolation

**Why**: Prevents renderer from accessing Node.js APIs

**Implementation**: Enabled in BrowserWindow configuration
```typescript
webPreferences: {
  contextIsolation: true,
  nodeIntegration: false,
  sandbox: true,
  preload: path.join(__dirname, 'preload.js')
}
```

### Sandboxed Renderer

**Why**: OS-level process isolation, limits malicious code damage

### Input Validation with Zod

**All IPC messages validated**:
```typescript
const FilePathSchema = z.object({
  path: z.string().min(1).max(4096),
  name: z.string().min(1).max(255)
})

// In preload script
ipcRenderer.on('file-selected', (event, data) => {
  const validated = FilePathSchema.parse(data)
  // Safe to use
})
```

### Credential Storage

**Use Electron safeStorage**:
```typescript
import { safeStorage } from 'electron'

// Store
const encrypted = safeStorage.encryptString(token)
await db.set('auth_token', encrypted)

// Retrieve
const encrypted = await db.get('auth_token')
const token = safeStorage.decryptString(encrypted)
```

---

## COMPLETE TASK LIST TO COMPLETION

### Phase 1: Infrastructure (COMPLETE ✓)

- [x] Project structure created
- [x] TypeScript configuration (strict mode)
- [x] Webpack configuration
- [x] Electron Forge setup
- [x] Security hardening (context isolation, CSP)
- [x] Testing frameworks (Jest, Playwright)
- [x] CI/CD pipeline (GitHub Actions)
- [x] Git hooks (Husky, lint-staged)
- [x] Documentation structure
- [x] Agent logging system
- [x] Command wrapper (run-command.sh)
- [x] Legal documents (LICENSE, SECURITY, CODE_OF_CONDUCT)
- [x] Configuration files (.env.example, etc.)

### Phase 2: Core Services (IN PROGRESS)

**P0: Foundation Layer**
- [ ] Create src/shared/types/system.ts - System capability types
- [ ] Create src/shared/utils/performance-profiler.ts - Hardware detection
- [ ] Create src/services/env-validator.ts - Environment validation with Zod
- [ ] Create src/services/app-config.ts - Configuration loader + performance profiles
- [ ] Create src/services/logger.ts - Winston logging setup
- [ ] Test: Unit tests for performance profiler
- [ ] Test: Unit tests for env-validator
- [ ] Test: Unit tests for app-config

**P1: Database Layer**
- [ ] Create src/services/storage-service.ts - SQLite wrapper with HDD optimization
- [ ] Create src/services/database/migrations.ts - Migration runner
- [ ] Create src/services/database/migrations/001_initial_schema.sql - Initial schema
- [ ] Create src/services/database/migrations/002_indexes.sql - Performance indexes
- [ ] Create src/services/backup-service.ts - Automated database backups
- [ ] Test: Unit tests for storage-service
- [ ] Test: Migration up/down tests
- [ ] Test: Backup/restore tests

**P2: SDK Integration**
- [ ] Create src/services/sdk-bridge.ts - ProtonDrive SDK adapter
- [ ] Create src/services/auth-service.ts - Authentication with secure storage
- [ ] Create src/shared/utils/api-client.ts - axios configuration with retry
- [ ] Create src/services/api-queue.ts - Request queue with p-queue
- [ ] Test: Unit tests for sdk-bridge (mocked SDK)
- [ ] Test: Unit tests for auth-service
- [ ] Test: API queue concurrency tests

**P3: Input Validation**
- [ ] Create src/shared/schemas/file-schemas.ts - Zod file validation
- [ ] Create src/shared/schemas/auth-schemas.ts - Zod auth validation
- [ ] Create src/shared/schemas/config-schemas.ts - Zod config validation
- [ ] Update src/preload/index.ts - Add schema validation to IPC
- [ ] Test: Schema validation tests

**P4: Error Handling**
- [ ] Create src/shared/errors/app-errors.ts - Custom error classes
- [ ] Create src/shared/utils/error-handler.ts - Global error handler
- [ ] Integrate Sentry error tracking
- [ ] Test: Error handling tests

**Phase 2 Exit Criteria**:
- All services have 80%+ test coverage
- Database migrations work forward/backward
- Performance profiles correctly detect hardware
- Authentication works with secure storage
- All P0-P4 tasks complete

### Phase 3: UI Foundation

**P0: Component Library**
- [ ] Create src/renderer/components/ui/Button.tsx
- [ ] Create src/renderer/components/ui/Input.tsx
- [ ] Create src/renderer/components/ui/Modal.tsx
- [ ] Create src/renderer/components/ui/Toast.tsx
- [ ] Create src/renderer/components/ui/Loading.tsx
- [ ] Set up Tailwind CSS configuration
- [ ] Test: Component unit tests
- [ ] Test: Accessibility tests (a11y)

**P1: Authentication UI**
- [ ] Create src/renderer/components/auth/LoginForm.tsx
- [ ] Create src/renderer/components/auth/TwoFactorForm.tsx
- [ ] Create src/renderer/stores/auth-store.ts - Zustand auth state
- [ ] Wire up authentication service to UI
- [ ] Test: E2E login flow (Playwright)

**P2: Settings UI**
- [ ] Create src/renderer/components/settings/GeneralSettings.tsx
- [ ] Create src/renderer/components/settings/PerformanceSettings.tsx
- [ ] Create src/renderer/components/settings/AccountSettings.tsx
- [ ] Create src/renderer/stores/settings-store.ts
- [ ] Test: Settings E2E tests

**P3: File Browser UI**
- [ ] Create src/renderer/components/files/FileList.tsx
- [ ] Create src/renderer/components/files/FileItem.tsx
- [ ] Create src/renderer/components/files/FolderTree.tsx
- [ ] Create src/renderer/stores/files-store.ts
- [ ] Test: File browser E2E tests

**P4: System Integration**
- [ ] Implement system tray (electron-tray)
- [ ] Implement desktop notifications
- [ ] Implement theme support (light/dark)
- [ ] Test: System integration tests

**Phase 3 Exit Criteria**:
- All UI components have unit tests
- E2E tests cover critical user flows
- System tray functional
- UI performs at 30+ FPS on low-end hardware
- All P0-P4 tasks complete

### Phase 4: Sync Engine

**P0: File Watcher**
- [ ] Create src/services/file-watcher.ts - Watch local file changes
- [ ] Create src/services/change-detector.ts - Detect file modifications
- [ ] Handle large directories efficiently
- [ ] Test: File watcher unit tests
- [ ] Test: Change detection tests

**P1: Upload/Download Queue**
- [ ] Create src/services/upload-service.ts - Chunked upload logic
- [ ] Create src/services/download-service.ts - Streaming download
- [ ] Implement resumable uploads
- [ ] Implement progress tracking
- [ ] Test: Upload/download unit tests
- [ ] Test: Resume functionality tests

**P2: Conflict Resolution**
- [ ] Create src/services/conflict-resolver.ts - Conflict detection
- [ ] Implement conflict resolution strategies
- [ ] Create conflict UI components
- [ ] Test: Conflict resolution tests

**P3: Sync Orchestration**
- [ ] Create src/services/sync-service.ts - Main sync coordinator
- [ ] Implement sync queue management
- [ ] Implement delta sync (only changed parts)
- [ ] Test: Sync service integration tests
- [ ] Test: Large file sync tests (>1GB)

**P4: Optimization**
- [ ] Implement bandwidth throttling
- [ ] Implement offline mode detection
- [ ] Optimize for HDD performance
- [ ] Test: Performance tests against budgets
- [ ] Test: Offline mode tests

**Phase 4 Exit Criteria**:
- Files sync reliably
- Large files (5GB+) upload successfully
- Conflicts detected and resolved
- Sync works on low-end hardware
- Offline mode functional
- All P0-P4 tasks complete

### Phase 5: Advanced Features

**P0: Selective Sync**
- [ ] Create src/services/selective-sync.ts
- [ ] UI for selecting folders to sync
- [ ] Test: Selective sync tests

**P1: Shared Folders**
- [ ] Implement shared folder detection
- [ ] UI for shared folder management
- [ ] Test: Shared folder tests

**P2: File Versioning UI**
- [ ] Create version history viewer
- [ ] Implement version restoration
- [ ] Test: Version UI tests

**P3: Search Functionality**
- [ ] Create src/services/search-service.ts
- [ ] Full-text search in database
- [ ] Search UI component
- [ ] Test: Search tests

**P4: Performance Optimization**
- [ ] Profile memory usage on low-end hardware
- [ ] Optimize database queries
- [ ] Reduce bundle size
- [ ] Test: Performance regression tests

**P5: Additional Languages**
- [ ] Add translations (Spanish, French, German)
- [ ] Language switcher UI
- [ ] Test: i18n tests

**Phase 5 Exit Criteria**:
- All advanced features functional
- Performance optimized
- Translations complete
- All P0-P5 tasks complete

### Phase 6: Distribution

**P0: Beta Testing**
- [ ] Set up beta testing program
- [ ] Create feedback collection mechanism
- [ ] Fix critical bugs from beta
- [ ] Test: Beta user feedback review

**P1: Package Creation**
- [ ] Configure AppImage builds (x64, ARM64, ARMv7)
- [ ] Configure deb builds (multi-arch)
- [ ] Configure rpm builds (multi-arch)
- [ ] Test packages on various distros
- [ ] Test: Installation tests

**P2: Auto-Update System**
- [ ] Configure electron-updater
- [ ] Set up update server/CDN
- [ ] Implement update notifications
- [ ] Test: Auto-update tests

**P3: Release Automation**
- [ ] Configure semantic-release
- [ ] Set up release workflow
- [ ] Create release checklist
- [ ] Test: Release process dry-run

**P4: Documentation**
- [ ] Complete user guide
- [ ] Create video tutorials
- [ ] Write FAQ
- [ ] Update all documentation

**P5: Marketing Materials**
- [ ] Create project website
- [ ] Write announcement blog post
- [ ] Create screenshots/videos
- [ ] Prepare social media posts

**Phase 6 Exit Criteria**:
- Beta testing complete
- Packages available for all architectures
- Auto-update functional
- Documentation complete
- Ready for public release

---

## DEVELOPMENT WORKFLOW

### How to Implement a Service

**Template for all services**:
```typescript
// src/services/example-service.ts

import { logger } from './logger'

/**
 * ExampleService - Brief description
 * 
 * Responsibilities:
 * - List what this service does
 * - Be specific about scope
 * 
 * Dependencies:
 * - List required services
 */
export class ExampleService {
  private initialized = false
  
  constructor(
    private readonly config: AppConfig,
    private readonly storage: StorageService
  ) {}
  
  /**
   * Initialize service
   * Should be idempotent (safe to call multiple times)
   */
  async initialize(): Promise<void> {
    if (this.initialized) return
    
    logger.info('Initializing ExampleService')
    
    try {
      // Initialization logic
      this.initialized = true
      logger.info('ExampleService initialized successfully')
    } catch (error) {
      logger.error('Failed to initialize ExampleService', { error })
      throw error
    }
  }
  
  /**
   * Cleanup resources
   */
  async shutdown(): Promise<void> {
    logger.info('Shutting down ExampleService')
    // Cleanup logic
    this.initialized = false
  }
}
```

### How to Write Tests

**Test structure**:
```typescript
// tests/unit/services/example-service.test.ts

import { ExampleService } from '@/services/example-service'

describe('ExampleService', () => {
  let service: ExampleService
  let mockConfig: AppConfig
  let mockStorage: StorageService
  
  beforeEach(() => {
    // Set up mocks
    mockConfig = createMockConfig()
    mockStorage = createMockStorage()
    service = new ExampleService(mockConfig, mockStorage)
  })
  
  afterEach(() => {
    // Cleanup
  })
  
  describe('initialize', () => {
    it('should initialize successfully', async () => {
      await service.initialize()
      expect(service.isInitialized()).toBe(true)
    })
    
    it('should be idempotent', async () => {
      await service.initialize()
      await service.initialize() // Should not throw
      expect(service.isInitialized()).toBe(true)
    })
    
    it('should handle initialization errors', async () => {
      mockStorage.setup.mockRejectedValue(new Error('DB error'))
      await expect(service.initialize()).rejects.toThrow('DB error')
    })
  })
})
```

### How to Handle Performance Budgets

**Always check before committing**:
```bash
# Memory test
./scripts/run-command.sh "node scripts/memory-test.js"
# Should report < 150MB for standard profile

# Build size check
./scripts/run-command.sh "npm run build"
du -sh out/
# Should be < 80MB

# Startup time check
time ./scripts/run-command.sh "npm start"
# Should be < 2s cold start
```

### Command Wrapper Usage

**Always use wrapper for commands**:
```bash
# Good
./scripts/run-command.sh "npm start"
./scripts/run-command.sh "npm test"

# Bad (will lock up terminal)
npm start
npm test
```

### Conventional Commits

**Format**:
```
<type>(<scope>): <subject>

<body>

<footer>
```

**Examples**:
```bash
feat(auth): add OAuth2 authentication
fix(sync): resolve duplicate upload bug
perf(db): optimize query with index
test(upload): add chunked upload tests
docs(readme): update installation instructions
```

---

## TESTING REQUIREMENTS

### Coverage Requirements

**80% minimum coverage enforced in CI**:
- Unit tests: Business logic and services
- Integration tests: Service interactions
- E2E tests: Critical user workflows
- Performance tests: Budget validation

### What to Test

**Unit Tests** (Jest):
- All service methods
- Utility functions
- Error handling
- Edge cases

**Integration Tests**:
- SDK bridge + storage service
- Sync service + conflict resolver
- Auth service + credential storage

**E2E Tests** (Playwright):
- Login flow
- File upload/download
- Conflict resolution UI
- Settings changes

**Performance Tests**:
- Memory usage over time
- Startup time
- Sync speed
- Database query performance

---

## DOCUMENTATION REQUIREMENTS

### Code Documentation

**All public APIs must have JSDoc**:
```typescript
/**
 * Upload file to ProtonDrive
 * 
 * @param filePath - Local file path
 * @param remotePath - Remote destination path
 * @param options - Upload options
 * @returns Upload result with file ID
 * @throws {AuthenticationError} If not authenticated
 * @throws {NetworkError} If upload fails
 * 
 * @example
 * ```typescript
 * const result = await uploadFile(
 *   '/home/user/document.pdf',
 *   '/Documents/document.pdf'
 * )
 * console.log('Uploaded:', result.fileId)
 * ```
 */
async uploadFile(
  filePath: string,
  remotePath: string,
  options?: UploadOptions
): Promise<UploadResult>
```

### Architecture Decision Records

**Document all major decisions**:
```markdown
# ADR 003: Use Zustand for State Management

## Status
Accepted

## Context
Need lightweight state management for React UI.

## Decision
Use Zustand instead of Redux.

## Consequences
Positive:
- Smaller bundle size (4KB vs 20KB)
- Less boilerplate
- Better TypeScript support

Negative:
- Less ecosystem/plugins than Redux
- Team may need to learn new library

## Alternatives Considered
- Redux: Too much boilerplate
- Context API: Not sufficient for complex state
```

---

## SUCCESS METRICS

### Technical Metrics

- All tests passing (80%+ coverage)
- No security vulnerabilities (npm audit)
- Performance budgets met on all hardware classes
- Code quality: ESLint passing, no TypeScript errors
- CI/CD pipeline green

### User Experience Metrics

- Files sync reliably (99%+ success rate)
- Fast and responsive UI on their hardware
- Intuitive interface (minimal support questions)
- Stable (no crashes in normal usage)
- Privacy maintained (zero-knowledge encryption)

### Project Health Metrics

- Active development (regular commits)
- Community contributions (PRs accepted)
- Clear roadmap (phases documented)
- Regular releases (semantic versioning)
- Positive user feedback

---

**This document provides complete project context and task list for AI agent. For operational rules, see agent-docs.md. For user documentation, see README.md.**

**Last Updated**: 2024-11-29  
**Version**: 5.0  
**Status**: ACTIVE - Complete Context with All Tasks to Completion