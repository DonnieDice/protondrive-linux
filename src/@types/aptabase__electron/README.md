# Aptabase Electron Type Definitions

## Purpose

TypeScript type definitions for the `@aptabase/electron` analytics package.

## File

### `index.d.ts`
Declares module types for `@aptabase/electron`.

**Exports**:
```typescript
export function init(appKey: string): void
export function trackEvent(eventName: string, props?: Record<string, any>): void
```

## Related Documentation

- [Type Definitions](../README.md)
- [Analytics](../../main/analytics.ts)

---

**Last Updated**: 2024-11-30
