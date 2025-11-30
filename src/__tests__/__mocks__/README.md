# Test Mocks

## Purpose

Mock implementations of external dependencies for testing. Mocks are automatically applied by Jest when tests import the real modules.

## Directory Structure

```
__mocks__/
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

## Mock Files

### `@main/utils/app-utils.ts`
Mocks app lifecycle functions (quit, restart, version)

### `@shared/utils/logger.ts`
Mocks Winston logger with jest.fn() for all methods

### `@aptabase/electron.ts`
Mocks Aptabase analytics SDK

### `better-sqlite3.ts`
Mocks SQLite database with prepare/exec/close methods

### `fs.ts`
Mocks Node.js file system module

### `path.ts`
Mocks Node.js path module

## Usage

Mocks are automatically applied when you use `jest.mock()`:

```typescript
jest.mock('@shared/utils/logger')

import logger from '@shared/utils/logger'

// logger is now the mock
expect(logger.info).toHaveBeenCalled()
```

## Related Documentation

- [Tests Overview](../README.md)

---

**Last Updated**: 2024-11-30
