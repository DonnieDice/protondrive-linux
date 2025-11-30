# Main Process Utilities

## Purpose

Utility functions for the Electron main process, including app lifecycle management and system operations.

## Files

### `app-utils.ts`
**Purpose**: Application lifecycle utility functions  
**Exports**: `quitApp()`, `restartApp()`, `getAppVersion()`

**Usage**:
```typescript
import { quitApp, restartApp, getAppVersion } from '@main/utils/app-utils'

// Quit the application
quitApp()

// Restart the application
restartApp()

// Get app version
const version = getAppVersion() // "1.0.0"
```

## Related Documentation

- [Main Process](../README.md)
- [Source Overview](../../README.md)

---

**Last Updated**: 2024-11-30
