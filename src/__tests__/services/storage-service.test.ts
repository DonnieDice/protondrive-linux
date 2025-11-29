import {
  initializeDatabase,
  closeDatabase,
  runQuery,
  getRow,
  getAllRows,
  runInTransaction,
  getDbInstance,
} from '@services/storage-service';
import Database from 'better-sqlite3';
import logger from '@shared/utils/logger';
import { app } from 'electron';
import * as path from 'path';
import * as fs from 'fs';

// Mock electron's app.getPath
jest.mock('electron', () => ({
  app: {
    getPath: jest.fn((name: string) => {
      if (name === 'userData') {
        return path.join(__dirname, '.temp_user_data');
      }
      return '';
    }),
    quit: jest.fn(),
  },
}));

// Mock the logger
jest.mock('@shared/utils/logger', () => ({
  __esModule: true,
  default: {
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  },
}));

const TEST_DB_PATH = path.join(__dirname, '.temp_user_data', 'protondrive.sqlite');
const TEMP_USER_DATA_DIR = path.join(__dirname, '.temp_user_data');

describe('storage-service', () => {
  beforeEach(() => {
    // Clear mock calls
    jest.clearAllMocks();
    // Ensure the temp user data directory is clean before each test
    if (fs.existsSync(TEMP_USER_DATA_DIR)) {
      fs.rmSync(TEMP_USER_DATA_DIR, { recursive: true, force: true });
    }
    fs.mkdirSync(TEMP_USER_DATA_DIR, { recursive: true });

    // Reset the database instance to null before each test to ensure initializeDatabase is called
    // @ts-ignore - Private member access for testing
    closeDatabase(); // Ensure any previous DB connection is closed
  });

  afterAll(() => {
    // Clean up the temp user data directory after all tests
    if (fs.existsSync(TEMP_USER_DATA_DIR)) {
      fs.rmSync(TEMP_USER_DATA_DIR, { recursive: true, force: true });
    }
  });

  it('should initialize and close the database successfully', () => {
    expect(() => initializeDatabase()).not.toThrow();
    expect(fs.existsSync(TEST_DB_PATH)).toBe(true);
    expect(logger.info).toHaveBeenCalledWith(expect.stringContaining('Database successfully opened'));

    expect(() => closeDatabase()).not.toThrow();
    expect(logger.info).toHaveBeenCalledWith('Database connection closed.');
  });

  it('should not re-initialize the database if already initialized', () => {
    initializeDatabase();
    initializeDatabase(); // Call again
    expect(logger.warn).toHaveBeenCalledWith('Database already initialized.');
  });

  it('should quit the app if database initialization fails', () => {
    // Simulate failure by making better-sqlite3 throw on creation
    jest.spyOn(Database.prototype, 'constructor').mockImplementation(() => {
        throw new Error('Mock DB Init Failure');
    });

    expect(() => initializeDatabase()).not.toThrow(); // initializeDatabase catches and calls app.quit
    expect(logger.error).toHaveBeenCalledWith(expect.stringContaining('Failed to initialize database'), expect.any(Error));
    expect(app.quit).toHaveBeenCalledTimes(1);

    // Restore mock to prevent affecting other tests
    jest.restoreAllMocks();
  });

  it('should execute DDL queries via runQuery', () => {
    initializeDatabase();
    const createTableSql = 'CREATE TABLE test_table (id INTEGER PRIMARY KEY, name TEXT)';
    const result = runQuery(createTableSql);
    expect(result.changes).toBe(0); // DDL usually has 0 changes
    expect(() => runQuery('INSERT INTO test_table (name) VALUES (?)', 'test')).not.toThrow();
  });

  it('should execute INSERT, UPDATE, DELETE queries via runQuery', () => {
    initializeDatabase();
    runQuery('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)');

    const insertResult = runQuery('INSERT INTO users (name) VALUES (?)', 'Alice');
    expect(insertResult.changes).toBe(1);
    expect(insertResult.lastInsertRowid).toBe(1);

    const updateResult = runQuery('UPDATE users SET name = ? WHERE id = ?', 'Bob', 1);
    expect(updateResult.changes).toBe(1);

    const deleteResult = runQuery('DELETE FROM users WHERE id = ?', 1);
    expect(deleteResult.changes).toBe(1);
  });

  it('should fetch a single row via getRow', () => {
    initializeDatabase();
    runQuery('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
    runQuery('INSERT INTO settings (key, value) VALUES (?, ?)', 'theme', 'dark');

    const setting = getRow<{ key: string; value: string }>('SELECT * FROM settings WHERE key = ?', 'theme');
    expect(setting).toEqual({ key: 'theme', value: 'dark' });

    const notFound = getRow('SELECT * FROM settings WHERE key = ?', 'nonexistent');
    expect(notFound).toBeUndefined();
  });

  it('should fetch all rows via getAllRows', () => {
    initializeDatabase();
    runQuery('CREATE TABLE items (id INTEGER PRIMARY KEY, description TEXT)');
    runQuery('INSERT INTO items (description) VALUES (?), (?)', 'Item A', 'Item B');

    const items = getAllRows<{ id: number; description: string }>('SELECT * FROM items');
    expect(items).toEqual([
      { id: 1, description: 'Item A' },
      { id: 2, description: 'Item B' },
    ]);
  });

  it('should throw error if query is run before database initialization', () => {
    expect(() => runQuery('SELECT 1')).toThrow('Database is not initialized. Call initializeDatabase() first.');
    expect(() => getRow('SELECT 1')).toThrow('Database is not initialized. Call initializeDatabase() first.');
    expect(() => getAllRows('SELECT 1')).toThrow('Database is not initialized. Call initializeDatabase() first.');
    expect(() => runInTransaction(() => {})).toThrow('Database is not initialized. Call initializeDatabase() first.');
    expect(() => getDbInstance()).toThrow('Database is not initialized. Call initializeDatabase() first.');
  });

  describe('runInTransaction', () => {
    it('should commit transaction on success', () => {
      initializeDatabase();
      runQuery('CREATE TABLE accounts (id INTEGER PRIMARY KEY, balance INTEGER)');
      runQuery('INSERT INTO accounts (balance) VALUES (100), (200)');

      runInTransaction(() => {
        runQuery('UPDATE accounts SET balance = balance - 50 WHERE id = 1');
        runQuery('UPDATE accounts SET balance = balance + 50 WHERE id = 2');
      });

      const balance1 = getRow<{ balance: number }>('SELECT balance FROM accounts WHERE id = 1');
      const balance2 = getRow<{ balance: number }>('SELECT balance FROM accounts WHERE id = 2');

      expect(balance1?.balance).toBe(50);
      expect(balance2?.balance).toBe(250);
    });

    it('should rollback transaction on error', () => {
      initializeDatabase();
      runQuery('CREATE TABLE accounts (id INTEGER PRIMARY KEY, balance INTEGER)');
      runQuery('INSERT INTO accounts (balance) VALUES (100), (200)');

      expect(() => {
        runInTransaction(() => {
          runQuery('UPDATE accounts SET balance = balance - 50 WHERE id = 1');
          throw new Error('Transaction failed intentionally');
          runQuery('UPDATE accounts SET balance = balance + 50 WHERE id = 2'); // This should not be reached
        });
      }).toThrow('Transaction failed intentionally');

      const balance1 = getRow<{ balance: number }>('SELECT balance FROM accounts WHERE id = 1');
      const balance2 = getRow<{ balance: number }>('SELECT balance FROM accounts WHERE id = 2');

      expect(balance1?.balance).toBe(100); // Should be rolled back
      expect(balance2?.balance).toBe(200); // Should be rolled back
      expect(logger.error).toHaveBeenCalledWith('Transaction failed and was rolled back.', expect.any(Error));
    });
  });

  describe('getDbInstance', () => {
    it('should return the database instance if initialized', () => {
      initializeDatabase();
      const dbInstance = getDbInstance();
      expect(dbInstance).toBeInstanceOf(Database);
      expect(dbInstance.open).toBe(true);
    });
  });
});
