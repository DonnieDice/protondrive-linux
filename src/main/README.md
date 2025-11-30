# Main Process

## Purpose

The main process is the Electron application's Node.js backend. It has full system access and coordinates all services, manages windows, handles system integration, and communicates with the renderer process via IPC.

## Responsibilities

- Window lifecycle management (create, show, hide, close)
- System integration (tray, notifications, auto-updater)
- Service coordination (storage, auth, sync)
- IPC message handling
- Analytics and error tracking

## Directory Structure

```
main/
├── index.ts              # Main entry point
├── analytics.ts          # Aptabase analytics integration
├── auto-updater.ts       # Electron auto-updater
├── window-manager.ts     # Window creation and management
└── utils/
    └── app-utils.ts      # Utility functions (quit, restart, etc.)
```

## Files

### `index.ts`
**Purpose**: Application entry point, initializes all services and creates main window  
**Exports**: None (entry point)  
**Key Functions**:
- `app.whenReady()` - Initialize services and create window
- `app.on('window-all-closed')` - Handle app quit
- `app.on('activate')` - Handle macOS reactivation

**Usage**:
```typescript
// This file is the entry point - it runs automatically
// Services are initialized in order:
// 1. Logger
// 2. Storage
// 3. Analytics
// 4. Window Manager
```

### `analytics.ts`
**Purpose**: Aptabase analytics integration for usage tracking  
**Exports**: `initializeAnalytics()`, `recordAnalyticsEvent()`  
**Dependencies**: `@aptabase/electron`, `@shared/config/app-config`

**Usage**:
```typescript
import { initializeAnalytics, recordAnalyticsEvent } from '@main/analytics'

// Initialize (called once at startup)
initializeAnalytics()

// Track events
recordAnalyticsEvent('App Started', { platform: 'linux' })
recordAnalyticsEvent('File Uploaded', { size: '1.5MB' })
```

### `auto-updater.ts`
**Purpose**: Electron auto-updater integration for automatic app updates  
**Exports**: `initializeAutoUpdater()`  
**Dependencies**: `electron-updater`

**Usage**:
```typescript
import { initializeAutoUpdater } from '@main/auto-updater'

// Initialize (called once at startup)
initializeAutoUpdater()

// Auto-updater will:
// - Check for updates on startup
// - Download updates in background
// - Notify user when update is ready
// - Install on next app restart
```

### `window-manager.ts`
**Purpose**: Creates and manages application windows  
**Exports**: `createMainWindow()`, `getMainWindow()`  
**Dependencies**: `electron`

**Usage**:
```typescript
import { createMainWindow, getMainWindow } from '@main/window-manager'

// Create main window
const window = await createMainWindow()

// Get existing window
const existingWindow = getMainWindow()
if (existingWindow) {
  existingWindow.focus()
}
```

### `utils/app-utils.ts`
**Purpose**: Utility functions for app lifecycle management  
**Exports**: `quitApp()`, `restartApp()`, `getAppVersion()`  
**Dependencies**: `electron`

**Usage**:
```typescript
import { quitApp, restartApp, getAppVersion } from '@main/utils/app-utils'

// Quit the application
quitApp()

// Restart the application
restartApp()

// Get app version
const version = getAppVersion() // e.g., "1.0.0"
```

## Architecture

### Initialization Flow
```
1. app.whenReady()
2. Initialize Logger
3. Initialize Storage Service
4. Initialize Analytics
5. Initialize Auto-Updater
6. Create Main Window
7. Load Renderer
```

### IPC Communication
```
Renderer → IPC → Main Process → Services → Response → Renderer
```

## Testing

### Test Location
Tests are in: `src/__tests__/main/`

### Running Tests
```bash
npm test -- main
```

### Current Coverage
- analytics.ts: 100% (5/5 tests passing)

## Common Tasks

### Adding a New IPC Handler
```typescript
// In index.ts
import { ipcMain } from 'electron'

ipcMain.handle('my-channel', async (event, data) => {
  // Validate input
  // Call service
  // Return result
  return { success: true }
})
```

### Creating a New Window
```typescript
// In window-manager.ts
import { BrowserWindow } from 'electron'

export function createSettingsWindow() {
  const window = new BrowserWindow({
    width: 800,
    height: 600,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      preload: path.join(__dirname, '../preload.js')
    }
  })
  
  window.loadFile('settings.html')
  return window
}
```

## Security

### Context Isolation
All windows MUST have:
- `contextIsolation: true`
- `nodeIntegration: false`
- `sandbox: true`
- `preload` script for IPC

### Input Validation
All IPC handlers MUST validate input using Zod schemas.

## Related Documentation

- [Source Overview](../README.md)
- [Services](../services/README.md)
- [Preload Script](../preload.ts)
- [AGENTS.md](../../AGENTS.md)

---

**Last Updated**: 2024-11-30  
**Status**: Active Development
