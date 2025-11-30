// Mock Winston FIRST to prevent real logger creation
jest.mock('winston', () => ({
  createLogger: jest.fn(() => ({
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
    debug: jest.fn(),
  })),
  format: {
    combine: jest.fn(),
    timestamp: jest.fn(),
    errors: jest.fn(),
    splat: jest.fn(),
    json: jest.fn(),
    colorize: jest.fn(),
    printf: jest.fn(),
  },
  transports: {
    Console: jest.fn(),
    File: jest.fn(),
  },
}));

// Mock the logger module
const mockLogger = {
  info: jest.fn(),
  warn: jest.fn(),
  debug: jest.fn(),
  error: jest.fn(),
};

jest.mock('@shared/utils/logger', () => ({
  __esModule: true,
  default: mockLogger,
}));

// Also mock the relative path that analytics.ts uses
jest.mock('../../shared/utils/logger', () => ({
  __esModule: true,
  default: mockLogger,
}));

// Mock the appConfig module
jest.mock('@shared/config/app-config', () => ({
  appConfig: {
    APTABASE_APP_KEY: undefined as string | undefined,
    NODE_ENV: 'development',
    LOG_LEVEL: 'info',
  },
}));

// Mock @aptabase/electron
jest.mock('@aptabase/electron', () => ({
  init: jest.fn(),
  trackEvent: jest.fn(),
}));

// Now import after mocks are set up
import { init, trackEvent } from '@aptabase/electron';
import { initializeAnalytics, recordAnalyticsEvent } from '@main/analytics';
import { appConfig } from '@shared/config/app-config';
import logger from '@shared/utils/logger';

describe('analytics', () => {
  // Get the mocked logger instance
  const mockedLogger = logger as jest.Mocked<typeof logger>;

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
      expect(mockedLogger.info).toHaveBeenCalledWith('Aptabase analytics initialized.');
      expect(mockedLogger.warn).not.toHaveBeenCalled();
    });

    it('should not initialize Aptabase and log a warning when APTABASE_APP_KEY is missing', () => {
      initializeAnalytics();
      expect(init).not.toHaveBeenCalled();
      expect(mockedLogger.warn).toHaveBeenCalledTimes(1);
      expect(mockedLogger.warn).toHaveBeenCalledWith('APTABASE_APP_KEY is not set. Analytics will be disabled.');
      expect(mockedLogger.info).not.toHaveBeenCalled();
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
      expect(mockedLogger.debug).toHaveBeenCalledWith('Aptabase event recorded: App Started', { platform: 'linux' });
    });

    it('should not track an event when APTABASE_APP_KEY is missing', () => {
      recordAnalyticsEvent('App Closed');
      expect(trackEvent).not.toHaveBeenCalled();
      expect(mockedLogger.debug).toHaveBeenCalledWith('Aptabase event not recorded (analytics disabled): App Closed');
    });

    it('should handle undefined props gracefully', () => {
        (appConfig as any).APTABASE_APP_KEY = 'test-key-123';
        initializeAnalytics();
        jest.clearAllMocks();

        recordAnalyticsEvent('User Action');
        expect(trackEvent).toHaveBeenCalledTimes(1);
        expect(trackEvent).toHaveBeenCalledWith('User Action', undefined);
        expect(mockedLogger.debug).toHaveBeenCalledWith('Aptabase event recorded: User Action', undefined);
    });
  });
});