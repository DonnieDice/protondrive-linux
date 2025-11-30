# GitHub Actions Workflows

## Purpose

CI/CD workflow definitions for automated testing and deployment.

## Workflows

### `ci.yml`
**Name**: CI/CD Pipeline  
**Triggers**: Push and PR to main/alpha/dev branches  
**Runner**: ubuntu-24.04  
**Node Version**: 20

**Steps**:
1. Checkout code
2. Setup Node.js with npm cache
3. Install dependencies (npm install + npm ci)
4. Run tests with verbose output
5. Run ESLint

**Status**: ✅ Passing

## Related Documentation

- [GitHub Config](../README.md)

---

**Last Updated**: 2024-11-30
