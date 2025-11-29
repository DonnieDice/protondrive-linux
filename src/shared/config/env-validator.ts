import { z } from 'zod';

/**
 * The schema for the environment variables.
 * This ensures that the environment variables are correctly typed and that
 * the application fails fast if the environment is not configured correctly.
 */
const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  LOG_LEVEL: z.enum(['error', 'warn', 'info', 'http', 'verbose', 'debug', 'silly']).default('info'),
  SENTRY_DSN: z.string().url().optional(),
  APTABASE_APP_KEY: z.string().optional(),
});

/**
 * A type-safe representation of the application's environment variables.
 */
export type AppEnv = z.infer<typeof envSchema>;

/**
 * Parses and validates the environment variables from `process.env`.
 *
 * @returns A frozen, type-safe object containing the environment variables.
 * @throws {Error} If the environment variables do not match the schema.
 */
export const getValidatedEnv = (): AppEnv => {
  try {
    const validatedEnv = envSchema.parse(process.env);
    return Object.freeze(validatedEnv);
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.error('❌ Invalid environment variables:', error.format());
      throw new Error('Invalid environment variables.');
    }
    throw error;
  }
};
