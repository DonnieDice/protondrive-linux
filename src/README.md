# Source Code Directory

## Purpose

This is the main source code directory for ProtonDrive Linux. It contains all TypeScript/JavaScript code for the Electron application, organized by process type (main, renderer, shared) and functionality.

## Directory Structure

```
src/
├── main/              # Electron main process (Node.js)
├── renderer/          # Electron renderer process (React UI)
├── preload.ts         # Preload script (IPC bridge)
├── shared/            # Code shared between main and renderer
├── services/          # Business logic services
├── __tests__/         # Test files (mirrors src structure)
└── @types/            # TypeScript type definitions
```

## Key Files

### `preload.ts`
**Purpose**: Secure bridge between main and renderer processes  
**Exports**: IPC API exposed to renderer via `contextBridge`  
**Security**: Validates all IPC messages, prevents direct Node.js access

### `renderer.d.ts`
**Purpose**: TypeScript definitions for renderer global types  
**Exports**: Window interface extensions for IPC API

## Subdirectories

### `main/`
Electron main process code - runs in Node.js environment with full system access. Handles window management, system integration, and coordinates services.

[See main/README.md](./main/README.md)

### `renderer/`
Electron renderer process code - runs in Chromium with React. Provides the user interface with no direct Node.js access (security).

[See renderer/README.md](./renderer/README.md)

### `shared/`
Code shared between main and renderer processes. Includes utilities, configuration, and types that work in both environments.

[See shared/README.md](./shared/README.md)

### `services/`
Business logic services for ProtonDrive integration, local storage, file sync, and authentication. Used by main process.

[See services/README.md](./services/README.md)

### `__tests__/`
Test files organized to mirror the src/ structure. Includes unit tests, integration tests, and mocks.

[See __tests__/README.md](./__tests__/README.md)

### `@types/`
Custom TypeScript type definitions for packages that don't provide their own types.

## Architecture

### Process Separation
```
┌─────────────────────────────────────────┐
│         Renderer Process (React)        │
│   - UI Components                       │
│   - No Node.js Access (security)        │
└──────────────┬──────────────────────────┘
               │ IPC (contextBridge)
┌──────────────┴──────────────────────────┐
│           Preload Script                │
│   - Secure IPC Bridge                   │
│   - Input Validation                    │
└──────────────┬──────────────────────────┘
               │
┌──────────────┴──────────────────────────┐
│         Main Process (Node.js)          │
│   - Services Layer                      │
│   - System Integration                  │
└─────────────────────────────────────────┘
```

### Import Aliases
- `@main/*` → `src/main/*`
- `@renderer/*` → `src/renderer/*`
- `@shared/*` → `src/shared/*`
- `@services/*` → `src/services/*`

## Usage Example

### Main Process
```typescript
import { StorageService } from '@services/storage-service'
import logger from '@shared/utils/logger'

const storage = new StorageService()
await storage.initialize()
logger.info('Storage initialized')
```

### Renderer Process
```typescript
import React from 'react'
import { useAuthStore } from '@renderer/stores/auth-store'

function App() {
  const { user } = useAuthStore()
  return <div>Hello {user?.name}</div>
}
```

### Shared Code
```typescript
import { appConfig } from '@shared/config/app-config'
import logger from '@shared/utils/logger'

logger.info('App starting', { env: appConfig.NODE_ENV })
```

## Development

### Running the App
```bash
npm start
```

### Running Tests
```bash
npm test
```

### Linting
```bash
npm run lint
```

## Related Documentation

- [Project README](../README.md)
- [Architecture Docs](../docs/architecture/)
- [AGENTS.md](../AGENTS.md) - Complete project context

---

**Last Updated**: 2024-11-30  
**Status**: Active Development
