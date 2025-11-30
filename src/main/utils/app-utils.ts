import { app } from 'electron';

export const getUserDataPath = (): string => {
  return app.getPath('userData');
};

export const quitApp = (): void => {
  app.quit();
};
