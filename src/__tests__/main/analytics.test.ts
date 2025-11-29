// Clean, standard, conflict-free mocking of @aptabase/electron
jest.mock('@aptabase/electron', () => ({
  init: jest.fn(),
  trackEvent: jest.fn(),
}));

// Type-safe access to the mocks
import { init, trackEvent } from '@aptabase/electron';
import { initializeAnalytics, recordAnalyticsEvent } from '@main/analytics';
import { appConfig } from '@shared/config/app-config';
import logger from '@shared/utils/logger';

// Optional: add types if your linter complains (most don't)
type MockedAptabase = {
  init: jest.Mock;
  trackEvent: jest.Mock;
};
const mocked = { init, trackEvent } satisfies MockedAptabase;

// ──────────────────────────────────────────────────────────────────────────────
// Your existing tests continue unchanged below
// ──────────────────────────────────────────────────────────────────────────────


// Mock the appConfig module
jest.mock('@shared/config/app-config', () => ({
  appConfig: {
    APTABASE_APP_KEY: undefined as string | undefined,
    NODE_ENV: 'development', // Add other properties if necessary for logger.ts
    LOG_LEVEL: 'info',
  },
}));

// Mock the logger module
jest.mock('@shared/utils/logger', () => ({
  __esModule: true, // This is important for ESM modules
  default: {
    info: jest.fn(),
    warn: jest.fn(),
    debug: jest.fn(),
    error: jest.fn(),
  },
}));

describe('analytics', () => {
  const loggerWarnSpy = jest.spyOn(logger, 'warn');
  const loggerInfoSpy = jest.spyOn(logger, 'info');
  const loggerDebugSpy = jest.spyOn(logger, 'debug');

  afterEach(() => {
    jest.clearAllMocks();
  });

  beforeEach(() => {
    // Reset appConfig.APTABASE_APP_KEY for each test
    (appConfig as any).APTABASE_APP_KEY = undefined;
  });

  describe('initializeAnalytics', () => {
    it('should initialize Aptabase when APTABASE_APP_KEY is present', () => {
      (appConfig as any).APTABASE_APP_KEY = 'test-key-123';
      initializeAnalytics();
      expect(init).toHaveBeenCalledTimes(1);
      expect(init).toHaveBeenCalledWith('test-key-123');
      expect(loggerInfoSpy).toHaveBeenCalledWith('Aptabase analytics initialized.');
      expect(loggerWarnSpy).not.toHaveBeenCalled();
    });

    it('should not initialize Aptabase and log a warning when APTABASE_APP_KEY is missing', () => {
      initializeAnalytics();
      expect(init).not.toHaveBeenCalled();
      expect(loggerWarnSpy).toHaveBeenCalledTimes(1);
      expect(loggerWarnSpy).toHaveBeenCalledWith('APTABASE_APP_KEY is not set. Analytics will be disabled.');
      expect(loggerInfoSpy).not.toHaveBeenCalled();
    });
  });

  describe('recordAnalyticsEvent', () => {
    it('should track an event when APTABASE_APP_KEY is present', () => {
      (appConfig as any).APTABASE_APP_KEY = 'test-key-123';
      initializeAnalytics();
      jest.clearAllMocks(); 

      recordAnalyticsEvent('App Started', { platform: 'linux' });
      expect(trackEvent).toHaveBeenCalledTimes(1);
      expect(trackEvent).toHaveBeenCalledWith('App Started', { platform: 'linux' });
      expect(loggerDebugSpy).toHaveBeenCalledWith('Aptabase event recorded: App Started', { platform: 'linux' });
    });

    it('should not track an event when APTABASE_APP_KEY is missing', () => {
      recordAnalyticsEvent('App Closed');
      expect(trackEvent).not.toHaveBeenCalled();
      expect(loggerDebugSpy).toHaveBeenCalledWith('Aptabase event not recorded (analytics disabled): App Closed');
    });

    it('should handle undefined props gracefully', () => {
        (appConfig as any).APTABASE_APP_KEY = 'test-key-123';
        initializeAnalytics();
        jest.clearAllMocks();

        recordAnalyticsEvent('User Action');
        expect(trackEvent).toHaveBeenCalledTimes(1);
        expect(trackEvent).toHaveBeenCalledWith('User Action', undefined);
        expect(loggerDebugSpy).toHaveBeenCalledWith('Aptabase event recorded: User Action', undefined);
    });
  });
});