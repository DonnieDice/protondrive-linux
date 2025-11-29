import { getDbInstance } from './storage-service';
import logger from '../shared/utils/logger';
import * as path from 'path';
import * as fs from 'fs';
import { app } from 'electron';

const BACKUPS_DIR = path.join(app.getPath('userData'), 'backups');

/**
 * Ensures the backups directory exists.
 */
function ensureBackupDirectory(): void {
  if (!fs.existsSync(BACKUPS_DIR)) {
    fs.mkdirSync(BACKUPS_DIR, { recursive: true });
    logger.info(`Created backup directory: ${BACKUPS_DIR}`);
  }
}

/**
 * Creates a backup of the current SQLite database.
 * The backup file will be named with a timestamp.
 *
 * @returns The path to the created backup file, or null if backup failed.
 */
export const createBackup = async (): Promise<string | null> => {
  ensureBackupDirectory();
  const db = getDbInstance();
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backupFilePath = path.join(BACKUPS_DIR, `protondrive_backup_${timestamp}.sqlite`);

  try {
    // Use the backup API from better-sqlite3
    await db.backup(backupFilePath);
    logger.info(`Database backup created at: ${backupFilePath}`);
    return backupFilePath;
  } catch (error) {
    logger.error(`Failed to create database backup to ${backupFilePath}:`, error);
    return null;
  }
};

/**
 * Restores the database from a specified backup file.
 * WARNING: This will overwrite the current database.
 *
 * @param backupFilePath - The full path to the backup file to restore from.
 * @returns True if restoration was successful, false otherwise.
 */
export const restoreBackup = async (backupFilePath: string): Promise<boolean> => {
  if (!fs.existsSync(backupFilePath)) {
    logger.error(`Backup file not found: ${backupFilePath}`);
    return false;
  }

  const db = getDbInstance();
  const currentDbPath = db.name; // Get the path of the currently open database

  try {
    // Close the current database connection before restoring
    db.close();

    // Copy the backup file over the current database file
    fs.copyFileSync(backupFilePath, currentDbPath);

    // Re-initialize the database connection
    getDbInstance(); // This will re-open the database from the restored file
    logger.info(`Database restored from: ${backupFilePath}`);
    return true;
  } catch (error) {
    logger.error(`Failed to restore database from ${backupFilePath}:`, error);
    // Attempt to re-open the original database if restoration failed
    try {
      getDbInstance();
    } catch (reopenError) {
      logger.error('Failed to re-open database after failed restore attempt!', reopenError);
      // In a critical failure, the app might need to quit
      app.quit();
    }
    return false;
  }
};

/**
 * Cleans up old backup files, keeping only the most recent N backups.
 * @param maxBackups - The maximum number of backups to keep. Defaults to 5.
 */
export const cleanupOldBackups = (maxBackups: number = 5): void => {
  ensureBackupDirectory();
  try {
    const backupFiles = fs.readdirSync(BACKUPS_DIR)
      .filter(file => file.startsWith('protondrive_backup_') && file.endsWith('.sqlite'))
      .map(file => ({
        name: file,
        path: path.join(BACKUPS_DIR, file),
        // Extract timestamp from filename for sorting
        timestamp: new Date(file.substring(19, file.length - 7).replace(/-/g, ':').replace('T', ' ').substring(0, 19)).getTime()
      }))
      .sort((a, b) => b.timestamp - a.timestamp); // Sort by newest first

    if (backupFiles.length > maxBackups) {
      for (let i = maxBackups; i < backupFiles.length; i++) {
        fs.unlinkSync(backupFiles[i].path);
        logger.info(`Deleted old backup file: ${backupFiles[i].name}`);
      }
    }
  } catch (error) {
    logger.error('Failed to clean up old backup files:', error);
  }
};
