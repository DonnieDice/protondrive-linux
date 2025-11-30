# Shared Code

## Purpose

Code that is shared between the main process (Node.js) and renderer process (Chromium). This includes utilities, configuration, types, and helpers that work in both environments.

## Responsibilities

- Application configuration management
- Environment variable validation
- Logging utilities
- Performance monitoring
- Type definitions
- Validation schemas (Zod)
- Error classes

## Directory Structure

```
shared/
├── config/
│   ├── app-config.ts       # Application configuration
│   └── env-validator.ts    # Environment validation with Zod
├── utils/
│   ├── logger.ts           # Winston logging
│   └── performance.ts      # Performance monitoring
├── types/                  # TypeScript types (to be created)
├── schemas/                # Zod validation schemas (to be created)
└── errors/                 # Custom error classes (to be created)
```

## Files

### `config/app-config.ts`
**Purpose**: Centralized application configuration  
**Exports**: `appConfig` (frozen object)  
**Dependencies**: `env-validator`

**Usage**:
```typescript
import { appConfig } from '@shared/config/app-config'

console.log(appConfig.NODE_ENV)        // 'development' | 'production' | 'test'
console.log(appConfig.LOG_LEVEL)       // 'error' | 'warn' | 'info' | 'debug'
console.log(appConfig.APTABASE_APP_KEY) // Analytics key (optional)
console.log(appConfig.SENTRY_DSN)      // Error tracking DSN (optional)

// Config is frozen - cannot be modified
appConfig.NODE_ENV = 'test' // ❌ Error: Cannot assign to read only property
```

### `config/env-validator.ts`
**Purpose**: Validates environment variables using Zod schemas  
**Exports**: `getValidatedEnv()`, `envSchema`  
**Dependencies**: `zod`

**Usage**:
```typescript
import { getValidatedEnv } from '@shared/config/env-validator'

// Validates and returns typed environment variables
const env = getValidatedEnv()

// TypeScript knows the exact types
env.NODE_ENV // 'development' | 'production' | 'test'
env.LOG_LEVEL // 'error' | 'warn' | 'info' | 'http' | 'verbose' | 'debug' | 'silly'

// Throws error if validation fails
// Error: Invalid environment variables: NODE_ENV must be one of...
```

### `utils/logger.ts`
**Purpose**: Winston-based logging utility  
**Exports**: `logger` (default export)  
**Dependencies**: `winston`, `app-config`

**Usage**:
```typescript
import logger from '@shared/utils/logger'

// Log levels
logger.error('Critical error', { error: err, context: 'auth' })
logger.warn('Warning message', { userId: 123 })
logger.info('Info message', { action: 'file-upload' })
logger.debug('Debug details', { data: complexObject })

// Structured logging
logger.info('User logged in', {
  userId: user.id,
  email: user.email,
  timestamp: Date.now()
})

// Error logging with stack trace
try {
  await riskyOperation()
} catch (error) {
  logger.error('Operation failed', { error, operation: 'riskyOperation' })
  throw error
}
```

**Configuration**:
- Development: Logs to console with colors
- Production: Logs to files (`error.log`, `combined.log`)
- Log level controlled by `LOG_LEVEL` env var

### `utils/performance.ts`
**Purpose**: Performance monitoring utilities  
**Exports**: `startPerformanceMeasure()`, `endPerformanceMeasure()`, `getMemoryUsage()`, `formatBytes()`  
**Dependencies**: None (uses Node.js built-ins)

**Usage**:
```typescript
import {
  startPerformanceMeasure,
  endPerformanceMeasure,
  getMemoryUsage,
  formatBytes
} from '@shared/utils/performance'

// Measure operation duration
startPerformanceMeasure('database-query')
await db.query('SELECT * FROM users')
const duration = endPerformanceMeasure('database-query')
console.log(`Query took ${duration}ms`)

// Get memory usage
const memory = getMemoryUsage()
console.log(`Heap used: ${formatBytes(memory.heapUsed)}`)
console.log(`Total: ${formatBytes(memory.total)}`)

// Format bytes
formatBytes(1024)           // "1.00 KB"
formatBytes(1048576)        // "1.00 MB"
formatBytes(1073741824)     // "1.00 GB"
formatBytes(1536, 0)        // "2 KB" (no decimals)
```

## Planned Additions

### `types/` (Phase 2 P1)
TypeScript type definitions:
- `system.ts` - System capability types
- `user.ts` - User data types
- `file.ts` - File metadata types
- `sync.ts` - Sync operation types

### `schemas/` (Phase 2 P4)
Zod validation schemas:
- `file-schemas.ts` - File validation
- `auth-schemas.ts` - Auth validation
- `config-schemas.ts` - Config validation

### `errors/` (Phase 2 P5)
Custom error classes:
- `app-errors.ts` - Application-specific errors
- `error-handler.ts` - Global error handler

## Architecture

### Environment-Agnostic Code
All code in `shared/` must work in both:
- **Main Process** (Node.js environment)
- **Renderer Process** (Browser environment)

### What NOT to Include
- ❌ Electron-specific APIs (use in `main/` instead)
- ❌ React components (use in `renderer/` instead)
- ❌ DOM manipulation (use in `renderer/` instead)
- ❌ File system operations (use in `services/` instead)

### What TO Include
- ✅ Pure functions
- ✅ Type definitions
- ✅ Validation schemas
- ✅ Constants
- ✅ Utilities that work in both environments

## Testing

### Test Location
Tests are in: `src/__tests__/shared/`

### Running Tests
```bash
npm test -- shared
```

### Current Coverage
- `config/app-config.ts`: 100% (2/2 tests passing)
- `config/env-validator.ts`: 100% (7/7 tests passing)
- `utils/performance.ts`: 100% (12/12 tests passing)

## Common Patterns

### Creating a Utility Function
```typescript
// shared/utils/string-utils.ts
export function capitalize(str: string): string {
  return str.charAt(0).toUpperCase() + str.slice(1)
}

export function truncate(str: string, maxLength: number): string {
  if (str.length <= maxLength) return str
  return str.slice(0, maxLength - 3) + '...'
}
```

### Creating a Type Definition
```typescript
// shared/types/user.ts
export interface User {
  id: string
  email: string
  name: string
  createdAt: Date
}

export type UserRole = 'admin' | 'user' | 'guest'
```

### Creating a Validation Schema
```typescript
// shared/schemas/user-schemas.ts
import { z } from 'zod'

export const UserSchema = z.object({
  id: z.string().uuid(),
  email: z.string().email(),
  name: z.string().min(1).max(100),
  createdAt: z.date()
})

export type User = z.infer<typeof UserSchema>
```

## Best Practices

### ✅ DO
- Keep functions pure (no side effects)
- Export types and interfaces
- Use Zod for runtime validation
- Document all exports with JSDoc
- Write tests for all utilities

### ❌ DON'T
- Import Electron APIs
- Import React
- Access file system directly
- Use browser-only APIs (localStorage, etc.)
- Use Node.js-only APIs (fs, path, etc.) without checks

## Related Documentation

- [Source Overview](../README.md)
- [Main Process](../main/README.md)
- [Renderer Process](../renderer/README.md)
- [Services](../services/README.md)

---

**Last Updated**: 2024-11-30  
**Status**: Core utilities in place, types/schemas/errors to be added in Phase 2
