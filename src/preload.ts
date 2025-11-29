// See the Electron documentation for details on how to use preload scripts:
// https://www.electronjs.org/docs/latest/tutorial/process-model#preload-scripts
import { contextBridge, ipcRenderer } from 'electron';

console.log('Preload script loaded!'); // New log at the very top

contextBridge.exposeInMainWorld('sdk', {
  // Use invoke for sending messages that expect a response
  sendMessage: (message: { method: string; args: any[] }) => {
    console.log('Preload: Sending IPC message to main process:', message);
    return ipcRenderer.invoke('sdk-message', message);
  },
  // onMessage remains for event-like communication from main to renderer
  onMessage: (callback: (message: string) => void) => {
    ipcRenderer.on('sdk-reply', (event, message) => {
      console.log('Preload: Received unsolicited message from main process:', message);
      callback(message);
    });
  },
});