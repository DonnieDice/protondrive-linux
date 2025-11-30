import { getDbInstance, runInTransaction, runQuery } from '../storage-service';
import logger from '../../shared/utils/logger';
import * as fs from 'fs';
import * as path from 'path';

const MIGRATIONS_DIR = path.join(__dirname, 'migrations');

interface Migration {
  version: number;
  name: string;
  sql: string;
}

/**
 * Ensures the migrations table exists to track applied migrations.
 */
export function ensureMigrationsTable(): void {
  const db = getDbInstance();
  db.exec(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      applied_at TEXT DEFAULT CURRENT_TIMESTAMP
    );
  `);
}

/**
 * Gets the current schema version from the database.
 * @returns The current schema version.
 */
export function getCurrentSchemaVersion(): number {
  const db = getDbInstance();
  const result = db.prepare('PRAGMA user_version').get() as { user_version: number };
  return result.user_version;
}

/**
 * Sets the schema version in the database.
 * @param version The new schema version.
 */
export function setSchemaVersion(version: number): void {
  const db = getDbInstance();
  db.exec(`PRAGMA user_version = ${version}`);
}

/**
 * Loads all SQL migration files from the migrations directory.
 * @returns An array of Migration objects, sorted by version.
 */
export function loadMigrations(): Migration[] {
  const migrationFiles = fs.readdirSync(MIGRATIONS_DIR)
    .filter(file => file.match(/^\d{3}_.*\.sql$/))
    .sort(); // Sorts alphabetically, which should be numerically for 001, 002, etc.

  return migrationFiles.map(file => {
    const filePath = path.join(MIGRATIONS_DIR, file);
    const version = parseInt(file.substring(0, 3), 10);
    const name = file.substring(4, file.length - 4).replace(/_/g, ' '); // e.g., "001_initial_schema.sql" -> "initial schema"
    const sql = fs.readFileSync(filePath, 'utf8');
    return { version, name, sql };
  });
}

/**
 * Applies all pending database migrations.
 */
export const applyMigrations = (): void => {
  ensureMigrationsTable();
  const currentDbVersion = getCurrentSchemaVersion();
  const migrations = loadMigrations();
  let latestAppliedVersion = currentDbVersion;

  logger.info(`Current database schema version: ${currentDbVersion}`);

  for (const migration of migrations) {
    if (migration.version > currentDbVersion) {
      try {
        runInTransaction(() => {
          logger.info(`Applying migration v${migration.version}: ${migration.name}`);
          // Execute the migration SQL
          runQuery(migration.sql);

          // Record the migration in the schema_migrations table
          runQuery(
            'INSERT INTO schema_migrations (version, name) VALUES (?, ?)',
            migration.version,
            migration.name
          );

          // Update the user_version PRAGMA
          setSchemaVersion(migration.version);
          latestAppliedVersion = migration.version;
        });
        logger.info(`Successfully applied migration v${migration.version}`);
      } catch (error) {
        logger.error(`Failed to apply migration v${migration.version}: ${migration.name}`, error);
        // Rethrow the error to stop further execution if a migration fails
        throw error;
      }
    }
  }

  if (latestAppliedVersion === currentDbVersion) {
    logger.info('No new migrations to apply. Database is up to date.');
  } else {
    logger.info(`Database migrations complete. New schema version: ${latestAppliedVersion}`);
  }
};
