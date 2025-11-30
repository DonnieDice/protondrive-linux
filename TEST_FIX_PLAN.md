# Test Fix Plan - Systematic Approach

## Current Status
- **Passing**: 4 test suites (51 tests) ✅
- **Failing**: 4 test suites (42 tests) ❌

## Root Cause Analysis

### Issue 1: backup-service.test.ts (30 failures)
**Error**: `TypeError: logger_1.default.info is not a function`

**Root Cause**: The inline mock in the test file creates a mock object, but when the backup-service imports logger, it's getting the real Winston logger instance instead of the mock.

**Solution**: Use `jest.mock()` with a factory function that returns the mock BEFORE any imports.

### Issue 2: analytics.test.ts (5 failures)
**Error**: Logger spy not capturing calls

**Root Cause**: The test creates spies on the logger object, but the analytics module has already imported and cached the real logger instance.

**Solution**: Mock the logger module before importing analytics, and use the mocked logger instance.

### Issue 3: logger.test.ts (5 failures)
**Error**: Winston mocks not being called

**Root Cause**: The logger module is imported and executed before the Winston mocks are set up, so it uses the real Winston library.

**Solution**: Use `jest.resetModules()` and dynamic imports to ensure mocks are applied before the logger module loads.

### Issue 4: storage-service.test.ts (2 failures)
**Error 1**: Path mismatch - Expected "/mock/user/data/protondrive.sqlite" but got "/tmp/mock-user-data/protondrive.sqlite"
**Error 2**: app.quit not being called

**Root Cause**: The mock for `app.getPath('userData')` is returning a different path, and the error handling doesn't call app.quit in the test scenario.

**Solution**: Update test expectations to match actual mock behavior, or fix the mock setup.

## Execution Plan

### Step 1: Fix backup-service.test.ts ✅
1. Move jest.mock() to the very top of the file
2. Ensure the mock returns a proper default export
3. Clear all mocks in beforeEach

### Step 2: Fix analytics.test.ts ✅
1. Mock logger before importing analytics
2. Use jest.resetModules() between tests
3. Import analytics dynamically after mocks are set up

### Step 3: Fix storage-service.test.ts ✅
1. Fix the path expectation to match the actual mock return value
2. Verify app.quit is called in error scenarios

### Step 4: Fix logger.test.ts ✅
1. Use jest.resetModules() before each test
2. Set up Winston mocks before importing logger
3. Import logger dynamically after mocks are configured

## Expected Outcome
- All 93 tests passing
- CI/CD pipeline green
- Solid foundation for implementing P0 Foundation Layer
