# Services Layer

## Purpose

Business logic services for ProtonDrive integration, local storage, file synchronization, and authentication. Services are singletons with lifecycle management (initialize/shutdown) and are used exclusively by the main process.

## Responsibilities

- ProtonDrive SDK integration
- Local SQLite database management
- Database migrations and backups
- User authentication and session management
- File upload/download operations
- Sync queue management
- API rate limiting and retry logic

## Directory Structure

```
services/
├── storage-service.ts      # SQLite database wrapper
├── backup-service.ts       # Database backup/restore
├── auth-service.ts         # Authentication service
├── sdk-bridge.ts           # ProtonDrive SDK adapter
├── api-queue.ts            # API request queue with rate limiting
└── database/
    └── migrations.ts       # Database migration runner
```

## Files

### `storage-service.ts`
**Purpose**: SQLite database wrapper with HDD optimization  
**Exports**: `StorageService` class, `getStorageService()` singleton  
**Dependencies**: `better-sqlite3`, `electron`

**Usage**:
```typescript
import { getStorageService } from '@services/storage-service'

const storage = getStorageService()
await storage.initialize()

// Run queries
const user = await storage.getRow('SELECT * FROM users WHERE id = ?', [userId])
const users = await storage.getAllRows('SELECT * FROM users')

// Run in transaction
await storage.runInTransaction(async (db) => {
  db.run('INSERT INTO users (name) VALUES (?)', ['Alice'])
  db.run('INSERT INTO logs (action) VALUES (?)', ['user_created'])
})

// Cleanup
await storage.closeDatabase()
```

**Features**:
- Synchronous API (simpler than async)
- Transaction support
- HDD optimization (WAL mode, tuned cache)
- Automatic schema migrations
- Connection pooling

**Tests**: 20/20 passing ✅

### `backup-service.ts`
**Purpose**: Automated database backups and restore  
**Exports**: `BackupService` class, `getBackupService()` singleton  
**Dependencies**: `storage-service`, `fs`, `path`

**Usage**:
```typescript
import { getBackupService } from '@services/backup-service'

const backup = getBackupService()
await backup.initialize()

// Create backup
await backup.createBackup('before-migration')

// List backups
const backups = await backup.listBackups()
// [{ filename: 'backup_2024-11-30_12-00-00_before-migration.sqlite', ... }]

// Restore from backup
await backup.restoreBackup('backup_2024-11-30_12-00-00_before-migration.sqlite')

// Delete old backups
await backup.deleteBackup('old-backup.sqlite')

// Get total backup size
const size = await backup.getTotalBackupSize() // bytes
```

**Features**:
- Automatic backup rotation (keeps last N backups)
- Emergency backup before restore
- Backup size monitoring
- Filename sanitization

**Tests**: 29/29 passing ✅

### `auth-service.ts`
**Purpose**: User authentication and session management  
**Exports**: `AuthService` class  
**Dependencies**: `sdk-bridge`, `electron.safeStorage`

**Usage**:
```typescript
import { AuthService } from '@services/auth-service'

const auth = new AuthService()

// Login
await auth.login('user@example.com', 'password')

// Check if authenticated
if (auth.isAuthenticated()) {
  const user = auth.getCurrentUser()
  console.log('Logged in as:', user.email)
}

// Get auth token (encrypted storage)
const token = await auth.getToken()

// Logout
await auth.logout()
```

**Features**:
- Secure credential storage (Electron safeStorage)
- Session persistence
- Token refresh
- 2FA support (planned)

### `sdk-bridge.ts`
**Purpose**: ProtonDrive SDK adapter and wrapper  
**Exports**: `SDKBridge` class  
**Dependencies**: `@protontech/drive-sdk`

**Usage**:
```typescript
import { SDKBridge } from '@services/sdk-bridge'

const sdk = new SDKBridge()
await sdk.initialize()

// Upload file
const result = await sdk.uploadFile('/local/path/file.pdf', '/remote/path/')

// Download file
await sdk.downloadFile('file-id', '/local/destination/')

// List files
const files = await sdk.listFiles('/remote/folder/')

// Delete file
await sdk.deleteFile('file-id')
```

**Features**:
- Chunked uploads for large files
- Resumable uploads
- Progress tracking
- Error handling and retry logic

### `api-queue.ts`
**Purpose**: API request queue with rate limiting  
**Exports**: `APIQueue` class  
**Dependencies**: `p-queue`, `axios-retry`

**Usage**:
```typescript
import { APIQueue } from '@services/api-queue'

const queue = new APIQueue({
  concurrency: 3,        // Max 3 concurrent requests
  intervalCap: 10,       // Max 10 requests
  interval: 1000         // Per 1 second
})

// Add request to queue
const result = await queue.add(async () => {
  return await api.get('/endpoint')
})

// Priority requests
await queue.add(async () => {
  return await api.post('/urgent')
}, { priority: 10 })
```

