import winston from 'winston';
import { appConfig } from '@shared/config/app-config';
import loggerModule from '@shared/utils/logger'; // Import as module to access default export
import * as path from 'path';

// --- Mocking Winston and its components ---
const mockConsoleTransportInstance = { type: 'console', level: 'debug' };
const mockFileTransportInstance1 = { type: 'file', level: 'error', filename: 'error.log' };
const mockFileTransportInstance2 = { type: 'file', level: 'info', filename: 'combined.log' };

const mockLoggerInstance = {
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  debug: jest.fn(),
  add: jest.fn(),
  remove: jest.fn(),
  transports: [] as any[],
  level: 'info', // Initial default, will be set by createLogger mock
  format: jest.fn(),
};

// A generic mock for winston.format.combine that just passes args through
const mockCombine = jest.fn((...args) => (...info: any[]) => args.reduce((acc, fn) => fn(acc), info[0]));

jest.mock('winston', () => {
  const originalWinston = jest.requireActual('winston'); // Get actual winston functions
  return {
    ...originalWinston, // Keep original utilities not explicitly mocked
    format: {
      ...originalWinston.format,
      combine: mockCombine,
      timestamp: jest.fn(() => jest.fn(info => ({ ...info, timestamp: '2024-01-01T00:00:00Z' }))),
      printf: jest.fn(() => jest.fn(info => `${info.timestamp} ${info.level}: ${info.message}`)),
      colorize: jest.fn(() => jest.fn(info => info)),
      json: jest.fn(() => jest.fn(info => JSON.stringify(info))),
    },
    transports: {
      Console: jest.fn(() => mockConsoleTransportInstance),
      File: jest.fn((options) => {
        // Return distinct instances based on options for testing
        if (options.level === 'error') return mockFileTransportInstance1;
        return mockFileTransportInstance2;
      }),
    },
    createLogger: jest.fn((options) => {
      // Configure our mockLoggerInstance based on the options passed to createLogger
      mockLoggerInstance.level = options.level || 'info'; // Implement Winston's default fallback for invalid level
      mockLoggerInstance.transports = options.transports || [];
      mockLoggerInstance.format = options.format;
      // Clear specific log methods only (createLogger is called once per module load)
      mockLoggerInstance.info.mockClear();
      mockLoggerInstance.warn.mockClear();
      mockLoggerInstance.error.mockClear();
      mockLoggerInstance.debug.mockClear();
      mockLoggerInstance.add.mockClear();
      mockLoggerInstance.remove.mockClear();
      mockLoggerInstance.transports = []; // Ensure transports are clean for each createLogger call mock
      if (options.transports) {
          mockLoggerInstance.transports.push(...options.transports);
      }
      return mockLoggerInstance;
    }),
  };
});

// --- Mocking appConfig ---
// Use a mutable object for mockAppConfig state
const mockAppConfigState = {
  NODE_ENV: 'development',
  LOG_LEVEL: 'info',
};

jest.mock('@shared/config/app-config', () => ({
  appConfig: {
    get NODE_ENV() { return mockAppConfigState.NODE_ENV; },
    get LOG_LEVEL() { return mockAppConfigState.LOG_LEVEL; },
  },
}));

// --- Mocking electron ---
jest.mock('electron', () => ({
  app: {
    getPath: jest.fn(() => '/mock/user/data'),
  },
}));

