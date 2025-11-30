// Mock dependencies FIRST before any imports
jest.mock('../../services/storage-service');
jest.mock('../../shared/utils/logger', () => ({
  default: {
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
    debug: jest.fn(),
  },
}));
jest.mock('better-sqlite3');

// Mock fs module
jest.mock('fs', () => ({
  existsSync: jest.fn(),
  mkdirSync: jest.fn(),
  readdirSync: jest.fn(),
  statSync: jest.fn(),
  copyFileSync: jest.fn(),
  unlinkSync: jest.fn(),
  stat: jest.fn((path, callback) => callback(null, { size: 0, mtime: new Date() })),
  createWriteStream: jest.fn(() => ({
    write: jest.fn(),
    end: jest.fn(),
    on: jest.fn(),
  })),
}));

// Mock electron
jest.mock('electron', () => ({
  app: {
    getPath: jest.fn(),
  },
}), { virtual: true });

// Now import after mocks are set up
import { BackupService, getBackupService, initializeBackupService } from '../../services/backup-service';
import * as storageService from '../../services/storage-service';
import * as fs from 'fs';
import * as path from 'path';
import logger from '../../shared/utils/logger';

describe('BackupService', () => {
  let backupService: BackupService;
  let mockDb: any;
  const mockBackupDir = '/mock/backup/dir';
  const mockUserDataPath = '/mock/user/data';

  beforeEach(() => {
    jest.clearAllMocks();

    // Mock electron app.getPath
    const { app } = require('electron');
    app.getPath.mockReturnValue(mockUserDataPath);

    // Mock database instance
    mockDb = {
      exec: jest.fn(),
      prepare: jest.fn().mockReturnValue({
        get: jest.fn().mockReturnValue({ user_version: 1 }),
      }),
      close: jest.fn(),
    };

    (storageService.getDbInstance as jest.Mock).mockReturnValue(mockDb);

    // Mock filesystem
    (fs.existsSync as jest.Mock).mockReturnValue(false);
    (fs.mkdirSync as jest.Mock).mockReturnValue(undefined);
    (fs.readdirSync as jest.Mock).mockReturnValue([]);
    (fs.statSync as jest.Mock).mockReturnValue({
      size: 1024,
      mtime: new Date('2024-01-01T00:00:00Z'),
    });
    (fs.copyFileSync as jest.Mock).mockReturnValue(undefined);
    (fs.unlinkSync as jest.Mock).mockReturnValue(undefined);

    // Create service with test config
    backupService = new BackupService({
      maxBackups: 3,
      backupDir: mockBackupDir,
    });
  });

  describe('initialize', () => {
    it('should create backup directory if it does not exist', async () => {
      (fs.existsSync as jest.Mock).mockReturnValue(false);

      await backupService.initialize();

      expect(fs.mkdirSync).toHaveBeenCalledWith(mockBackupDir, { recursive: true });
      expect(logger.info).toHaveBeenCalledWith(expect.stringContaining('Created backup directory'));
    });

    it('should not create backup directory if it already exists', async () => {
      (fs.existsSync as jest.Mock).mockReturnValue(true);

      await backupService.initialize();

      expect(fs.mkdirSync).not.toHaveBeenCalled();
    });

    it('should be idempotent (safe to call multiple times)', async () => {
      await backupService.initialize();
      await backupService.initialize();

      expect(fs.mkdirSync).toHaveBeenCalledTimes(1);
    });

    it('should throw error if directory creation fails', async () => {
      (fs.existsSync as jest.Mock).mockReturnValue(false);
      (fs.mkdirSync as jest.Mock).mockImplementation(() => {
        throw new Error('Permission denied');
      });

      await expect(backupService.initialize()).rejects.toThrow('Permission denied');
    });
  });

  describe('createBackup', () => {
    beforeEach(async () => {
      await backupService.initialize();
    });

    it('should create a backup with timestamp in filename', async () => {
      const mockDate = new Date('2024-01-15T10:30:00Z');
      jest.spyOn(global, 'Date').mockImplementation(() => mockDate as any);

      const metadata = await backupService.createBackup();

      expect(metadata.filename).toMatch(/protondrive_backup_2024-01-15T10-30-00-000Z\.sqlite/);
      expect(metadata.path).toBe(path.join(mockBackupDir, metadata.filename));
      expect(metadata.timestamp).toEqual(mockDate);
      expect(metadata.size).toBe(1024);
      expect(metadata.schemaVersion).toBe(1);
    });

    it('should include reason in filename if provided', async () => {
      const metadata = await backupService.createBackup('pre-migration');

      expect(metadata.filename).toMatch(/pre_migration/);
    });

    it('should sanitize reason string for filename', async () => {
      const metadata = await backupService.createBackup('before: migration #2');

      expect(metadata.filename).toMatch(/before__migration__2/);
    });

    it('should use VACUUM INTO for backup', async () => {
      await backupService.createBackup();

      expect(mockDb.exec).toHaveBeenCalledWith(
        expect.stringMatching(/VACUUM INTO/)
      );
    });

    it('should throw error if not initialized', async () => {
      const uninitializedService = new BackupService();

      await expect(uninitializedService.createBackup()).rejects.toThrow('not initialized');
    });

    it('should cleanup old backups after creating new one', async () => {
      // Mock existing backups
      (fs.readdirSync as jest.Mock).mockReturnValue([
        'backup1.sqlite',
        'backup2.sqlite',
        'backup3.sqlite',
        'backup4.sqlite',
      ]);

      await backupService.createBackup();

      // Should delete oldest backup (maxBackups = 3, so 4 total means 1 should be deleted)
      expect(fs.unlinkSync).toHaveBeenCalled();
    });
  });

  describe('listBackups', () => {
    beforeEach(async () => {
      await backupService.initialize();
    });

    it('should list all backup files', async () => {
      (fs.readdirSync as jest.Mock).mockReturnValue([
        'backup1.sqlite',
        'backup2.sqlite',
        'not_a_backup.txt', // Should be filtered out
      ]);

      const backups = await backupService.listBackups();

      expect(backups).toHaveLength(2);
      expect(backups[0].filename).toBe('backup1.sqlite');
      expect(backups[1].filename).toBe('backup2.sqlite');
    });

    it('should sort backups by timestamp (newest first)', async () => {
      (fs.readdirSync as jest.Mock).mockReturnValue([
        'old_backup.sqlite',
        'new_backup.sqlite',
      ]);

      (fs.statSync as jest.Mock).mockImplementation((filePath: string) => {
        if (filePath.includes('old_backup')) {
          return { size: 1024, mtime: new Date('2024-01-01') };
        }
        return { size: 2048, mtime: new Date('2024-01-15') };
      });

      const backups = await backupService.listBackups();

      expect(backups[0].filename).toBe('new_backup.sqlite');
      expect(backups[1].filename).toBe('old_backup.sqlite');
    });

    it('should return empty array if no backups exist', async () => {
      (fs.readdirSync as jest.Mock).mockReturnValue([]);

      const backups = await backupService.listBackups();

      expect(backups).toEqual([]);
    });

    it('should throw error if not initialized', async () => {
      const uninitializedService = new BackupService();

      await expect(uninitializedService.listBackups()).rejects.toThrow('not initialized');
    });
  });

  describe('restoreBackup', () => {
    beforeEach(async () => {
      await backupService.initialize();
    });

    it('should restore database from backup file', async () => {
      const backupPath = '/mock/backup/dir/backup.sqlite';
      (fs.existsSync as jest.Mock).mockReturnValue(true);

      await backupService.restoreBackup(backupPath);

      expect(mockDb.close).toHaveBeenCalled();
      expect(fs.copyFileSync).toHaveBeenCalledWith(
        backupPath,
        expect.stringContaining('protondrive.sqlite')
      );
    });

    it('should create emergency backup before restoring', async () => {
      const backupPath = '/mock/backup/dir/backup.sqlite';
      (fs.existsSync as jest.Mock).mockReturnValue(true);

      await backupService.restoreBackup(backupPath);

      expect(fs.copyFileSync).toHaveBeenCalledTimes(2); // Emergency backup + restore
      expect(fs.copyFileSync).toHaveBeenCalledWith(
        expect.stringContaining('protondrive.sqlite'),
        expect.stringMatching(/emergency_\d+\.sqlite/)
      );
    });

    it('should throw error if backup file does not exist', async () => {
      (fs.existsSync as jest.Mock).mockReturnValue(false);

      await expect(backupService.restoreBackup('/nonexistent/backup.sqlite'))
        .rejects.toThrow('Backup file not found');
    });

    it('should throw error if not initialized', async () => {
      const uninitializedService = new BackupService();

      await expect(uninitializedService.restoreBackup('/some/path'))
        .rejects.toThrow('not initialized');
    });
  });

  describe('deleteBackup', () => {
    beforeEach(async () => {
      await backupService.initialize();
    });

    it('should delete a backup file', async () => {
      const backupPath = path.join(mockBackupDir, 'backup.sqlite');
      (fs.existsSync as jest.Mock).mockReturnValue(true);

      await backupService.deleteBackup(backupPath);

      expect(fs.unlinkSync).toHaveBeenCalledWith(backupPath);
    });

    it('should throw error if backup file does not exist', async () => {
      (fs.existsSync as jest.Mock).mockReturnValue(false);

      await expect(backupService.deleteBackup('/nonexistent/backup.sqlite'))
        .rejects.toThrow('Backup file not found');
    });

    it('should throw error if trying to delete file outside backup directory', async () => {
      const outsidePath = '/some/other/dir/backup.sqlite';
      (fs.existsSync as jest.Mock).mockReturnValue(true);

      await expect(backupService.deleteBackup(outsidePath))
        .rejects.toThrow('outside of backup directory');
    });

    it('should throw error if not initialized', async () => {
      const uninitializedService = new BackupService();

      await expect(uninitializedService.deleteBackup('/some/path'))
        .rejects.toThrow('not initialized');
    });
  });

  describe('getTotalBackupSize', () => {
    beforeEach(async () => {
      await backupService.initialize();
    });

    it('should calculate total size of all backups', async () => {
      (fs.readdirSync as jest.Mock).mockReturnValue([
        'backup1.sqlite',
        'backup2.sqlite',
      ]);

      (fs.statSync as jest.Mock).mockImplementation((filePath: string) => {
        if (filePath.includes('backup1')) {
          return { size: 1024, mtime: new Date() };
        }
        return { size: 2048, mtime: new Date() };
      });

      const totalSize = await backupService.getTotalBackupSize();

      expect(totalSize).toBe(3072); // 1024 + 2048
    });

    it('should return 0 if no backups exist', async () => {
      (fs.readdirSync as jest.Mock).mockReturnValue([]);

      const totalSize = await backupService.getTotalBackupSize();

      expect(totalSize).toBe(0);
    });
  });

  describe('cleanup old backups', () => {
    beforeEach(async () => {
      await backupService.initialize();
    });

    it('should keep only maxBackups most recent backups', async () => {
      // Create 5 backups, maxBackups is 3
      (fs.readdirSync as jest.Mock).mockReturnValue([
        'backup1.sqlite',
        'backup2.sqlite',
        'backup3.sqlite',
        'backup4.sqlite',
        'backup5.sqlite',
      ]);

      (fs.statSync as jest.Mock).mockImplementation((filePath: string) => {
        const match = filePath.match(/backup(\d)/);
        const num = match ? parseInt(match[1]) : 0;
        return {
          size: 1024,
          mtime: new Date(2024, 0, num), // Different dates for each
        };
      });

      await backupService.createBackup();

      // Should delete 2 oldest backups (5 existing + 1 new = 6, keep 3 = delete 3)
      // But cleanup happens after the new backup is created
      expect(fs.unlinkSync).toHaveBeenCalled();
    });

    it('should not delete backups if under maxBackups limit', async () => {
      (fs.readdirSync as jest.Mock).mockReturnValue([
        'backup1.sqlite',
      ]);

      await backupService.createBackup();

      // Should not delete anything (2 total, maxBackups is 3)
      expect(fs.unlinkSync).not.toHaveBeenCalled();
    });
  });

  describe('singleton functions', () => {
    it('getBackupService should return the same instance', () => {
      const instance1 = getBackupService();
      const instance2 = getBackupService();

      expect(instance1).toBe(instance2);
    });

    it('initializeBackupService should initialize the singleton', async () => {
      await initializeBackupService();

      const instance = getBackupService();
      // Should be initialized (no error when calling methods)
      await expect(instance.listBackups()).resolves.toBeDefined();
    });

    it('initializeBackupService with config should create new instance', async () => {
      const customConfig = { maxBackups: 10 };
      
      await initializeBackupService(customConfig);

      // Should have created a new instance with custom config
      expect(fs.mkdirSync).toHaveBeenCalled();
    });
  });

  describe('shutdown', () => {
    it('should cleanup resources', async () => {
      await backupService.initialize();
      await backupService.shutdown();

      // After shutdown, should throw error when trying to use
      await expect(backupService.createBackup()).rejects.toThrow('not initialized');
    });
  });
});
