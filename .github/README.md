# GitHub Configuration

## Purpose

GitHub-specific configuration files for CI/CD, issue templates, and repository settings.

## Directory Structure

```
.github/
└── workflows/
    └── ci.yml
```

## Files

### `workflows/ci.yml`
GitHub Actions CI/CD pipeline configuration.

**Triggers**:
- Push to main, alpha, dev branches
- Pull requests to main, alpha, dev branches

**Jobs**:
1. Setup Node.js 20
2. Install dependencies
3. Run tests (85/85 passing)
4. Run linting (0 errors)

## CI/CD Status

✅ All checks passing

## Related Documentation

- [Project README](../README.md)

---

**Last Updated**: 2024-11-30
