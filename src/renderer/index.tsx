/// <reference path="./renderer.d.ts" />
/**
 * This file will automatically be loaded by webpack and run in the "renderer" context.
 * To learn more about the differences between the "main" and the "renderer" context in
 * Electron, visit:
 *
 * https://www.electronjs.org/docs/tutorial/application-architecture#main-and-renderer-processes
 *
 * By default, Node.js integration in this file is disabled. When enabling Node.js integration
 * in a renderer process, please be aware of potential security implications. You can read
 * more about security risks here:
 *
 * https://www.electronjs.org/docs/tutorial/security
 *
 * To enable Node.js integration in this file, open up `main.js` and enable the `nodeIntegration`
 * flag:
 *
 * ```
 *  // Create the browser window.
 *  mainWindow = new BrowserWindow({
 *    width: 800,
 *    height: 600,
 *    webPreferences: {
 *      nodeIntegration: true
 *    }
 *  });
 * ```
 */

import '../index.css';

// Global error handling for the renderer process
window.onerror = (message, source, lineno, colno, error) => {
  console.error('Unhandled Error in renderer process:', { message, source, lineno, colno, error });
};

window.addEventListener('unhandledrejection', (event) => {
  console.error('Unhandled Rejection in renderer process:', event.reason);
});


const getRootFolderButton = document.getElementById('get-root-folder');
const sdkResponse = document.getElementById('sdk-response');

if (getRootFolderButton) {
  getRootFolderButton.addEventListener('click', async () => {
    console.log('Renderer: Button clicked, attempting to send IPC message.'); // New log
    try {
      if (sdkResponse) {
        sdkResponse.textContent = 'Fetching root folder...';
      }
      const rootFolder = await window.sdk.sendMessage({ method: 'getMyFilesRootFolder', args: [] });
      console.log('Renderer: Received response from main process:', rootFolder); // New log
      if (sdkResponse) {
        sdkResponse.textContent = JSON.stringify(rootFolder, null, 2);
      }
    } catch (error: any) {
      console.error('Renderer: Error sending IPC message or receiving response:', error); // New log
      if (sdkResponse) {
        sdkResponse.textContent = `Error: ${error.message}`;
      }
    }
  });
}

// For demonstration, you can still listen to onMessage if the main process sends unsolicited messages.
window.sdk.onMessage((message) => {
  console.log('Received unsolicited message from main process:', message);
});