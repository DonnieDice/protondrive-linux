# Tests Directory

## Purpose

Contains all test files for the ProtonDrive Linux application. Tests are organized to mirror the `src/` directory structure, making it easy to find tests for any given source file.

## Responsibilities

- Unit tests for services, utilities, and components
- Integration tests for service interactions
- E2E tests for user workflows (Playwright)
- Mock implementations for external dependencies
- Test fixtures and helpers

## Directory Structure

```
__tests__/
├── main/                   # Main process tests
│   └── analytics.test.ts
├── renderer/               # Renderer process tests (to be added)
├── shared/                 # Shared code tests
│   ├── config/
│   │   ├── app-config.test.ts
│   │   └── env-validator.test.ts
│   └── utils/
│       └── performance.test.ts
├── services/               # Service layer tests
│   ├── storage-service.test.ts
│   ├── backup-service.test.ts
│   └── database/
│       └── migrations.test.ts
└── __mocks__/              # Mock implementations
    ├── @main/utils/
    │   └── app-utils.ts
    ├── @shared/utils/
    │   └── logger.ts
    ├── @aptabase/
    │   └── electron.ts
    ├── better-sqlite3.ts
    ├── fs.ts
    └── path.ts
```

## Test Statistics

### Current Coverage
```
Test Suites: 7 passed, 7 total
Tests:       85 passed, 85 total
Coverage:    100% of active tests passing ✅
```

### By Module
| Module | Tests | Status |
|--------|-------|--------|
| Analytics | 5/5 | ✅ 100% |
| Storage Service | 20/20 | ✅ 100% |
| Backup Service | 29/29 | ✅ 100% |
| Database Migrations | 10/10 | ✅ 100% |
| App Config | 2/2 | ✅ 100% |
| Env Validator | 7/7 | ✅ 100% |
| Performance Utils | 12/12 | ✅ 100% |

## Running Tests

### All Tests
```bash
npm test
```

### Specific Test File
```bash
npm test -- storage-service.test.ts
```

### Specific Test Suite
```bash
npm test -- --testNamePattern="BackupService"
```

### Watch Mode
```bash
npm test -- --watch
```

### With Coverage
```bash
npm test -- --coverage
```

## Test Structure

### Unit Test Example
```typescript
// __tests__/services/example-service.test.ts
import { ExampleService } from '@services/example-service'

describe('ExampleService', () => {
  let service: ExampleService
  
  beforeEach(() => {
    service = new ExampleService()
  })
  
  afterEach(() => {
    jest.clearAllMocks()
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
  })
})
```

### Integration Test Example
```typescript
// __tests__/integration/storage-backup.test.ts
import { getStorageService } from '@services/storage-service'
import { getBackupService } from '@services/backup-service'

describe('Storage + Backup Integration', () => {
  it('should backup and restore database', async () => {
    const storage = getStorageService()
    const backup = getBackupService()
    
    await storage.initialize()
    await backup.initialize()
    
    // Create data
    await storage.runQuery('INSERT INTO users (name) VALUES (?)', ['Alice'])
    
    // Backup
    await backup.createBackup('test')
    
    // Modify data
    await storage.runQuery('DELETE FROM users')
    
    // Restore
    await backup.restoreBackup('backup_test.sqlite')
    
    // Verify
    const users = await storage.getAllRows('SELECT * FROM users')
    expect(users).toHaveLength(1)
    expect(users[0].name).toBe('Alice')
  })
})
```

## Mocking

### Mock Directory (`__mocks__/`)

Contains mock implementations of external dependencies:

#### `@shared/utils/logger.ts`
```typescript
export default {
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  debug: jest.fn(),
}
```

#### `better-sqlite3.ts`
```typescript
export default jest.fn().mockImplementation(() => ({
  prepare: jest.fn().mockReturnValue({
    get: jest.fn(),
    all: jest.fn(),
    run: jest.fn(),
  }),
  exec: jest.fn(),
  close: jest.fn(),
}))
```

#### `fs.ts`
```typescript
const actualFs = jest.requireActual('fs')

export default {
  ...actualFs,
  existsSync: jest.fn(),
  mkdirSync: jest.fn(),
  readdirSync: jest.fn(),
  statSync: jest.fn(),
  unlinkSync: jest.fn(),
}
```

