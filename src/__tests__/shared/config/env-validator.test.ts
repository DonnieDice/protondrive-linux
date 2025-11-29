import { getValidatedEnv } from '@shared/config/env-validator';

describe('env-validator', () => {
  const originalEnv = process.env;

  beforeEach(() => {
    jest.resetModules(); // Clears module cache before each test
    process.env = { ...originalEnv }; // Make a copy of original process.env
  });

  afterAll(() => {
    process.env = originalEnv; // Restore original process.env after all tests
  });

  it('should correctly parse valid environment variables with defaults', () => {
    process.env.NODE_ENV = 'development';
    process.env.LOG_LEVEL = 'debug';

    const env = getValidatedEnv();

    expect(env.NODE_ENV).toBe('development');
    expect(env.LOG_LEVEL).toBe('debug');
    expect(env.SENTRY_DSN).toBeUndefined();
    expect(env.APTABASE_APP_KEY).toBeUndefined();
  });

  it('should apply default values when optional variables are missing', () => {
    process.env.NODE_ENV = 'production';
    // LOG_LEVEL is not set, should default to 'info'

    const env = getValidatedEnv();

    expect(env.NODE_ENV).toBe('production');
    expect(env.LOG_LEVEL).toBe('info'); // Default value
  });

  it('should correctly parse all specified environment variables', () => {
    process.env.NODE_ENV = 'test';
    process.env.LOG_LEVEL = 'error';
    process.env.SENTRY_DSN = 'https://example.com/sentry';
    process.env.APTABASE_APP_KEY = 'aptabase-123';

    const env = getValidatedEnv();

    expect(env.NODE_ENV).toBe('test');
    expect(env.LOG_LEVEL).toBe('error');
    expect(env.SENTRY_DSN).toBe('https://example.com/sentry');
    expect(env.APTABASE_APP_KEY).toBe('aptabase-123');
  });

  it('should throw an error for invalid NODE_ENV', () => {
    process.env.NODE_ENV = 'invalid';
    process.env.LOG_LEVEL = 'info';

    expect(() => getValidatedEnv()).toThrow('Invalid environment variables.');
  });

  it('should throw an error for invalid LOG_LEVEL', () => {
    process.env.NODE_ENV = 'development';
    process.env.LOG_LEVEL = 'invalid';

    expect(() => getValidatedEnv()).toThrow('Invalid environment variables.');
  });

  it('should throw an error for invalid SENTRY_DSN format if present', () => {
    process.env.NODE_ENV = 'development';
    process.env.LOG_LEVEL = 'info';
    process.env.SENTRY_DSN = 'not-a-url';

    expect(() => getValidatedEnv()).toThrow('Invalid environment variables.');
  });

  it('should return a frozen object', () => {
    process.env.NODE_ENV = 'development';
    process.env.LOG_LEVEL = 'info';

    const env = getValidatedEnv();
    expect(Object.isFrozen(env)).toBe(true);
  });
});
