import { appConfig } from '@shared/config/app-config';

// Mock the env-validator module to control its output
jest.mock('@shared/config/env-validator', () => ({
  getValidatedEnv: jest.fn(() => Object.freeze({ // Make sure the mock returns a frozen object
    NODE_ENV: 'test',
    LOG_LEVEL: 'debug',
    SENTRY_DSN: 'https://mock.sentry.io',
    APTABASE_APP_KEY: 'mock-aptabase-key',
  })),
}));

describe('app-config', () => {
  it('should load validated environment variables', () => {
    // appConfig is imported, which immediately calls getValidatedEnv
    expect(appConfig.NODE_ENV).toBe('test');
    expect(appConfig.LOG_LEVEL).toBe('debug');
    expect(appConfig.SENTRY_DSN).toBe('https://mock.sentry.io');
    expect(appConfig.APTABASE_APP_KEY).toBe('mock-aptabase-key');
  });

  it('should export a frozen appConfig object', () => {
    expect(Object.isFrozen(appConfig)).toBe(true);

    // Modifications should fail because the object is frozen.
    // We are only verifying the frozen state, not attempting to modify it.
  });
});
