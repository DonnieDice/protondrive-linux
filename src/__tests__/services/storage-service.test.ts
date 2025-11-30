import {
  initializeDatabase,
  closeDatabase,
  runQuery,
  getRow,
  getAllRows,
  runInTransaction,
  getDbInstance,
} from '@services/storage-service';
import Database from 'better-sqlite3'; // This will be the actual BetterSqlite3 constructor
import logger from '@shared/utils/logger';
import { app } from 'electron';
import * as path from 'path';
import * as fs from 'fs';

// --- Mock better-sqlite3 ---
const mockRunResult = { changes: 0, lastInsertRowid: 0 };
const mockStatement = {
  run: jest.fn(() => mockRunResult),
  get: jest.fn(),
  all: jest.fn(),
};

// Mock transaction function: better-sqlite3 transaction method returns a function
// which then needs to be called with the actual transaction callback.
// Define a variable to store the callback passed to db.transaction
let storedTransactionCallback: (() => any) | undefined;

const mockDbTransactionRunner = jest.fn(() => {
  if (!storedTransactionCallback) {
    throw new Error('Transaction runner called without a stored callback.');
  }
  return storedTransactionCallback(); // Execute the stored callback
});

const mockDatabaseInstance = {
  pragma: jest.fn(),
  exec: jest.fn(),
  prepare: jest.fn(() => mockStatement),
  transaction: jest.fn((callback: () => any) => {
    storedTransactionCallback = callback; // Store the callback passed to transaction
    return mockDbTransactionRunner; // Return the runner function
  }),
  close: jest.fn(),
  backup: jest.fn(),
  open: true, // Simulate open state
  name: 'mock.sqlite', // Simulate db path
};

// We need a variable to control if the mock constructor should throw
let shouldMockDbConstructorThrow = false;
let mockDbConstructorError: Error | undefined;

jest.mock('better-sqlite3', () => {
  // Return a mock constructor function
  return jest.fn((dbPath: string, options?: any) => {
    if (shouldMockDbConstructorThrow) {
      throw mockDbConstructorError || new Error('Mock DB Init Failure');
    }
    // Set the name property based on dbPath for testing getDbInstance().name
    mockDatabaseInstance.name = dbPath;
    return mockDatabaseInstance;
  });
});

