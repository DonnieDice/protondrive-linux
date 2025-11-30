# Database Migrations

## Purpose

SQL migration files for database schema evolution. Migrations are applied sequentially by the migration runner.

## Migration Files

Currently no migration SQL files exist yet. They will be created in Phase 2 P2.

## Planned Migrations

### `001_initial_schema.sql`
- Create initial database tables
- Set up primary keys and constraints
- Initial indexes

### `002_indexes.sql`
- Performance indexes
- Foreign key indexes
- Query optimization indexes

## Naming Convention

Format: `{number}_{description}.sql`

Examples:
- `001_initial_schema.sql`
- `002_indexes.sql`
- `003_add_sync_table.sql`

## Migration Format

```sql
-- Migration: 001_initial_schema.sql
-- Description: Initial database schema

CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS files (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  path TEXT NOT NULL,
  size INTEGER NOT NULL,
  modified_at INTEGER NOT NULL
);
```

## How Migrations Work

1. Migration runner reads all `.sql` files from this directory
2. Files are sorted numerically by prefix
3. Current schema version is checked (PRAGMA user_version)
4. Only new migrations (version > current) are applied
5. Each migration runs in a transaction
6. Schema version is updated after successful migration

## Related Documentation

- [Migration Runner](../migrations.ts)
- [Database Services](../README.md)

---

**Last Updated**: 2024-11-30