describe('logger', () => {
  let winstonMocks: jest.Mocked<typeof winston>;
  // Don't need appConfigMock directly as we manipulate mockAppConfigState
  let electronAppMock: jest.Mocked<typeof import('electron')>;
  let logger: typeof import('@shared/utils/logger').default; // Declare logger here

  beforeEach(() => {
    jest.resetModules(); // Clear module cache for clean slate
    
    // Reset mockAppConfigState for each test
    mockAppConfigState.NODE_ENV = 'development';
    mockAppConfigState.LOG_LEVEL = 'info';

    // Re-import all mocked modules to get their fresh mock instances
    winstonMocks = require('winston');
    electronAppMock = require('electron');

    // Re-import the module under test. This will trigger its module-level side effects (calling createLogger)
    logger = require('@shared/utils/logger').default; 
    
    // Clear call counts on winston.createLogger AFTER logger.ts has initialized itself
    // so we can inspect its state cleanly in individual tests.
    winstonMocks.createLogger.mockClear();
  });

  it('should initialize logger with correct level based on appConfig', () => {
    // When logger.ts was imported, winston.createLogger was called.
    // We expect the mockLoggerInstance's level to be set by the options passed.
    expect(mockLoggerInstance.level).toBe(mockAppConfigState.LOG_LEVEL);
    expect(mockLoggerInstance.transports).toBeInstanceOf(Array);
  });

  describe('in development environment', () => {
    beforeEach(() => {
      jest.resetModules();
      winstonMocks = require('winston');
      mockAppConfigState.NODE_ENV = 'development';
      mockAppConfigState.LOG_LEVEL = 'debug';
      logger = require('@shared/utils/logger').default; // Re-import with dev config
      winstonMocks.createLogger.mockClear(); // Clear createLogger calls for this specific scenario
    });

    it('should configure console transport and not file transports', () => {
      expect(winstonMocks.transports.Console).toHaveBeenCalledTimes(1);
      expect(winstonMocks.transports.File).not.toHaveBeenCalled();
      
      // Check that the mockLoggerInstance now contains the console transport
      const hasConsoleTransport = mockLoggerInstance.transports.some(
        (t: any) => t === mockConsoleTransportInstance
      );
      expect(hasConsoleTransport).toBe(true);

      // And should not add console transport again directly via loggerInstance.add()
      expect(mockLoggerInstance.add).not.toHaveBeenCalled();
    });

    it('should use colorized and printf formats for console transport', () => {
      expect(winstonMocks.format.colorize).toHaveBeenCalledTimes(1);
      expect(winstonMocks.format.printf).toHaveBeenCalledTimes(1);
      expect(winstonMocks.format.combine).toHaveBeenCalledWith(
        expect.any(Function), // colorize() result
        expect.any(Function), // timestamp() result
        expect.any(Function)  // printf() result
      );
    });
  });

  describe('in production environment', () => {
    beforeEach(() => {
      jest.resetModules();
      winstonMocks = require('winston');
      mockAppConfigState.NODE_ENV = 'production';
      mockAppConfigState.LOG_LEVEL = 'info';
      logger = require('@shared/utils/logger').default; // Re-import with prod config
      winstonMocks.createLogger.mockClear(); // Clear createLogger calls for this specific scenario
    });

    it('should configure file transports and not console transport', () => {
      expect(winstonMocks.transports.File).toHaveBeenCalledTimes(2);
      expect(winstonMocks.transports.Console).not.toHaveBeenCalled();

      // Check that the mockLoggerInstance now contains the file transports
      expect(mockLoggerInstance.transports).toContain(mockFileTransportInstance1);
      expect(mockLoggerInstance.transports).toContain(mockFileTransportInstance2);
      expect(mockLoggerInstance.transports.some(t => t === mockConsoleTransportInstance)).toBe(false);
    });

    it('should use json format for file transports', () => {
      expect(winstonMocks.format.json).toHaveBeenCalledTimes(1); // Default format is json
      // The loggerInstance's format should be the result of winston.format.json()
      expect(mockLoggerInstance.format).toEqual(expect.any(Function)); 
    });
  });

  it('should log messages using the winston instance methods', () => {
    logger.info('Test info message', { key: 'value' });
    expect(mockLoggerInstance.info).toHaveBeenCalledWith('Test info message', { key: 'value' });

    const testError = new Error('Something went wrong');
    logger.error('Critical error', { error: testError, code: 500 });
    expect(mockLoggerInstance.error).toHaveBeenCalledWith(
      'Critical error',
      expect.objectContaining({ error: testError, code: 500 })
    );
  });

  it('should use winston default level if appConfig.LOG_LEVEL is invalid', () => {
    jest.resetModules();
    winstonMocks = require('winston');
    // Set the LOG_LEVEL to an invalid value via the state object
    mockAppConfigState.LOG_LEVEL = 'invalid'; 
    logger = require('@shared/utils/logger').default; // Re-import with invalid config

    // Now, we assert what winston.createLogger was called with, not mockLoggerInstance.level directly.
    // The logger module itself should have resolved 'invalid' to 'info'.
    const createLoggerCallArgs = winstonMocks.createLogger.mock.calls[0][0];
    expect(createLoggerCallArgs.level).toBe('info'); 
  });
});