# Shared Code Tests

## Purpose

Tests for shared utilities and configuration that work in both main and renderer processes.

## Directory Structure

```
shared/
├── config/
│   ├── app-config.test.ts
│   └── env-validator.test.ts
└── utils/
    └── performance.test.ts
```

## Test Coverage

**Total**: 21/21 tests passing ✅

### By Module
- `config/app-config.test.ts`: 2/2 ✅
- `config/env-validator.test.ts`: 7/7 ✅
- `utils/performance.test.ts`: 12/12 ✅

## Running Tests

```bash
# All shared tests
npm test -- shared

# Specific module
npm test -- shared/config
npm test -- shared/utils
```

## Related Documentation

- [Shared Code](../../shared/README.md)
- [Tests Overview](../README.md)

---

**Last Updated**: 2024-11-30
