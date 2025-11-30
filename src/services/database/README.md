# Database Services

## Purpose

Database migration system and schema management for SQLite database.

## Files

### `migrations.ts`
**Purpose**: Database migration runner with version tracking  
**Exports**: `applyMigrations()`, `getCurrentSchemaVersion()`, `setSchemaVersion()`, `loadMigrations()`

**Usage**:
```typescript
import { applyMigrations, getCurrentSchemaVersion } from '@services/database/migrations'

// Get current schema version
const version = getCurrentSchemaVersion(db)

// Apply all pending migrations
await applyMigrations(db)
```

**Features**:
- Sequential migration execution
- Transaction-based (rollback on error)
- Version tracking via PRAGMA user_version
- Idempotent (safe to run multiple times)

## Migration Files

### `migrations/` Directory
SQL migration files are stored in `src/services/database/migrations/`:
- `001_initial_schema.sql` - Initial database schema
- `002_indexes.sql` - Performance indexes
- Future migrations...

**Naming Convention**: `{number}_{description}.sql`

## Testing

**Tests**: 10/10 passing ✅  
**Location**: `src/__tests__/services/database/migrations.test.ts`

## Related Documentation

- [Services Layer](../README.md)
- [Storage Service](../storage-service.ts)

---

**Last Updated**: 2024-11-30
