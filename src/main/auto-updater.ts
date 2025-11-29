import { autoUpdater } from 'electron-updater';
import logger from '../shared/utils/logger';
import { app, BrowserWindow } from 'electron';

/**
 * Initializes and configures the auto-updater for the application.
 * This should be called in the main process after the app is ready.
 *
 * @param mainWindow - The main browser window, used to notify the user of update status.
 */
export const initializeAutoUpdater = (mainWindow: BrowserWindow): void => {
  // Disable auto-downloading updates
  autoUpdater.autoDownload = false;

  // Configure logging for auto-updater
  autoUpdater.logger = logger;

  // Event: An update is available
  autoUpdater.on('update-available', (info) => {
    logger.info(`Update available: ${info.version}`);
    mainWindow.webContents.send('update-message', {
      type: 'update-available',
      info: info,
    });
  });

  // Event: No update is available
  autoUpdater.on('update-not-available', (info) => {
    logger.info('No update available.');
    mainWindow.webContents.send('update-message', {
      type: 'update-not-available',
      info: info,
    });
  });

  // Event: Download progress
  autoUpdater.on('download-progress', (progressObj) => {
    const log_message = `Download speed: ${progressObj.bytesPerSecond} - Downloaded ${progressObj.percent}% (${progressObj.transferred}/${progressObj.total})`;
    logger.info(log_message);
    mainWindow.webContents.send('update-message', {
      type: 'download-progress',
      info: progressObj,
    });
  });

  // Event: Update has been downloaded
  autoUpdater.on('update-downloaded', (info) => {
    logger.info(`Update downloaded: ${info.version}. App will quit and install.`);
    mainWindow.webContents.send('update-message', {
      type: 'update-downloaded',
      info: info,
    });
    // Optional: Quit and install immediately
    // autoUpdater.quitAndInstall();
  });

  // Event: Error during update process
  autoUpdater.on('error', (err) => {
    logger.error(`Error in auto-updater: ${err.message}`, err);
    mainWindow.webContents.send('update-message', {
      type: 'update-error',
      info: err.message,
    });
  });

  // Check for updates immediately after initialization (can be triggered by user later)
  checkUpdates();
};

/**
 * Manually checks for updates.
 */
export const checkUpdates = (): void => {
  logger.info('Checking for updates...');
  if (app.isPackaged) { // Only check for updates if the app is packaged
    autoUpdater.checkForUpdates();
  } else {
    logger.info('Skipping update check: App is not packaged (running in development mode).');
  }
};

/**
 * Manually starts downloading the update.
 */
export const downloadUpdate = (): void => {
  logger.info('Starting update download...');
  autoUpdater.downloadUpdate();
};

/**
 * Quits the application and installs the downloaded update.
 */
export const installUpdate = (): void => {
  logger.info('Quitting and installing update...');
  autoUpdater.quitAndInstall();
};
