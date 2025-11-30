# Renderer Process

## Purpose

The renderer process is the Electron application's frontend, running in a Chromium browser environment with React. It provides the user interface with NO direct Node.js access for security. All system operations go through the secure IPC bridge.

## Responsibilities

- User interface rendering (React components)
- User interaction handling
- State management (Zustand)
- IPC communication with main process
- Client-side routing
- UI/UX animations and transitions

## Directory Structure

```
renderer/
├── index.tsx           # Renderer entry point
├── components/         # React components (to be created)
│   ├── ui/            # Reusable UI components
│   ├── auth/          # Authentication components
│   ├── files/         # File browser components
│   └── settings/      # Settings components
└── stores/            # Zustand state stores (to be created)
    ├── auth-store.ts
    ├── files-store.ts
    └── settings-store.ts
```

## Files

### `index.tsx`
**Purpose**: Renderer process entry point, mounts React app  
**Exports**: None (entry point)  
**Dependencies**: `react`, `react-dom`

**Current Implementation**:
```typescript
import React from 'react'
import { createRoot } from 'react-dom/client'

function App() {
  return (
    <div>
      <h1>ProtonDrive Linux</h1>
      <p>Welcome to ProtonDrive for Linux!</p>
    </div>
  )
}

const root = createRoot(document.getElementById('root')!)
root.render(<App />)
```

## Architecture

### Security Model
```
┌─────────────────────────────────────────┐
│         Renderer Process                │
│   - NO Node.js access                   │
│   - NO file system access               │
│   - NO direct system calls              │
│   - Sandboxed browser environment       │
└──────────────┬──────────────────────────┘
               │
               │ IPC via window.api
               │ (exposed by preload.ts)
               │
┌──────────────┴──────────────────────────┐
│         Main Process                    │
│   - Full system access                  │
│   - Services layer                      │
└─────────────────────────────────────────┘
```

### State Management (Zustand)
```typescript
// Example store structure (to be implemented)
import create from 'zustand'

interface AuthStore {
  user: User | null
  isAuthenticated: boolean
  login: (email: string, password: string) => Promise<void>
  logout: () => Promise<void>
}

export const useAuthStore = create<AuthStore>((set) => ({
  user: null,
  isAuthenticated: false,
  login: async (email, password) => {
    // Call IPC to main process
    const user = await window.api.auth.login(email, password)
    set({ user, isAuthenticated: true })
  },
  logout: async () => {
    await window.api.auth.logout()
    set({ user: null, isAuthenticated: false })
  }
}))
```

## Usage Examples

### Using IPC API
```typescript
// The window.api is exposed by preload.ts
// All system operations go through this secure bridge

// Example: Get app version
const version = await window.api.getAppVersion()

// Example: Open file dialog
const files = await window.api.openFileDialog()

// Example: Save settings
await window.api.saveSettings({ theme: 'dark' })
```

### Creating a Component
```typescript
import React from 'react'
import { useAuthStore } from '@renderer/stores/auth-store'

export function LoginForm() {
  const { login, isAuthenticated } = useAuthStore()
  const [email, setEmail] = React.useState('')
  const [password, setPassword] = React.useState('')
  
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    await login(email, password)
  }
  
  if (isAuthenticated) {
    return <div>Already logged in!</div>
  }
  
  return (
    <form onSubmit={handleSubmit}>
      <input
        type="email"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        placeholder="Email"
      />
      <input
        type="password"
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        placeholder="Password"
      />
      <button type="submit">Login</button>
    </form>
  )
}
```

### Using Zustand Store
```typescript
import { useAuthStore } from '@renderer/stores/auth-store'

function UserProfile() {
  // Subscribe to specific state
  const user = useAuthStore((state) => state.user)
  const logout = useAuthStore((state) => state.logout)
  
  return (
    <div>
      <h2>Welcome, {user?.name}</h2>
      <button onClick={logout}>Logout</button>
    </div>
  )
}
```

## Development

### Running in Dev Mode
```bash
npm start
# Opens Electron window with hot reload
```

### Building for Production
```bash
npm run build
# Compiles React app for production
```

## Planned Components

### UI Components (Phase 3 P0)
- `Button.tsx` - Reusable button component
- `Input.tsx` - Form input component
- `Modal.tsx` - Modal dialog component
- `Toast.tsx` - Toast notification component
- `Loading.tsx` - Loading spinner component

### Auth Components (Phase 3 P1)
- `LoginForm.tsx` - Login form
- `TwoFactorForm.tsx` - 2FA verification

### File Components (Phase 3 P3)
- `FileList.tsx` - File list view
- `FileItem.tsx` - Individual file item
- `FolderTree.tsx` - Folder tree navigation

### Settings Components (Phase 3 P2)
- `GeneralSettings.tsx` - General app settings
- `PerformanceSettings.tsx` - Performance tuning
- `AccountSettings.tsx` - Account management

## Styling

### Tailwind CSS (Planned)
```typescript
// Example with Tailwind classes
function Button({ children, onClick }) {
  return (
    <button
      onClick={onClick}
      className="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
    >
      {children}
    </button>
  )
}
```

## Testing

### Test Location
Tests will be in: `src/__tests__/renderer/`

### Running Tests
```bash
npm test -- renderer
```

### E2E Tests (Playwright)
```bash
npm run test:e2e
```

## Security Best Practices

### ✅ DO
- Use `window.api` for all system operations
- Validate user input before sending to main process
- Use React's built-in XSS protection
- Keep sensitive data in main process

### ❌ DON'T
- Try to access Node.js APIs directly (won't work)
- Store sensitive data in renderer state
- Bypass the IPC bridge
- Use `dangerouslySetInnerHTML` without sanitization

## Performance

### Optimization Tips
- Use React.memo for expensive components
- Lazy load routes and components
- Virtualize long lists
- Debounce user input
- Use Zustand selectors to prevent unnecessary re-renders

### Performance Budget
- Target: 60 FPS on low-end hardware
- Bundle size: < 500KB (gzipped)
- Time to interactive: < 2s

## Related Documentation

- [Source Overview](../README.md)
- [Preload Script](../preload.ts)
- [Main Process](../main/README.md)
- [Shared Code](../shared/README.md)

---

**Last Updated**: 2024-11-30  
**Status**: Basic structure in place, components to be implemented in Phase 3
