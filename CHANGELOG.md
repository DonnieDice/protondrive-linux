# Changelog

All notable changes to ProtonDrive Linux will be documented in this file.

This file tracks **releases**, not individual commits. For commit history, see `git log`.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

*Changes here will be included in the next release.*

### Added
- Project documentation structure (CLAUDE.md, TASKS.md, AGENT.md)
- GopenPGP-based encryption architecture design
- Zero-trust security model specification
- Performance profiling system design
- Multi-tier keyring fallback strategy
- CI/CD pipeline for Go (GitHub Actions)

### Changed
- Simplified crypto stack from ~15 dependencies to 5-6
- Replaced SQLCipher with GopenPGP for local encryption
- Split project context (CLAUDE.md) from task tracking (TASKS.md)
- Streamlined AGENT.md for clarity
- Updated README.md with correct dependency list

### Removed
- SQLCipher dependency (CGO complexity)
- Separate Argon2 implementation (GopenPGP RFC 9580 handles this)
- Third-party crypto packages (using Proton official libraries)
- Node.js CI/CD pipeline (replaced with Go)

---

## [0.0.1] - 2024-12-09

### Added
- Initial Go module setup
- Basic project structure
- Configuration system foundation
- Technology stack decision (Go + Fyne + GopenPGP)

---

## Release Process

1. Update version in code
2. Move `[Unreleased]` items to new version section
3. Add release date: `## [X.Y.Z] - YYYY-MM-DD`
4. Commit: `git commit -m "chore: release vX.Y.Z"`
5. Tag: `git tag vX.Y.Z`
6. Push: `git push origin main --tags`
7. GitHub Actions creates release automatically

## Commit Message Convention

For consistent git history, use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Formatting, no code change
- `refactor`: Code change that neither fixes nor adds
- `perf`: Performance improvement
- `test`: Adding/updating tests
- `chore`: Maintenance tasks

**Examples:**
```
feat(encryption): add GopenPGP wrapper for local storage
fix(sync): handle rate limit 429 responses correctly
docs(readme): update installation instructions
test(encryption): add memory wiping verification tests
chore: release v0.1.0
```

## Change Categories

- **Added**: New features
- **Changed**: Changes to existing functionality
- **Deprecated**: Soon-to-be removed features
- **Removed**: Removed features
- **Fixed**: Bug fixes
- **Security**: Security improvements