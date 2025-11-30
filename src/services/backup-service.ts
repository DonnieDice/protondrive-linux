import * as fs from 'fs';
import * as path from 'path';
import { getDbInstance } from './storage-service';
import logger from '../shared/utils/logger';

/**
 * Get the user data path
 * Wrapped in a function to make it easier to mock in tests
 */
function getUserDataPath(): string {
  // Dynamic import to avoid loading electron at module level
  const { app } = require('electron');
  return app.getPath('userData');
}

/**
 * Configuration for backup service
 */
interface BackupConfig {
  /** Maximum number of backups to keep */
  maxBackups: number;
  /** Directory where backups are stored */
  backupDir: string;
  /** Whether to compress backups (future enhancement) */
  compress?: boolean;
}

/**
 * Backup metadata
 */
interface BackupMetadata {
  /** Backup filename */
  filename: string;
  /** Full path to backup file */
  path: string;
  /** Timestamp when backup was created */
  timestamp: Date;
  /** Size of backup file in bytes */
  size: number;
  /** Database schema version at time of backup */
  schemaVersion: number;
}

/**
 * Default backup configuration
 */
/**
 * Get default backup configuration
 */
function getDefaultConfig(): BackupConfig {
  return {
    maxBackups: 5,
    backupDir: path.join(getUserDataPath(), 'backups'),
    compress: false,
  };
}

/**
 * BackupService - Handles automated database backups
 * 
 * Responsibilities:
 * - Create database backups before migrations
 * - Maintain a rolling window of backups (delete old ones)
 * - Restore database from backup
 * - List available backups
 * 
 * Dependencies:
 * - storage-service (for database access)
 * - fs (for file operations)
 */
export class BackupService {
  private config: BackupConfig;
  private initialized = false;

  constructor(config: Partial<BackupConfig> = {}) {
    this.config = { ...getDefaultConfig(), ...config };
  }

  /**
   * Initialize backup service
   * Creates backup directory if it doesn't exist
   */
  async initialize(): Promise<void> {
    if (this.initialized) return;

    logger.info('Initializing BackupService');

    try {
      // Ensure backup directory exists
      if (!fs.existsSync(this.config.backupDir)) {
        fs.mkdirSync(this.config.backupDir, { recursive: true });
        logger.info(`Created backup directory: ${this.config.backupDir}`);
      }

      this.initialized = true;
      logger.info('BackupService initialized successfully');
    } catch (error) {
      logger.error('Failed to initialize BackupService', { error });
      throw error;
    }
  }

  /**
   * Create a backup of the current database
   * @param reason - Optional reason for the backup (e.g., "pre-migration")
   * @returns Metadata about the created backup
   */
  async createBackup(reason?: string): Promise<BackupMetadata> {
    if (!this.initialized) {
      throw new Error('BackupService not initialized');
    }

    const timestamp = new Date();
    const timestampStr = timestamp.toISOString().replace(/[:.]/g, '-');
    const reasonStr = reason ? `_${reason.replace(/[^a-zA-Z0-9]/g, '_')}` : '';
    const filename = `protondrive_backup_${timestampStr}${reasonStr}.sqlite`;
    const backupPath = path.join(this.config.backupDir, filename);

    logger.info(`Creating database backup: ${filename}`);

    try {
      const db = getDbInstance();
      
      // Get current schema version
      const versionResult = db.prepare('PRAGMA user_version').get() as { user_version: number };
      const schemaVersion = versionResult.user_version;

      // Use SQLite's backup API for safe backup
      // This is better than file copy because it handles active connections
      await this.performBackup(backupPath);

      // Get backup file size
      const stats = fs.statSync(backupPath);

      const metadata: BackupMetadata = {
        filename,
        path: backupPath,
        timestamp,
        size: stats.size,
        schemaVersion,
      };

      logger.info(`Backup created successfully: ${filename} (${stats.size} bytes, schema v${schemaVersion})`);

      // Clean up old backups
      await this.cleanupOldBackups();

      return metadata;
    } catch (error) {
      logger.error(`Failed to create backup: ${filename}`, { error });
      throw error;
    }
  }

  /**
   * Perform the actual backup using SQLite's backup command
   * @param backupPath - Path where backup should be saved
   */
  private async performBackup(backupPath: string): Promise<void> {
    const db = getDbInstance();
    
    // Use SQLite's VACUUM INTO command for safe backup
    // This creates a clean copy of the database
    db.exec(`VACUUM INTO '${backupPath}'`);
  }

