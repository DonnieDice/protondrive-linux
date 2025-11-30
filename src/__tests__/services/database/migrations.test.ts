// src/__tests__/services/database/migrations.test.ts

// Global manual mocks
jest.mock('path');
jest.mock('fs');

// Full mock for logger.ts to bypass its internal dependencies (like winston and path)
jest.mock('@shared/utils/logger', () => ({
  __esModule: true,
  default: {
    info: jest.fn(),
    error: jest.fn(),
    debug: jest.fn(),
    warn: jest.fn(),
    // Provide a mocked winston.format object directly
    format: {
      combine: jest.fn(),
      timestamp: jest.fn(),
      printf: jest.fn(),
      colorize: jest.fn(),
      json: jest.fn(),
    },
    transports: {
      File: jest.fn(),
      Console: jest.fn(),
    },
  },
}));

// Critical: Full manual mock of storage-service to avoid real module loading
jest.mock('@services/storage-service', () => {
  const mockDb = {
    exec: jest.fn(),
    prepare: jest.fn(() => ({
      get: jest.fn(),
      run: jest.fn(),
      all: jest.fn(),
    })),
    transaction: jest.fn((cb: any) => cb()),
    close: jest.fn(),
    backup: jest.fn(),
  };

  return {
    getDbInstance: jest.fn(() => mockDb),
    initializeDatabase: jest.fn().mockResolvedValue(undefined),
    runInTransaction: jest.fn((cb: any) => cb()),
    runQuery: jest.fn(),
    runQueryWithParams: jest.fn(),
  };
});


import path from 'path';
import fs from 'fs';
import * as storageService from '@services/storage-service';
import logger from '@shared/utils/logger'; // Import default export of mock
import { applyMigrations } from '@services/database/migrations';

const mockPathJoin = path.join as jest.Mock;
const mockReaddirSync = fs.readdirSync as jest.Mock;
const mockReadFileSync = fs.readFileSync as jest.Mock;
const mockLogger = logger as jest.Mocked<any>;

let mockDb: any;

describe('database migrations', () => {
  beforeEach(() => {
    jest.clearAllMocks();

    mockDb = {
      exec: jest.fn(),
      prepare: jest.fn((sql: string) => {
        const statement = {
          get: jest.fn(),
          run: jest.fn(),
          all: jest.fn(),
        };

        if (sql === 'PRAGMA user_version') {
          statement.get.mockReturnValue({ user_version: 0 }); // Default initial version
        } else if (sql.includes('SELECT version FROM schema_migrations')) {
          statement.all.mockReturnValue([]); // Default no migrations
        } else if (sql.includes('CREATE TABLE IF NOT EXISTS schema_migrations')) {
          statement.run.mockReturnValue({ changes: 1 }); // For CREATE TABLE
        } else if (sql.includes('INSERT INTO schema_migrations')) {
          statement.run.mockReturnValue({ changes: 1 }); // For INSERT
        } else if (sql.includes('PRAGMA user_version =')) {
          statement.run.mockReturnValue({ changes: 1 }); // For setting PRAGMA user_version
        }

        return statement;
      }),
      transaction: jest.fn((cb: any) => cb()), // Returns the callback itself
      close: jest.fn(),
      backup: jest.fn(),
    };

    mockGetDbInstance.mockReturnValue(mockDb);
    mockRunInTransaction.mockImplementation((cb: any) => cb());
    mockRunQuery.mockImplementation((sql: string) => {
      if (sql.includes('SELECT version FROM schema_migrations')) return [];
      if (sql.includes('PRAGMA user_version')) return [{ user_version: 0 }];
      return { changes: 1, lastInsertRowid: 0 };
    });

    mockReaddirSync.mockReturnValue([]);
    mockReadFileSync.mockReturnValue('');
    (path.join as jest.Mock).mockImplementation((...parts) => parts.join('/'));
  });

  it('creates schema_migrations table if not exists', () => {
    applyMigrations();
    expect(mockDb.exec).toHaveBeenCalledWith(expect.stringContaining('CREATE TABLE IF NOT EXISTS schema_migrations'));
  });

  it('returns the current user_version from PRAGMA', () => {
    mockDb.prepare('PRAGMA user_version').get.mockReturnValue({ user_version: 7 });
    applyMigrations();
    expect(mockDb.prepare).toHaveBeenCalledWith('PRAGMA user_version');
  });

  it('updates the PRAGMA user_version', () => {
    mockReaddirSync.mockReturnValue(['001_init.sql']);
    mockReadFileSync.mockReturnValue('CREATE TABLE users(id INTEGER);');
    applyMigrations();
    expect(mockDb.exec).toHaveBeenCalledWith('PRAGMA user_version = 1');
  });

  it('applies new migrations in order and updates schema version', () => {
    mockReaddirSync.mockReturnValue(['001.sql', '002.sql']);
    mockReadFileSync.mockImplementation((path: string) =>
      path.includes('001') ? 'CREATE TABLE a;' : 'CREATE TABLE b;'
    );

    applyMigrations();

    expect(mockRunInTransaction).toHaveBeenCalledTimes(2);
    expect(mockRunQuery).toHaveBeenCalledWith('CREATE TABLE a;');
    expect(mockRunQuery).toHaveBeenCalledWith('CREATE TABLE b;');
    expect(mockDb.exec).toHaveBeenCalledWith('PRAGMA user_version = 2');
  });

  it('only applies new migrations (skips already applied ones)', () => {
    mockReaddirSync.mockReturnValue(['001.sql', '002.sql']);
    mockReadFileSync.mockReturnValue('CREATE TABLE b;');
    mockRunQuery.mockImplementation((sql: string) => {
      if (sql.includes('SELECT version FROM schema_migrations')) {
        return [{ version: 1 }];
      }
      return { changes: 1 };
    });

    applyMigrations();

    expect(mockRunInTransaction).toHaveBeenCalledTimes(1);
    expect(mockRunQuery).toHaveBeenCalledWith('CREATE TABLE b;');
    expect(mockDb.exec).toHaveBeenCalledWith('PRAGMA user_version = 2');
  });

  it('handles migration failures correctly (transaction rollback)', () => {
    mockReaddirSync.mockReturnValue(['001.sql', '002.sql']);
    mockReadFileSync.mockImplementation((path: string) =>
      path.includes('002') ? 'SYNTAX ERROR!!!' : 'CREATE TABLE a;'
    );
    mockRunQuery.mockImplementation((sql: string) => {
      if (sql === 'SYNTAX ERROR!!!') throw new Error('SQL syntax error');
      return { changes: 1 };
    });

    expect(() => applyMigrations()).toThrow('SQL syntax error');
    expect(mockRunInTransaction).toHaveBeenCalledTimes(1); // Only first migration attempted
  });
});