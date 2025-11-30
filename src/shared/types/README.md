# Type Definitions

## Purpose

TypeScript type definitions for shared data structures used across the application.

## Files

### `system.ts`
**Purpose**: System capability and performance profile types  
**Exports**:
- `SystemCapabilities` - Hardware detection results
- `StorageType` - Storage device types
- `PerformanceProfile` - Performance configuration
- `PerformanceProfileLevel` - Profile levels
- `MemoryUsage` - Memory statistics
- `PerformanceMeasurement` - Performance timing
- `StoragePerformanceTest` - Storage test results

**Usage**:
```typescript
import {
  SystemCapabilities,
  PerformanceProfile
} from '@shared/types/system'

const capabilities: SystemCapabilities = {
  totalRAM: 8192,
  availableRAM: 4096,
  cpuCores: 4,
  architecture: 'x64',
  storageType: 'SSD',
  platform: 'linux',
  osRelease: '5.15.0'
}
```

## Related Documentation

- [Shared Code](../README.md)
- [Performance Profiler](../utils/performance-profiler.ts)

---

**Last Updated**: 2024-11-30
