# Shared Utilities

## Purpose

Utility functions that work in both main and renderer processes.

## Files

### `logger.ts`
**Purpose**: Winston-based logging utility  
**Exports**: `logger` (default export)

**Usage**:
```typescript
import logger from '@shared/utils/logger'

logger.error('Error message', { error, context })
logger.warn('Warning', { userId: 123 })
logger.info('Info', { action: 'upload' })
logger.debug('Debug details', { data })
```

**Configuration**:
- Development: Console with colors
- Production: Files (error.log, combined.log)

### `performance.ts`
**Purpose**: Performance monitoring utilities  
**Exports**: `startPerformanceMeasure()`, `endPerformanceMeasure()`, `getMemoryUsage()`, `formatBytes()`

**Usage**:
```typescript
import {
  startPerformanceMeasure,
  endPerformanceMeasure,
  getMemoryUsage,
  formatBytes
} from '@shared/utils/performance'

// Measure duration
startPerformanceMeasure('operation')
await doSomething()
const ms = endPerformanceMeasure('operation')

// Memory usage
const memory = getMemoryUsage()
console.log(formatBytes(memory.heapUsed))
```

## Testing

**Tests**: 12/12 passing ✅  
**Location**: `src/__tests__/shared/utils/`

## Related Documentation

- [Shared Code](../README.md)
- [Performance Tests](../../__tests__/shared/utils/performance.test.ts)

---

**Last Updated**: 2024-11-30
