import Database from 'better-sqlite3';
import path from 'path';
import logger from '@shared/utils/logger';
import { getUserDataPath, quitApp } from '@main/utils/app-utils';

// Determine the database file path
const isDevelopment = process.env.NODE_ENV === 'development';
const userDataPath = getUserDataPath(); // This is usually ~/.config/<app-name> on Linux

// In development, the DB can be in the project root for easier access,
// but in production, it should be in the user data directory.
const dbFileName = 'protondrive.sqlite';
const dbPath = isDevelopment
  ? path.join(process.cwd(), dbFileName)
  : path.join(userDataPath, dbFileName);

let db: Database.Database | null = null;

/**
 * Initializes and opens the SQLite database connection.
 * If the database file does not exist, it will be created.
 */
export const initializeDatabase = (): void => {
  if (db) {
    logger.warn('Database already initialized.');
    return;
  }

  try {
    // Open the database in read-write mode, create if it doesn't exist
    db = new Database(dbPath, {
      verbose: isDevelopment ? (message) => logger.debug(`SQL: ${message}`) : undefined,
    });
    db.pragma('journal_mode = WAL'); // Use WAL mode for better concurrency and performance
    db.pragma('foreign_keys = ON'); // Enforce foreign key constraints
    logger.info(`Database successfully opened at: ${dbPath}`);
  } catch (error) {
    logger.error(`Failed to initialize database at ${dbPath}:`, error);
    // In a real application, you might want to show an error dialog and exit.
    quitApp();
  }
};

/**
 * Closes the SQLite database connection.
 */
export const closeDatabase = (): void => {
  if (db) {
    db.close();
    db = null;
    logger.info('Database connection closed.');
  }
};

/**
 * Executes a SQL query that does not return any rows (e.g., INSERT, UPDATE, DELETE, DDL).
 *
 * @param sql - The SQL query string.
 * @param params - Optional parameters for the query.
 * @returns The result object from `better-sqlite3` execution.
 */
export const runQuery = (sql: string, ...params: any[]): Database.RunResult => {
  if (!db) {
    throw new Error('Database is not initialized. Call initializeDatabase() first.');
  }
  try {
    const stmt = db.prepare(sql);
    return stmt.run(...params);
  } catch (error) {
    logger.error(`Error running SQL query: "${sql}" with params: ${JSON.stringify(params)}`, error);
    throw error;
  }
};

/**
 * Executes a SQL query that returns a single row.
 *
 * @param sql - The SQL query string.
 * @param params - Optional parameters for the query.
 * @returns The first row returned by the query, or undefined if no rows.
 */
export const getRow = <T>(sql: string, ...params: any[]): T | undefined => {
  if (!db) {
    throw new Error('Database is not initialized. Call initializeDatabase() first.');
  }
  try {
    const stmt = db.prepare(sql);
    return stmt.get(...params) as T | undefined;
  } catch (error) {
    logger.error(`Error getting row from SQL query: "${sql}" with params: ${JSON.stringify(params)}`, error);
    throw error;
  }
};

/**
 * Executes a SQL query that returns multiple rows.
 *
 * @param sql - The SQL query string.
 * @param params - Optional parameters for the query.
 * @returns An array of rows returned by the query.
 */
export const getAllRows = <T>(sql: string, ...params: any[]): T[] => {
  if (!db) {
    throw new Error('Database is not initialized. Call initializeDatabase() first.');
  }
  try {
    const stmt = db.prepare(sql);
    return stmt.all(...params) as T[];
  } catch (error) {
    logger.error(`Error getting all rows from SQL query: "${sql}" with params: ${JSON.stringify(params)}`, error);
    throw error;
  }
};

/**
 * Executes a SQL query within a transaction.
 *
 * @param callback - A function containing the SQL operations to perform within the transaction.
 *                   If the callback throws an error, the transaction will be rolled back.
 * @returns The return value of the callback function.
 */
export const runInTransaction = <T>(callback: () => T): T => {
  if (!db) {
    throw new Error('Database is not initialized. Call initializeDatabase() first.');
  }
  const transaction = db.transaction(callback);
  try {
    return transaction();
  } catch (error) {
    logger.error('Transaction failed and was rolled back.', error);
    throw error;
  }
};

/**
 * Exports the SQLite Database instance. Use with caution for advanced operations.
 * It's generally preferred to use the provided wrapper functions (runQuery, getRow, etc.).
 * @returns The `better-sqlite3` Database instance.
 */
export const getDbInstance = (): Database.Database => {
  if (!db) {
    throw new Error('Database is not initialized. Call initializeDatabase() first.');
  }
  return db;
};
