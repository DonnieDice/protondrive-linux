import { getValidatedEnv, AppEnv } from './env-validator';

/**
 * A frozen, type-safe object containing the application's configuration.
 *
 * This configuration is derived from the environment variables and is validated
 * at application startup. Freezing the object prevents accidental modifications
 * at runtime.
 *
 * @example
 * import { appConfig } from './app-config';
 *
 * if (appConfig.NODE_ENV === 'development') {
 *   console.log('Running in development mode');
 * }
 */
export const appConfig: AppEnv = getValidatedEnv();
