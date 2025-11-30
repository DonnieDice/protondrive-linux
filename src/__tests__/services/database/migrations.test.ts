import * as migrations from '../../../services/database/migrations';
import * as storageService from '../../../services/storage-service';
import logger from '../../../shared/utils/logger';
import * as fs from 'fs';

// Mock dependencies
jest.mock('../../../services/storage-service');
jest.mock('../../../shared/utils/logger');
jest.mock('fs');

describe('database migrations', () => {
  let mockDb: any;
  let mockExec: jest.Mock;
  let mockPrepare: jest.Mock;
  let mockGet: jest.Mock;
  let mockRunInTransaction: jest.Mock;
  let mockRunQuery: jest.Mock;

  beforeEach(() => {
    jest.clearAllMocks();

    // Set up database mocks
    mockExec = jest.fn();
    mockGet = jest.fn().mockReturnValue({ user_version: 0 });
    mockPrepare = jest.fn().mockReturnValue({ get: mockGet });
    
    mockDb = {
      exec: mockExec,
      prepare: mockPrepare,
    };

    (storageService.getDbInstance as jest.Mock).mockReturnValue(mockDb);

    // Set up storage service mocks
    mockRunInTransaction = jest.fn((callback: () => void) => {
      callback(); // Execute the callback immediately
    });
    mockRunQuery = jest.fn();

    (storageService.runInTransaction as jest.Mock).mockImplementation(mockRunInTransaction);
    (storageService.runQuery as jest.Mock).mockImplementation(mockRunQuery);

    // Mock filesystem to return no migration files by default
    (fs.readdirSync as jest.Mock).mockReturnValue([]);
    (fs.readFileSync as jest.Mock).mockReturnValue('');
  });

  describe('ensureMigrationsTable', () => {
    it('creates schema_migrations table if not exists', () => {
      migrations.ensureMigrationsTable();

      expect(mockDb.exec).toHaveBeenCalledWith(
        expect.stringContaining('CREATE TABLE IF NOT EXISTS schema_migrations')
      );
    });
  });

  describe('getCurrentSchemaVersion', () => {
    it('returns the current user_version from PRAGMA', () => {
      mockGet.mockReturnValue({ user_version: 5 });

      const version = migrations.getCurrentSchemaVersion();

      expect(mockDb.prepare).toHaveBeenCalledWith('PRAGMA user_version');
      expect(version).toBe(5);
    });
  });

  describe('setSchemaVersion', () => {
    it('updates the PRAGMA user_version', () => {
      migrations.setSchemaVersion(10);

      expect(mockDb.exec).toHaveBeenCalledWith('PRAGMA user_version = 10');
    });
  });

  describe('loadMigrations', () => {
    it('loads and sorts migration files correctly', () => {
      // Mock filesystem to return test migration files
      (fs.readdirSync as jest.Mock).mockReturnValue([
        '002_second.sql',
        '001_first.sql',
        '003_third.sql',
        'not_a_migration.txt', // Should be filtered out
      ]);

      (fs.readFileSync as jest.Mock).mockImplementation((filePath: string) => {
        if (filePath.includes('001_first.sql')) return 'CREATE TABLE first;';
        if (filePath.includes('002_second.sql')) return 'CREATE TABLE second;';
        if (filePath.includes('003_third.sql')) return 'CREATE TABLE third;';
        return '';
      });

      const result = migrations.loadMigrations();

      expect(result).toEqual([
        { version: 1, name: 'first', sql: 'CREATE TABLE first;' },
        { version: 2, name: 'second', sql: 'CREATE TABLE second;' },
        { version: 3, name: 'third', sql: 'CREATE TABLE third;' },
      ]);
    });

    it('returns empty array when no migration files exist', () => {
      (fs.readdirSync as jest.Mock).mockReturnValue([]);

      const result = migrations.loadMigrations();

      expect(result).toEqual([]);
    });
  });

  describe('applyMigrations', () => {
    it('applies new migrations in order and updates schema version', () => {
      // Mock filesystem to return test migrations
      (fs.readdirSync as jest.Mock).mockReturnValue([
        '001_create_table_a.sql',
        '002_create_table_b.sql',
      ]);

      (fs.readFileSync as jest.Mock).mockImplementation((filePath: string) => {
        if (filePath.includes('001_create_table_a.sql')) return 'CREATE TABLE a;';
        if (filePath.includes('002_create_table_b.sql')) return 'CREATE TABLE b;';
        return '';
      });

      // Current version is 0
      mockGet.mockReturnValue({ user_version: 0 });

      migrations.applyMigrations();

      // Should run in transaction twice (once per migration)
      expect(mockRunInTransaction).toHaveBeenCalledTimes(2);
      
      // Should execute both migration SQLs
      expect(mockRunQuery).toHaveBeenCalledWith('CREATE TABLE a;');
      expect(mockRunQuery).toHaveBeenCalledWith('CREATE TABLE b;');
      
      // Should record migrations in schema_migrations table
      expect(mockRunQuery).toHaveBeenCalledWith(
        'INSERT INTO schema_migrations (version, name) VALUES (?, ?)',
        1,
        'create table a'
      );
      expect(mockRunQuery).toHaveBeenCalledWith(
        'INSERT INTO schema_migrations (version, name) VALUES (?, ?)',
        2,
        'create table b'
      );
      
      // Should update schema version twice
      expect(mockDb.exec).toHaveBeenCalledWith('PRAGMA user_version = 1');
      expect(mockDb.exec).toHaveBeenCalledWith('PRAGMA user_version = 2');
    });

    it('only applies new migrations (skips already applied ones)', () => {
      // Mock filesystem to return test migrations
      (fs.readdirSync as jest.Mock).mockReturnValue([
        '001_create_table_a.sql',
        '002_create_table_b.sql',
      ]);

      (fs.readFileSync as jest.Mock).mockImplementation((filePath: string) => {
        if (filePath.includes('001_create_table_a.sql')) return 'CREATE TABLE a;';
        if (filePath.includes('002_create_table_b.sql')) return 'CREATE TABLE b;';
        return '';
      });

      // Current version is 1 (first migration already applied)
      mockGet.mockReturnValue({ user_version: 1 });

      migrations.applyMigrations();

      // Should only run transaction once (for migration 2)
      expect(mockRunInTransaction).toHaveBeenCalledTimes(1);
      
      // Should only execute second migration SQL
      expect(mockRunQuery).not.toHaveBeenCalledWith('CREATE TABLE a;');
      expect(mockRunQuery).toHaveBeenCalledWith('CREATE TABLE b;');
      
      // Should only update to version 2
      expect(mockDb.exec).toHaveBeenCalledWith('PRAGMA user_version = 2');
    });

    it('handles migration failures correctly (transaction rollback)', () => {
      // Mock filesystem to return test migrations
      (fs.readdirSync as jest.Mock).mockReturnValue([
        '001_create_table_a.sql',
        '002_bad_migration.sql',
      ]);

      (fs.readFileSync as jest.Mock).mockImplementation((filePath: string) => {
        if (filePath.includes('001_create_table_a.sql')) return 'CREATE TABLE a;';
        if (filePath.includes('002_bad_migration.sql')) return 'INVALID SQL;';
        return '';
      });

      // Current version is 0
      mockGet.mockReturnValue({ user_version: 0 });

      // Make the second migration fail
      mockRunQuery.mockImplementation((sql: string) => {
        if (sql === 'INVALID SQL;') {
          throw new Error('SQL syntax error');
        }
      });

      // Should throw the error
      expect(() => migrations.applyMigrations()).toThrow('SQL syntax error');
      
      // Should have attempted both migrations (first succeeds, second fails)
      expect(mockRunInTransaction).toHaveBeenCalledTimes(2);
    });

    it('does nothing when no migrations are pending', () => {
      // No migration files
      (fs.readdirSync as jest.Mock).mockReturnValue([]);
      
      // Current version is 0
      mockGet.mockReturnValue({ user_version: 0 });

      migrations.applyMigrations();

      // ensureMigrationsTable() is still called
      expect(mockDb.exec).toHaveBeenCalledWith(
        expect.stringContaining('CREATE TABLE IF NOT EXISTS schema_migrations')
      );
      
      // No migration transactions should run
      expect(mockRunInTransaction).not.toHaveBeenCalled();
      expect(mockRunQuery).not.toHaveBeenCalled();
    });

    it('does nothing when all migrations are already applied', () => {
      // Mock filesystem to return test migrations
      (fs.readdirSync as jest.Mock).mockReturnValue([
        '001_create_table_a.sql',
        '002_create_table_b.sql',
      ]);

      (fs.readFileSync as jest.Mock).mockImplementation((filePath: string) => {
        if (filePath.includes('001_create_table_a.sql')) return 'CREATE TABLE a;';
        if (filePath.includes('002_create_table_b.sql')) return 'CREATE TABLE b;';
        return '';
      });

      // Current version is 2 (all migrations already applied)
      mockGet.mockReturnValue({ user_version: 2 });

      migrations.applyMigrations();

      // ensureMigrationsTable() is still called
      expect(mockDb.exec).toHaveBeenCalledWith(
        expect.stringContaining('CREATE TABLE IF NOT EXISTS schema_migrations')
      );

      // No migration transactions should run
      expect(mockRunInTransaction).not.toHaveBeenCalled();
      expect(mockRunQuery).not.toHaveBeenCalled();
    });
  });
});
