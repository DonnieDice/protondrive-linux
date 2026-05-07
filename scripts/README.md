# Scripts Directory

## Purpose

Build scripts, utilities, and helper scripts for development and deployment.

## Files

### `run-command.sh`
**Purpose**: Wrapper script for running npm commands without terminal lockup  
**Usage**:
```bash
./scripts/run-command.sh "npm start"
./scripts/run-command.sh "npm test"
```

**Why**: Prevents terminal from locking up when running Electron in development mode.

## Planned Scripts

- `memory-test.js` - Memory usage profiling
- `build.sh` - Production build script
- `package.sh` - Package for distribution
- `clean.sh` - Clean build artifacts

## Related Documentation

- [Project README](../README.md)
- [AGENTS.md](../AGENTS.md)

---

**Last Updated**: 2024-11-30