// --- Mock electron's app.getPath ---
jest.mock('electron', () => ({
  app: {
    getPath: jest.fn((name: string) => {
      if (name === 'userData') {
        // Use a static path here to avoid 'path' being undefined in mock context
        return '/mock/user/data';
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

const MOCK_USER_DATA_PATH = '/tmp/mock-user-data';
const MOCK_TEST_DB_PATH = path.join(MOCK_USER_DATA_PATH, 'protondrive.sqlite');
// Note: TEMP_USER_DATA_DIR is for cleanup and actual file system interaction,
// which is independent of the mocked app.getPath() in initializeDatabase's internal logic.
const TEMP_USER_DATA_DIR = path.join(__dirname, '.temp_user_data');


describe('storage-service', () => {
  // Cast the mocked BetterSqlite3 constructor
  const MockBetterSqlite3 = Database as jest.MockedFunction<typeof Database>;
  
  beforeEach(() => {
    // Reset all mocks before each test
    jest.clearAllMocks();
    mockStatement.run.mockClear();
    mockStatement.get.mockClear();
    mockStatement.all.mockClear();
    mockDatabaseInstance.pragma.mockClear();
    mockDatabaseInstance.exec.mockClear();
    mockDatabaseInstance.prepare.mockClear();
    mockDatabaseInstance.transaction.mockClear();
    mockDatabaseInstance.close.mockClear();
    mockDatabaseInstance.backup.mockClear();
    mockDatabaseInstance.open = true; // Reset open state
    mockDatabaseInstance.name = 'mock.sqlite'; // Reset name
    mockDbTransactionRunner.mockClear(); // Clear runner calls
    storedTransactionCallback = undefined; // Reset the stored callback

    shouldMockDbConstructorThrow = false;
    mockDbConstructorError = undefined;

    // Ensure the temp user data directory is clean before each test
    if (fs.existsSync(TEMP_USER_DATA_DIR)) {
      fs.rmSync(TEMP_USER_DATA_DIR, { recursive: true, force: true });
    }
    fs.mkdirSync(TEMP_USER_DATA_DIR, { recursive: true });

    // Reset the database instance to null before each test to ensure initializeDatabase is called
    // @ts-ignore - Private member access for testing
    closeDatabase(); // Ensure any previous DB connection is closed by storage-service
  });

  afterAll(() => {
    // Clean up the temp user data directory after all tests
    if (fs.existsSync(TEMP_USER_DATA_DIR)) {
      fs.rmSync(TEMP_USER_DATA_DIR, { recursive: true, force: true });
    }
  });

  describe('initializeDatabase', () => {
    it('should initialize the database successfully', () => {
      initializeDatabase();
      expect(MockBetterSqlite3).toHaveBeenCalledTimes(1);
      expect(MockBetterSqlite3).toHaveBeenCalledWith(MOCK_TEST_DB_PATH, expect.any(Object));
      expect(mockDatabaseInstance.pragma).toHaveBeenCalledWith('journal_mode = WAL');
      expect(mockDatabaseInstance.pragma).toHaveBeenCalledWith('foreign_keys = ON');
      expect(logger.info).toHaveBeenCalledWith(expect.stringContaining('Database successfully opened'));
    });

    it('should not re-initialize the database if already initialized', () => {
      initializeDatabase();
      initializeDatabase(); // Call again
      expect(MockBetterSqlite3).toHaveBeenCalledTimes(1); // Should only be called once
      expect(logger.warn).toHaveBeenCalledWith('Database already initialized.');
    });

    it('should quit the app if database initialization fails', () => {
      shouldMockDbConstructorThrow = true;
      mockDbConstructorError = new Error('Simulated DB Init Failure');

      initializeDatabase(); 
      // Expect the mock constructor to have been called and then thrown
      expect(MockBetterSqlite3).toHaveBeenCalledTimes(1);
      // The function that calls initializeDatabase should have caught the error
      expect(logger.error).toHaveBeenCalledWith(expect.stringContaining('Failed to initialize database'), expect.any(Error));
      // quitApp is imported from app-utils, not app.quit directly
      const { quitApp } = require('@main/utils/app-utils');
      expect(quitApp).toHaveBeenCalledTimes(1);
    });
  });

  describe('closeDatabase', () => {
    it('should close the database successfully', () => {
      initializeDatabase();
      closeDatabase();
      expect(mockDatabaseInstance.close).toHaveBeenCalledTimes(1);
      expect(logger.info).toHaveBeenCalledWith('Database connection closed.');
    });

    it('should do nothing if database is not initialized', () => {
      closeDatabase(); // Call without initializing
      expect(mockDatabaseInstance.close).not.toHaveBeenCalled();
    });
  });

  describe('runQuery', () => {
    beforeEach(() => {
      initializeDatabase();
      jest.clearAllMocks(); // Clear calls from setup
    });

    it('should execute a SQL query via runQuery', () => {
      const sql = 'CREATE TABLE test (id INTEGER)';
      runQuery(sql);
      expect(mockDatabaseInstance.prepare).toHaveBeenCalledWith(sql);
      expect(mockStatement.run).toHaveBeenCalledTimes(1);
    });

    it('should pass parameters to the query', () => {
      const sql = 'INSERT INTO test (id) VALUES (?)';
      runQuery(sql, 123);
      expect(mockStatement.run).toHaveBeenCalledWith(123);
    });

    it('should return the result of the statement run', () => {
      const sql = 'DELETE FROM test';
      mockRunResult.changes = 5;
      mockRunResult.lastInsertRowid = 0;
      const result = runQuery(sql);
      expect(result).toEqual({ changes: 5, lastInsertRowid: 0 });
    });

    it('should throw error if query is run before database initialization', () => {
      // @ts-ignore
      closeDatabase(); // Ensure DB is uninitialized
      expect(() => runQuery('SELECT 1')).toThrow('Database is not initialized. Call initializeDatabase() first.');
    });
  });

  describe('getRow', () => {
    beforeEach(() => {
      initializeDatabase();
      jest.clearAllMocks();
    });

    it('should fetch a single row', () => {
      const sql = 'SELECT * FROM test WHERE id = ?';
      const row = { id: 1, name: 'Test' };
      mockStatement.get.mockReturnValueOnce(row);
      const result = getRow(sql, 1);
      expect(mockDatabaseInstance.prepare).toHaveBeenCalledWith(sql);
      expect(mockStatement.get).toHaveBeenCalledWith(1);
      expect(result).toEqual(row);
    });

    it('should return undefined if no row is found', () => {
      mockStatement.get.mockReturnValueOnce(undefined);
      const result = getRow('SELECT * FROM test WHERE id = ?', 99);
      expect(result).toBeUndefined();
    });

    it('should throw error if called before database initialization', () => {
      // @ts-ignore
      closeDatabase();
      expect(() => getRow('SELECT 1')).toThrow('Database is not initialized. Call initializeDatabase() first.');
    });
  });

  describe('getAllRows', () => {
    beforeEach(() => {
      initializeDatabase();
      jest.clearAllMocks();
    });

    it('should fetch all rows', () => {
      const sql = 'SELECT * FROM test';
      const rows = [{ id: 1 }, { id: 2 }];
      mockStatement.all.mockReturnValueOnce(rows);
      const result = getAllRows(sql);
      expect(mockDatabaseInstance.prepare).toHaveBeenCalledWith(sql);
      expect(mockStatement.all).toHaveBeenCalledTimes(1);
      expect(result).toEqual(rows);
    });

    it('should return an empty array if no rows are found', () => {
      mockStatement.all.mockReturnValueOnce([]);
      const result = getAllRows('SELECT * FROM test');
      expect(result).toEqual([]);
    });

    it('should throw error if called before database initialization', () => {
      // @ts-ignore
      closeDatabase();
      expect(() => getAllRows('SELECT 1')).toThrow('Database is not initialized. Call initializeDatabase() first.');
    });
  });

  describe('runInTransaction', () => {
    beforeEach(() => {
      initializeDatabase();
      jest.clearAllMocks();
    });

    it('should commit transaction on successful callback', () => {
      const callback = jest.fn(() => 'success');
      const result = runInTransaction(callback);

      expect(mockDatabaseInstance.transaction).toHaveBeenCalledTimes(1);
      expect(mockDbTransactionRunner).toHaveBeenCalledTimes(1); // The function returned by transaction is called
      expect(callback).toHaveBeenCalledTimes(1);
      expect(result).toBe('success');
    });

    it('should rollback transaction on error', () => {
      const error = new Error('Rollback test');
      const failingCallback = jest.fn(() => { throw error; });

      expect(() => runInTransaction(failingCallback)).toThrow(error);
      expect(mockDatabaseInstance.transaction).toHaveBeenCalledTimes(1);
      expect(mockDbTransactionRunner).toHaveBeenCalledTimes(1);
      expect(failingCallback).toHaveBeenCalledTimes(1);
      expect(logger.error).toHaveBeenCalledWith('Transaction failed and was rolled back.', error);
    });

    it('should throw error if called before database initialization', () => {
      // @ts-ignore
      closeDatabase();
      expect(() => runInTransaction(() => {})).toThrow('Database is not initialized. Call initializeDatabase() first.');
    });
  });

  describe('getDbInstance', () => {
    beforeEach(() => {
      initializeDatabase();
      jest.clearAllMocks();
    });

    it('should return the database instance if initialized', () => {
      const dbInstance = getDbInstance();
      expect(dbInstance).toBe(mockDatabaseInstance);
      expect(dbInstance.open).toBe(true);
    });

    it('should throw error if called before database initialization', () => {
      // @ts-ignore
      closeDatabase();
      expect(() => getDbInstance()).toThrow('Database is not initialized. Call initializeDatabase() first.');
    });
  });
});