**Features**:
- Rate limiting (prevents API throttling)
- Priority queue
- Retry with exponential backoff
- Concurrency control based on hardware

### `database/migrations.ts`
**Purpose**: Database schema migration runner  
**Exports**: `applyMigrations()`, `getCurrentSchemaVersion()`  
**Dependencies**: `storage-service`, `fs`

**Usage**:
```typescript
import { applyMigrations, getCurrentSchemaVersion } from '@services/database/migrations'

// Get current version
const version = getCurrentSchemaVersion(db)
console.log('Schema version:', version)

// Apply pending migrations
await applyMigrations(db)
// Applies all migrations in order from database/migrations/*.sql
```

**Features**:
- Sequential migration execution
- Transaction-based (rollback on error)
- Version tracking
- Idempotent (safe to run multiple times)

**Tests**: 10/10 passing ✅

## Architecture

### Service Lifecycle
```typescript
// All services follow this pattern
class ExampleService {
  private initialized = false
  
  async initialize(): Promise<void> {
    if (this.initialized) return
    // Setup logic
    this.initialized = true
  }
  
  async shutdown(): Promise<void> {
    // Cleanup logic
    this.initialized = false
  }
}
```

### Service Dependencies
```
┌─────────────────────────────────────────┐
│         Main Process                    │
└──────────────┬──────────────────────────┘
               │
┌──────────────┴──────────────────────────┐
│         Services Layer                  │
│                                         │
│  ┌─────────────┐    ┌──────────────┐  │
│  │   Storage   │◄───│   Backup     │  │
│  └──────┬──────┘    └──────────────┘  │
│         │                               │
│  ┌──────▼──────┐    ┌──────────────┐  │
│  │ Migrations  │    │     Auth     │  │
│  └─────────────┘    └──────┬───────┘  │
│                             │           │
│  ┌──────────────┐    ┌─────▼───────┐  │
│  │  API Queue   │◄───│ SDK Bridge  │  │
│  └──────────────┘    └─────────────┘  │
└─────────────────────────────────────────┘
```

## Testing

### Test Location
Tests are in: `src/__tests__/services/`

### Running Tests
```bash
npm test -- services
```

### Current Coverage
- `storage-service.ts`: 100% (20/20 tests)
- `backup-service.ts`: 100% (29/29 tests)
- `database/migrations.ts`: 100% (10/10 tests)
- **Total**: 59/59 tests passing ✅

## Common Patterns

### Creating a New Service
```typescript
// services/example-service.ts
import logger from '@shared/utils/logger'

export class ExampleService {
  private initialized = false
  
  constructor(
    private readonly config: Config
  ) {}
  
  async initialize(): Promise<void> {
    if (this.initialized) return
    
    logger.info('Initializing ExampleService')
    
    try {
      // Setup logic
      this.initialized = true
      logger.info('ExampleService initialized')
    } catch (error) {
      logger.error('Failed to initialize ExampleService', { error })
      throw error
    }
  }
  
  async shutdown(): Promise<void> {
    logger.info('Shutting down ExampleService')
    // Cleanup logic
    this.initialized = false
  }
  
  // Public methods
  async doSomething(): Promise<void> {
    if (!this.initialized) {
      throw new Error('Service not initialized')
    }
    // Implementation
  }
}

// Singleton pattern
let instance: ExampleService | null = null

export function getExampleService(): ExampleService {
  if (!instance) {
    instance = new ExampleService(config)
  }
  return instance
}
```

### Error Handling
```typescript
try {
  await service.operation()
} catch (error) {
  logger.error('Operation failed', { error, context: 'service-name' })
  
  if (error instanceof NetworkError) {
    // Retry logic
  } else if (error instanceof AuthError) {
    // Re-authenticate
  } else {
    // Rethrow
    throw error
  }
}
```

## Planned Services

### Phase 2 P3
- `upload-service.ts` - File upload with chunking
- `download-service.ts` - File download with streaming
- `sync-service.ts` - Sync orchestration

### Phase 4
- `file-watcher.ts` - Local file change detection
- `conflict-resolver.ts` - Sync conflict resolution

## Best Practices

### ✅ DO
- Implement initialize/shutdown lifecycle
- Use singleton pattern for stateful services
- Log all important operations
- Handle errors gracefully
- Write comprehensive tests
- Use transactions for multi-step operations

### ❌ DON'T
- Access file system directly (use storage-service)
- Make API calls without queue (use api-queue)
- Store credentials in plain text (use safeStorage)
- Skip error handling
- Forget to cleanup resources in shutdown

## Related Documentation

- [Source Overview](../README.md)
- [Main Process](../main/README.md)
- [Shared Code](../shared/README.md)
- [AGENTS.md](../../AGENTS.md)

---

**Last Updated**: 2024-11-30  
**Status**: Core services implemented and tested, sync services planned for Phase 4