  /**
   * Restore database from a backup
   * WARNING: This will replace the current database!
   * @param backupPath - Path to the backup file to restore
   */
  async restoreBackup(backupPath: string): Promise<void> {
    if (!this.initialized) {
      throw new Error('BackupService not initialized');
    }

    if (!fs.existsSync(backupPath)) {
      throw new Error(`Backup file not found: ${backupPath}`);
    }

    logger.warn(`Restoring database from backup: ${backupPath}`);

    try {
      const db = getDbInstance();
      
      // Close the current database connection
      db.close();

      // Get the current database path
      const dbPath = path.join(getUserDataPath(), 'protondrive.sqlite');

      // Create a backup of the current database before restoring
      const emergencyBackupPath = `${dbPath}.emergency_${Date.now()}.sqlite`;
      if (fs.existsSync(dbPath)) {
        fs.copyFileSync(dbPath, emergencyBackupPath);
        logger.info(`Created emergency backup: ${emergencyBackupPath}`);
      }

      // Copy the backup file to the database location
      fs.copyFileSync(backupPath, dbPath);

      logger.info('Database restored successfully from backup');
      logger.warn('Application should be restarted to use the restored database');
    } catch (error) {
      logger.error('Failed to restore backup', { error });
      throw error;
    }
  }

  /**
   * List all available backups
   * @returns Array of backup metadata, sorted by timestamp (newest first)
   */
  async listBackups(): Promise<BackupMetadata[]> {
    if (!this.initialized) {
      throw new Error('BackupService not initialized');
    }

    try {
      const files = fs.readdirSync(this.config.backupDir);
      const backups: BackupMetadata[] = [];

      for (const filename of files) {
        if (!filename.endsWith('.sqlite')) continue;

        const filePath = path.join(this.config.backupDir, filename);
        const stats = fs.statSync(filePath);

        // Try to get schema version from the backup file
        let schemaVersion = 0;
        try {
          const Database = require('better-sqlite3');
          const backupDb = new Database(filePath, { readonly: true });
          const versionResult = backupDb.prepare('PRAGMA user_version').get() as { user_version: number };
          schemaVersion = versionResult.user_version;
          backupDb.close();
        } catch (error) {
          logger.warn(`Could not read schema version from backup: ${filename}`, { error });
        }

        backups.push({
          filename,
          path: filePath,
          timestamp: stats.mtime,
          size: stats.size,
          schemaVersion,
        });
      }

      // Sort by timestamp, newest first
      backups.sort((a, b) => b.timestamp.getTime() - a.timestamp.getTime());

      return backups;
    } catch (error) {
      logger.error('Failed to list backups', { error });
      throw error;
    }
  }

  /**
   * Delete old backups, keeping only the most recent ones
   * according to maxBackups configuration
   */
  private async cleanupOldBackups(): Promise<void> {
    try {
      const backups = await this.listBackups();

      if (backups.length <= this.config.maxBackups) {
        return; // No cleanup needed
      }

      const backupsToDelete = backups.slice(this.config.maxBackups);

      for (const backup of backupsToDelete) {
        logger.info(`Deleting old backup: ${backup.filename}`);
        fs.unlinkSync(backup.path);
      }

      logger.info(`Cleaned up ${backupsToDelete.length} old backup(s)`);
    } catch (error) {
      logger.error('Failed to cleanup old backups', { error });
      // Don't throw - cleanup failure shouldn't break backup creation
    }
  }

  /**
   * Delete a specific backup
   * @param backupPath - Path to the backup file to delete
   */
  async deleteBackup(backupPath: string): Promise<void> {
    if (!this.initialized) {
      throw new Error('BackupService not initialized');
    }

    if (!fs.existsSync(backupPath)) {
      throw new Error(`Backup file not found: ${backupPath}`);
    }

    // Ensure the backup is in our backup directory (security check)
    const normalizedBackupPath = path.normalize(backupPath);
    const normalizedBackupDir = path.normalize(this.config.backupDir);
    
    if (!normalizedBackupPath.startsWith(normalizedBackupDir)) {
      throw new Error('Cannot delete backup outside of backup directory');
    }

    try {
      fs.unlinkSync(backupPath);
      logger.info(`Deleted backup: ${path.basename(backupPath)}`);
    } catch (error) {
      logger.error(`Failed to delete backup: ${backupPath}`, { error });
      throw error;
    }
  }

  /**
   * Get the total size of all backups
   * @returns Total size in bytes
   */
  async getTotalBackupSize(): Promise<number> {
    const backups = await this.listBackups();
    return backups.reduce((total, backup) => total + backup.size, 0);
  }

  /**
   * Cleanup resources
   */
  async shutdown(): Promise<void> {
    logger.info('Shutting down BackupService');
    this.initialized = false;
  }
}

// Export a singleton instance
let backupServiceInstance: BackupService | null = null;

/**
 * Get the singleton BackupService instance
 */
export function getBackupService(): BackupService {
  if (!backupServiceInstance) {
    backupServiceInstance = new BackupService();
  }
  return backupServiceInstance;
}

/**
 * Initialize the backup service (convenience function)
 */
export async function initializeBackupService(config?: Partial<BackupConfig>): Promise<void> {
  const service = config ? new BackupService(config) : getBackupService();
  await service.initialize();
  if (config) {
    backupServiceInstance = service;
  }
}
