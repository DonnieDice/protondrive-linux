import { app, BrowserWindow, shell, ipcMain } from 'electron';
import { is } from '@electron-toolkit/utils';
import path from 'path';
import logger from '../shared/utils/logger';

// Default window size
const DEFAULT_WIDTH = 1200;
const DEFAULT_HEIGHT = 800;

let mainWindow: BrowserWindow | null;

/**
 * Creates the main application window.
 */
function createMainWindow(): void {
  // Create the browser window.
  mainWindow = new BrowserWindow({
    width: DEFAULT_WIDTH,
    height: DEFAULT_HEIGHT,
    show: false, // Don't show until ready
    autoHideMenuBar: true,
    titleBarStyle: 'hidden', // Customize title bar
    webPreferences: {
      preload: path.join(__dirname, '../preload/index.js'),
      sandbox: true,
      contextIsolation: true, // Crucial for security
    },
  });

  mainWindow.on('ready-to-show', () => {
    if (mainWindow) {
      mainWindow.show();
      logger.info('Main window ready to show.');
    }
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
    logger.info('Main window closed.');
  });

  // Open urls in the user's default browser
  mainWindow.webContents.setWindowOpenHandler((details) => {
    shell.openExternal(details.url);
    return { action: 'deny' };
  });

  // Load the renderer process entry point
  if (is.dev && process.env['ELECTRON_RENDERER_URL']) {
    mainWindow.loadURL(process.env['ELECTRON_RENDERER_URL']);
    mainWindow.webContents.openDevTools(); // Open DevTools in development
  } else {
    mainWindow.loadFile(path.join(__dirname, '../renderer/index.html'));
  }

  logger.info('Main window created and loading content.');
}

/**
 * Initializes and manages application windows.
 */
export const initializeWindowManager = (): void => {
  app.whenReady().then(() => {
    createMainWindow();

    app.on('activate', () => {
      // On macOS it's common to re-create a window in the app when the
      // dock icon is clicked and there are no other windows open.
      if (BrowserWindow.getAllWindows().length === 0) createMainWindow();
    });

    logger.info('Window manager initialized.');
  });

  // Quit when all windows are closed, except on macOS. There, it's common
  // for applications and their menu bar to stay active until the user quits
  // explicitly with Cmd + Q.
  app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') {
      app.quit();
      logger.info('All windows closed, application quitting.');
    }
  });

  // Example IPC handler (can be expanded for specific renderer <-> main communication)
  ipcMain.handle('get-app-version', () => {
    logger.debug('IPC: get-app-version requested.');
    return app.getVersion();
  });
};

/**
 * Returns the main application window instance.
 * @returns The BrowserWindow instance, or null if not created yet.
 */
export const getMainWindow = (): BrowserWindow | null => {
  return mainWindow;
};
