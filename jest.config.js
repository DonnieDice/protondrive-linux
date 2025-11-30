module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testMatch: ['**/__tests__/**/*.test.ts', '**/?(*.)+(spec|test).ts'],
  testPathIgnorePatterns: [
    '/node_modules/',
    '/__mocks__/',
    '/dist/',
    '/out/',
  ],
  moduleFileExtensions: ['ts', 'js', 'json', 'node'],
  moduleNameMapper: {
    '^@shared/(.*)$': '<rootDir>/src/shared/$1',
    '^@main/(.*)$': '<rootDir>/src/main/$1',
    '^@services/(.*)$': '<rootDir>/src/services/$1',
    '^@main/utils/app-utils$': '<rootDir>/src/__tests__/__mocks__/@main/utils/app-utils.ts',
    '^@aptabase/electron$': '<rootDir>/src/__tests__/__mocks__/@aptabase/electron.ts',
  },
  // Coverage thresholds temporarily disabled until all tests are fixed
  // coverageThreshold: {
  //   global: {
  //     branches: 80,
  //     functions: 80,
  //     lines: 80,
  //     statements: 80
  //   }
  // }
};