### Using Mocks in Tests
```typescript
import logger from '@shared/utils/logger'

// Mock is automatically applied
jest.mock('@shared/utils/logger')

describe('MyService', () => {
  it('should log errors', () => {
    service.doSomething()
    expect(logger.error).toHaveBeenCalledWith('Error message', expect.any(Object))
  })
})
```

## Test Patterns

### AAA Pattern (Arrange, Act, Assert)
```typescript
it('should do something', () => {
  // Arrange
  const input = 'test'
  const expected = 'TEST'
  
  // Act
  const result = service.transform(input)
  
  // Assert
  expect(result).toBe(expected)
})
```

### Testing Async Code
```typescript
it('should handle async operations', async () => {
  const result = await service.asyncOperation()
  expect(result).toBeDefined()
})
```

### Testing Errors
```typescript
it('should throw error on invalid input', async () => {
  await expect(service.operation(null)).rejects.toThrow('Invalid input')
})
```

### Testing Callbacks
```typescript
it('should call callback', (done) => {
  service.operation((result) => {
    expect(result).toBe('success')
    done()
  })
})
```

## Configuration

### Jest Config (`jest.config.js`)
```javascript
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testMatch: ['**/__tests__/**/*.test.ts'],
  moduleNameMapper: {
    '^@main/(.*)$': '<rootDir>/src/main/$1',
    '^@renderer/(.*)$': '<rootDir>/src/renderer/$1',
    '^@shared/(.*)$': '<rootDir>/src/shared/$1',
    '^@services/(.*)$': '<rootDir>/src/services/$1',
  },
  collectCoverageFrom: [
    'src/**/*.{ts,tsx}',
    '!src/**/*.d.ts',
    '!src/**/__tests__/**',
  ],
}
```

## Best Practices

### ✅ DO
- Write tests for all new code
- Follow AAA pattern (Arrange, Act, Assert)
- Use descriptive test names
- Test edge cases and error conditions
- Mock external dependencies
- Keep tests isolated and independent
- Clean up resources in afterEach
- Aim for 80%+ code coverage

### ❌ DON'T
- Test implementation details
- Write tests that depend on other tests
- Skip error case testing
- Leave tests commented out
- Use real external services
- Hardcode file paths or timestamps
- Ignore failing tests

## Coverage Goals

### Minimum Coverage
- **Overall**: 80%
- **Services**: 90%
- **Utilities**: 85%
- **Critical paths**: 100%

### Current Coverage
- **Overall**: 100% of active tests passing
- **Services**: 100% (59/59 tests)
- **Shared**: 100% (21/21 tests)
- **Main**: 100% (5/5 tests)

## E2E Testing (Planned)

### Playwright Tests
```typescript
// __tests__/e2e/login.spec.ts
import { test, expect } from '@playwright/test'

test('user can login', async ({ page }) => {
  await page.goto('/')
  
  await page.fill('[data-testid="email"]', 'user@example.com')
  await page.fill('[data-testid="password"]', 'password')
  await page.click('[data-testid="login-button"]')
  
  await expect(page.locator('[data-testid="user-menu"]')).toBeVisible()
})
```

### Running E2E Tests
```bash
npm run test:e2e
```

## Troubleshooting

### Tests Failing Locally
1. Clear Jest cache: `npm test -- --clearCache`
2. Delete node_modules and reinstall: `rm -rf node_modules && npm install`
3. Check for mock pollution: Ensure `afterEach` cleans up mocks

### Mock Not Working
1. Verify mock path matches import path
2. Check that `jest.mock()` is called before imports
3. Use `jest.resetModules()` if needed

### Timeout Errors
1. Increase timeout: `jest.setTimeout(10000)`
2. Check for unresolved promises
3. Ensure async operations complete

## Related Documentation

- [Source Overview](../README.md)
- [Services](../services/README.md)
- [Jest Documentation](https://jestjs.io/)
- [Playwright Documentation](https://playwright.dev/)

---

**Last Updated**: 2024-11-30  
**Status**: 85/85 tests passing, E2E tests planned for Phase 3
