# Configuration

## Purpose

Application configuration management and environment variable validation.

## Files

### `app-config.ts`
**Purpose**: Centralized application configuration  
**Exports**: `appConfig` (frozen object)

**Usage**:
```typescript
import { appConfig } from '@shared/config/app-config'

console.log(appConfig.NODE_ENV)        // 'development' | 'production' | 'test'
console.log(appConfig.LOG_LEVEL)       // 'error' | 'warn' | 'info' | 'debug'
console.log(appConfig.APTABASE_APP_KEY) // Optional analytics key
```

### `env-validator.ts`
**Purpose**: Validates environment variables using Zod  
**Exports**: `getValidatedEnv()`, `envSchema`

**Usage**:
```typescript
import { getValidatedEnv } from '@shared/config/env-validator'

const env = getValidatedEnv()
// Throws if validation fails
```

## Environment Variables

### Required
- `NODE_ENV` - 'development' | 'production' | 'test'

### Optional
- `LOG_LEVEL` - Log verbosity (default: 'info')
- `APTABASE_APP_KEY` - Analytics key
- `SENTRY_DSN` - Error tracking DSN

## Testing

**Tests**: 9/9 passing ✅
- `app-config.test.ts`: 2/2
- `env-validator.test.ts`: 7/7

## Related Documentation

- [Shared Code](../README.md)
- [Environment Validator Tests](../../__tests__/shared/config/)

---

**Last Updated**: 2024-11-30
