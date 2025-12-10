# Changelog

All notable changes to ProtonDrive Linux will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Project documentation structure (CLAUDE.md, TASKS.md, AGENT.md)
- GopenPGP-based encryption architecture design
- Zero-trust security model specification
- Performance profiling system design
- Multi-tier keyring fallback strategy

### Changed
- Simplified crypto stack from ~15 dependencies to 5-6
- Replaced SQLCipher with GopenPGP for local encryption
- Split project context (CLAUDE.md) from task tracking (TASKS.md)
- Streamlined AGENT.md for clarity

### Removed
- SQLCipher dependency (CGO complexity)
- Separate Argon2 implementation (GopenPGP RFC 9580 handles this)
- Third-party crypto packages (using Proton official libraries)

## [0.0.1] - 2024-12-09

### Added
- Initial Go module setup
- Basic project structure
- Configuration system foundation
- Technology stack decision (Go + Fyne + GopenPGP)

---

## Version Format

- **[Unreleased]**: Changes not yet in a release
- **[X.Y.Z]**: Released version with date

## Change Categories

- **Added**: New features
- **Changed**: Changes to existing functionality
- **Deprecated**: Soon-to-be removed features
- **Removed**: Removed features
- **Fixed**: Bug fixes
- **Security**: Security improvements