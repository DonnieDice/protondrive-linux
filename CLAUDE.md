# ProtonDrive Linux Client - Project Context for AI Agents

**Version**: 6.0  
**Last Updated**: 2024-11-30  
**Phase**: Core Services Implementation (Phase 2)  
**Project Health**: 9.5/10

---

## WHAT THIS DOCUMENT IS

This is the complete project context for AI agents. It explains WHY decisions were made, WHAT the architecture is, and HOW to build it correctly.

**Purpose**: Help AI agents understand project goals, architecture decisions, and implementation patterns.

**This document contains:**
- Project overview and goals
- Architecture decisions and rationale
- Universal hardware compatibility strategy
- Security architecture
- Development patterns and best practices

**This document does NOT contain:**
- Task lists (see TASKS.md)
- Operational rules (see AGENT.md)
- User documentation (see README.md)

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
    }, 10000) // Check every 10s
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

## DEVELOPMENT PATTERNS

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

## PERFORMANCE BUDGETS

### Startup Time
- **Cold start**: < 2 seconds
- **Warm start**: < 1 second

### Memory Usage
- **Low-end profile**: < 100MB
- **Standard profile**: < 150MB
- **High-end profile**: < 200MB

### Bundle Size
- **Total installer**: < 80MB
- **Unpacked**: < 200MB

### UI Performance
- **FPS**: 30+ on low-end hardware
- **First paint**: < 500ms
- **Time to interactive**: < 1.5s

### Network
- **API timeout**: 30s default
- **Rate limit**: 10 req/s default
- **Concurrent uploads**: 1-5 (adaptive)
- **Concurrent downloads**: 2-10 (adaptive)

---

## PROJECT STRUCTURE

```
protondrive-linux/
├── src/
│   ├── main/              # Main process (Node.js)
│   ├── renderer/          # Renderer process (React)
│   ├── preload/           # Preload scripts (IPC bridge)
│   ├── services/          # Business logic services
│   ├── shared/            # Shared code (types, utils)
│   └── __tests__/         # Test files
├── scripts/               # Build and utility scripts
├── .agent_logs/           # AI agent session logs
├── docs/                  # Documentation
├── TASKS.md              # Complete task list
├── AGENT.md              # Operational rules for AI
├── GEMINI.md             # This file (project context)
└── README.md             # User documentation
```

---

## KEY PRINCIPLES

1. **Universal Compatibility**: Must run on any Linux device
2. **Adaptive Performance**: Adjust to available hardware
3. **Security First**: Context isolation, input validation, secure storage
4. **Privacy Focused**: Zero-knowledge encryption, minimal tracking
5. **Test Coverage**: 80% minimum on all code
6. **Documentation**: JSDoc on all public APIs
7. **Performance Budgets**: Enforced in CI/CD
8. **Graceful Degradation**: Never fail hard, reduce features instead

---

**For Task Management**: See TASKS.md  
**For Operational Rules**: See AGENT.md  
**For User Documentation**: See README.md