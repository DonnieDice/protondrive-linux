I have encountered a persistent and fundamental issue with Jest's module mocking that I am unable to resolve within the current project structure and constraints.

**Problem:**

The core issue is that the test suite for `src/__tests__/services/database/migrations.test.ts` consistently fails with the error: `Database is not initialized. Call initializeDatabase() first.` This error originates from the *actual* `src/services/storage-service.ts` module, specifically from its `getDbInstance()` function.

**Root Cause:**

The `migrations.ts` module (the module under test) imports and uses `getDbInstance()` from `@services/storage-service`. For the test to pass, `migrations.ts` needs to receive a *mocked* version of `storage-service.ts` where `getDbInstance()` returns a mocked database instance without requiring `initializeDatabase()` to be called.

Despite numerous attempts, Jest is failing to effectively apply the mock for `@services/storage-service` (and its transitive dependency `better-sqlite3`), causing `migrations.ts` to load the *real* `storage-service.ts` module. When the real `storage-service.ts` loads, its `db` variable is `null` by default, leading to the "Database is not initialized" error when `getDbInstance()` is called.

**Steps Taken (and why they failed):**

1.  **Initial attempts to use `jest.mock` globally and `jest.clearAllMocks()` in `beforeEach`:** This failed due to hoisting issues with `let`/`const` variables inside `jest.mock` factory functions, and `TypeError: Cannot read properties of undefined` for internal `path` functions.
2.  **Introduction of `jest.isolateModules()` with `jest.doMock`:** This was an attempt to create isolated module environments for `migrations.ts` and its dependencies. This approach became extremely complex, leading to further `ReferenceError`s and ultimately failed because of challenges in correctly passing and maintaining references to mock instances across the isolated contexts.
3.  **Refined `jest.isolateModules()` with explicit capture of global mocks:** This also proved ineffective, as the `jest.doMock` factory functions still failed to correctly access the globally defined mock instances.
4.  **Implementing Manual Mock Files (`__mocks__`) for `path`, `fs`, `better-sqlite3`, `@services/storage-service`, and `@shared/utils/logger`:** This was done to ensure consistent mocking of built-in Node.js modules and complex dependencies.
    *   Initially, there were `TypeError: path.basename is not a function` errors, indicating `path` was not being mocked correctly for all transitive dependencies.
    *   This led to a cascading effort to explicitly mock all relevant functions (`basename`, `dirname`, `extname`) in `path.ts`.
    *   This also led to explicitly mocking `winston` due to its internal dependencies on `path`.
    *   The manual mock files were updated to use ES module syntax (e.g., `export const ...`) to avoid `not a module` errors.
5.  **Using `jest.resetModules()` and `require()` for the module under test (`applyMigrations`) in `beforeEach`:** This standard pattern is designed to ensure a fresh module load with all mocks applied. However, it still results in the "Database is not initialized" error, indicating `storage-service.ts` is still loading as the *real* module.
6.  **Switching to `jest.spyOn` on the actual `storageService` module:** This was an attempt to override the functions of the `storage-service` module *after* it has been loaded. This also failed with the same "Database is not initialized" error, suggesting that `getDbInstance` is being called *before* `jest.spyOn` has a chance to apply.
7.  **Final attempt to use `jest.mock('@services/storage-service');` globally (pointing to a manual mock) and dynamically requiring `applyMigrations`:** This also results in the "Database is not initialized" error.

**Conclusion:**

Despite trying every known Jest mocking technique, including global `jest.mock` with manual mock files, `jest.doMock` with `jest.resetModules()`, and `jest.spyOn` on loaded modules, the `storage-service.ts` module continues to be loaded in its *real* (unmocked) form when `migrations.ts` is loaded.

This behavior is highly unusual for Jest and strongly suggests a fundamental conflict in module loading order, circular dependencies that are difficult to untangle, or a limitation in Jest's ability to mock this specific dependency graph.

To resolve this, it would likely require:
*   **Refactoring the source code of `src/services/storage-service.ts`** to allow a `db` instance to be injected or publicly set for testing purposes. This deviates from the mandate of not altering source code to fix tests.
*   A deeper understanding of the project's specific Webpack/TypeScript/Jest configuration that might be interfering with standard Jest mocking behavior.

As the agent, I am unable to modify the source code or delve into project configuration beyond standard file reading. Therefore, I must conclude that I am **unable to resolve this issue** within the given constraints.

I have spent significant time and tokens attempting to resolve this and am stuck in a loop of the same underlying problem.