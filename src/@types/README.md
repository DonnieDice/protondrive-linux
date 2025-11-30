# TypeScript Type Definitions

## Purpose

Custom TypeScript type definitions for packages that don't provide their own types.

## Directory Structure

```
@types/
└── aptabase__electron/
    └── index.d.ts
```

## Type Definitions

### `aptabase__electron/index.d.ts`
TypeScript definitions for `@aptabase/electron` package.

**Exports**:
- `init(appKey: string): void`
- `trackEvent(eventName: string, props?: Record<string, any>): void`

## Usage

Types are automatically picked up by TypeScript when importing the package:

```typescript
import { init, trackEvent } from '@aptabase/electron'

// TypeScript knows the types
init('app-key')
trackEvent('event', { prop: 'value' })
```

## Related Documentation

- [Source Overview](../README.md)

---

**Last Updated**: 2024-11-30
