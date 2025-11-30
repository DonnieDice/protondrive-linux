# ProtonDrive Linux

Unofficial open-source desktop client for ProtonDrive on Linux.

[![CI](https://github.com/donniedice/protondrive-linux/workflows/CI/badge.svg)](https://github.com/donniedice/protondrive-linux/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.0-blue.svg)](https://www.typescriptlang.org/)
[![Coverage](https://img.shields.io/badge/coverage-80%25-green.svg)](https://github.com/donniedice/protondrive-linux)

> **Status**: Alpha - Phase 2 (Core Services Implementation)  
> **Platform**: Linux Only (Ubuntu, Fedora, Debian, Arch)  
> **Security**: Production-grade encryption & isolation

---

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Available Commands](#available-commands)
- [Tech Stack](#tech-stack)
- [Architecture](#architecture)
- [Contributing](#contributing)
- [Documentation](#documentation)
- [Security](#security)
- [Performance](#performance)
- [Quality Assurance](#quality-assurance)
- [Troubleshooting](#troubleshooting)
- [License](#license)
- [Disclaimer](#disclaimer)
- [Acknowledgments](#acknowledgments)

---

## Features

### Core Features
- **Zero-knowledge encryption** - Files encrypted client-side with AES-256-GCM before upload
- **Real-time synchronization** - Automatic background file sync with conflict resolution
- **Offline mode** - Access files without internet connection, sync when reconnected
- **Universal hardware support** - Runs on any Linux-capable device from Raspberry Pi to workstations
- **Multi-language support** - English, Spanish, French, German via i18next
- **Standalone packages** - AppImage, deb, rpm with zero external dependencies
- **Privacy-first design** - Minimal telemetry (opt-in only), user-controlled data
- **Linux native integration** - Built exclusively for Linux, respects XDG specifications

### Security Features
- **Context Isolation** - Renderer process completely isolated from Node.js APIs
- **Sandboxed Renderer** - OS-level process isolation for defense-in-depth
- **Content Security Policy** - Strict CSP headers prevent script injection
- **Secure Credential Storage** - OS-level encryption via Electron safeStorage API
- **Input Validation** - Zod schema validation prevents injection attacks
- **Automated Vulnerability Scanning** - Dependabot and npm audit in CI/CD pipeline
- **OWASP Top 10 Compliance** - Systematic review against web security standards

### Performance Features
- **Adaptive Performance** - Automatically adjusts to available hardware resources
- **Smart Rate Limiting** - Configurable API request management (10 req/s default)
- **Exponential Backoff** - Automatic retry with intelligent failure handling
- **Chunked Uploads** - 5MB chunks enable resume capability and progress tracking
- **Database Optimization** - Indexed queries, ACID transactions, automated backups
- **Bundle Analysis** - Webpack bundle analyzer prevents bloat
- **Memory Profiling** - Automated leak detection and monitoring

### Developer Experience
- **80% Test Coverage** - Enforced minimum for all code (Jest unit + Playwright E2E)
- **TypeScript Strict Mode** - Zero any types allowed, complete type safety
- **Automated Releases** - Semantic versioning with automated changelog generation
- **Comprehensive Documentation** - Wiki-style docs with Architecture Decision Records
- **Development Tooling** - ESLint, Prettier, Husky git hooks, TypeDoc API docs
- **CI/CD Pipeline** - Automated testing, security scanning, build verification

---

## Quick Start

### For End Users

**WARNING: Not Ready for Production Use**

This project is in active alpha development. There are no stable releases yet. Check back later or star the repository to get notified of releases.

### For Developers

```bash
# Clone repository
git clone https://github.com/donniedice/protondrive-linux.git
cd protondrive-linux

# Install dependencies
npm ci

# Start development server
./scripts/run-command.sh "npm start"

# Run tests
./scripts/run-command.sh "npm test"

# Verify setup
./scripts/run-command.sh "npm run type-check"
./scripts/run-command.sh "npm run lint"
```

---

## Installation

### System Requirements

**Operating System:**
- Ubuntu 20.04 or later
- Fedora 35 or later
- Debian 11 or later
- Arch Linux (rolling)
- Other Linux distributions with glibc 2.31+

**Hardware Compatibility:**
- **CPU:** Any x86_64, ARM64, or ARMv7 processor (Intel, AMD, ARM SoCs)
- **RAM:** 2GB minimum, 4GB recommended, 8GB+ for development
- **Storage:** Works on HDD or SSD (SSD recommended for optimal performance)
- **Architecture:** x86_64, ARM64, ARMv7 (Raspberry Pi 2+ compatible)

**Development Requirements:**
- Node.js 18 LTS or 20 LTS
- npm 9 or higher
- Git 2.25+
- Build tools: gcc, g++, make

### Development Installation

```bash
# Clone repository
git clone https://github.com/donniedice/protondrive-linux.git
cd protondrive-linux

# Install dependencies (clean install recommended)
npm ci

# Copy environment template
cp .env.example .env

# Configure environment (optional for development)
nano .env

# Verify installation
./scripts/run-command.sh "npm run type-check"
./scripts/run-command.sh "npm test"
```

### Future Release Installation

When stable releases are available, installation will be via:

**AppImage (Universal Linux):**
```bash
# Download from releases page
chmod +x ProtonDrive-Linux-x86_64.AppImage
./ProtonDrive-Linux-x86_64.AppImage
```

**Debian/Ubuntu:**
```bash
sudo dpkg -i protondrive-linux_amd64.deb
sudo apt-get install -f  # Fix dependencies if needed
```

**Fedora/RHEL:**
```bash
sudo rpm -i protondrive-linux.x86_64.rpm
```

**Arch Linux (AUR):**
```bash
yay -S protondrive-linux
# or
paru -S protondrive-linux
```

---

## Development Setup

### Initial Setup

1. **Clone and install dependencies:**
   ```bash
   git clone https://github.com/donniedice/protondrive-linux.git
   cd protondrive-linux
   npm ci
   ```

2. **Configure environment (optional):**
   ```bash
   cp .env.example .env
   # Edit .env if needed for custom configuration
   ```

3. **Verify setup:**
   ```bash
   ./scripts/run-command.sh "npm run type-check"
   ./scripts/run-command.sh "npm run lint"
   ./scripts/run-command.sh "npm test"
   ```

### Running the Application

```bash
# Start in development mode (hot reload enabled)
./scripts/run-command.sh "npm start"

# Start with verbose logging (debugging)
VERBOSE_LOGGING=true ./scripts/run-command.sh "npm start"

# View structured logs
tail -f logs/command-*.json

# View Electron console logs (if verbose logging enabled)
tail -f browser_console_logs/electron-console-*.log
```

**Important:** Always use `./scripts/run-command.sh` wrapper to prevent terminal lockup from interactive commands.

### Development Workflow

1. **Create feature branch:**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make changes and test:**
   ```bash
   # Run tests in watch mode
   ./scripts/run-command.sh "npm test -- --watch"
   
   # Check types
   ./scripts/run-command.sh "npm run type-check"
   
   # Lint code
   ./scripts/run-command.sh "npm run lint"
   ```

3. **Commit using conventional format:**
   ```bash
   git commit -m "feat(scope): add new feature"
   ```

4. **Push and create pull request:**
   ```bash
   git push origin feature/your-feature-name
   ```

---

## Project Structure

```
protondrive-linux/
├── src/
│   ├── main/              # Electron main process (Node.js environment)
│   │   ├── index.ts       # Application entry point
│   │   └── window.ts      # Window management
│   ├── renderer/          # React UI (browser environment)
│   │   ├── App.tsx        # Root component
│   │   ├── components/    # React components
│   │   └── stores/        # Zustand state stores
│   ├── services/          # Business logic services
│   │   ├── auth-service.ts
│   │   ├── storage-service.ts
│   │   ├── sync-service.ts
│   │   └── sdk-bridge.ts
│   ├── shared/            # Shared utilities and types
│   │   ├── types/         # TypeScript type definitions
│   │   └── utils/         # Utility functions
│   ├── preload/           # Secure IPC bridge (contextBridge)
│   │   └── index.ts       # Preload script
│   └── __tests__/         # Test files
├── scripts/               # Build and utility scripts
│   └── run-command.sh     # Command wrapper (prevents lockup)
├── docs/                  # Documentation
│   ├── architecture/      # Architecture Decision Records (ADRs)
│   ├── development/       # Developer guides
│   ├── guides/            # User guides
│   └── api/               # API documentation (generated)
├── logs/                  # Command execution logs (gitignored)
├── browser_console_logs/  # Electron console logs (gitignored)
├── .agent_logs/           # AI agent session logs (gitignored)
├── sdk-main/              # ProtonDrive SDK (local patched copy)
│   └── js/sdk/            # SDK source (excluded from context)
├── GEMINI.md              # Project context for AI agents
├── AGENT.md               # AI agent operational rules
├── CONTRIBUTING.md        # Contribution guidelines
├── CODE_OF_CONDUCT.md     # Community standards
└── SECURITY.md            # Security policy
```

---

## Available Commands

### Development

```bash
# Start development server with hot reload
./scripts/run-command.sh "npm start"

# Run unit tests
./scripts/run-command.sh "npm test"

# Run tests in watch mode (TDD)
./scripts/run-command.sh "npm test -- --watch"

# Run tests with coverage report (80% minimum enforced)
./scripts/run-command.sh "npm test -- --coverage"

# Run end-to-end tests (Playwright)
./scripts/run-command.sh "npm run test:e2e"

# Run integration tests
./scripts/run-command.sh "npm run test:integration"

# Type checking (TypeScript strict mode)
./scripts/run-command.sh "npm run type-check"

# Linting (ESLint with auto-fix)
./scripts/run-command.sh "npm run lint"
./scripts/run-command.sh "npm run lint:fix"

# Code formatting (Prettier)
npm run format
npm run format:check
```

### Building

```bash
# Build for production (optimized bundles)
./scripts/run-command.sh "npm run build"

# Package application (creates executable)
./scripts/run-command.sh "npm run package"

# Create distributable installers (AppImage, deb, rpm)
./scripts/run-command.sh "npm run make"

# Clean build artifacts
rm -rf dist out .webpack
```

### Documentation

```bash
# Generate API documentation (TypeDoc)
npm run docs

# Serve API documentation locally (http://localhost:8080)
npm run docs:serve

# Generate coverage report
npm run test:coverage
```

---

## Tech Stack

### Core Technologies
- **Electron** 28+ - Cross-platform desktop framework (Linux target only)
- **TypeScript** 5+ - Type-safe development with strict mode
- **React** 18+ - User interface framework
- **Node.js** v18/v20 LTS - Runtime environment

### State & Data
- **Zustand** - Lightweight state management (chosen over Redux)
- **better-sqlite3** - Synchronous SQLite database with ACID transactions
- **Winston** - Structured application logging with file rotation
- **Sentry** - Error tracking and crash reporting (production only)
- **Aptabase** - Privacy-friendly analytics (opt-in)

### Development Tools
- **Webpack** 5+ - Module bundler with tree-shaking
- **Electron Forge** 7+ - Build and packaging automation
- **Jest** 29+ - Unit testing framework
- **Playwright** 1.40+ - End-to-end testing
- **ESLint** 8+ - Code quality enforcement
- **Prettier** 3+ - Code formatting
- **Husky** 8+ - Git hooks for pre-commit checks
- **semantic-release** 22+ - Automated versioning and releases

### Network & API
- **axios** - HTTP client with interceptors
- **axios-retry** - Automatic retry with exponential backoff
- **p-queue** - Request queue management with rate limiting
- **ProtonDrive SDK** - JavaScript SDK integration (local patched copy)
- **electron-updater** - Automated application updates

---

## Architecture

### Design Pattern

Classic Electron architecture with service layer isolation:

```
┌─────────────────────────────────────────┐
│         Renderer Process (React)        │
│   - UI Components                       │
│   - Zustand State Management            │
│   - No Node.js Access                   │
└──────────────┬──────────────────────────┘
               │ IPC (contextBridge)
┌──────────────┴──────────────────────────┐
│           Preload Script                │
│   - Secure IPC Bridge                   │
│   - Input Validation (Zod)              │
└──────────────┬──────────────────────────┘
               │
┌──────────────┴──────────────────────────┐
│         Main Process (Node.js)          │
│   - Window Management                   │
│   - Service Layer                       │
│   - Database Access (SQLite)            │
│   - File System Operations              │
│   - ProtonDrive SDK Integration         │
└─────────────────────────────────────────┘
```

### Key Architectural Decisions

- **Context Isolation** - Renderer process isolated from Node.js APIs
- **Service Layer Pattern** - Business logic separated from UI
- **Adapter Pattern** - SDK wrapped in bridge for loose coupling
- **Repository Pattern** - Database access abstracted in storage service
- **Observer Pattern** - Zustand for reactive state management

For detailed architectural decisions, see [docs/architecture/](docs/architecture/).

---

## Contributing

We welcome contributions! Please follow these guidelines.

### Getting Started

1. **Fork the repository**
2. **Clone your fork:**
   ```bash
   git clone https://github.com/YOUR_USERNAME/protondrive-linux.git
   cd protondrive-linux
   ```
3. **Create a branch:**
   ```bash
   git checkout -b feature/your-feature-name
   ```

### Development Workflow

1. **Make your changes** following code standards
2. **Write tests** (80% coverage minimum required)
3. **Run tests:**
   ```bash
   ./scripts/run-command.sh "npm test"
   ./scripts/run-command.sh "npm run lint"
   ```
4. **Commit your changes** using conventional format
5. **Push to your fork**
6. **Open a Pull Request**

### Commit Message Format

We use [Conventional Commits](https://www.conventionalcommits.org/) for automated changelog generation.

**Format:**
```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation changes
- `style` - Code style/formatting
- `refactor` - Code refactoring
- `perf` - Performance improvements
- `test` - Test additions/changes
- `chore` - Build/tooling changes

**Examples:**
```bash
feat(auth): add OAuth2 login flow
fix(sync): resolve duplicate upload issue
docs(readme): update installation instructions
test(storage): add database migration tests
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for complete guidelines.

### Code Standards

- **TypeScript**: Strict mode, no `any` types
- **Testing**: 80% coverage minimum (enforced in CI)
- **Linting**: ESLint rules enforced
- **Formatting**: Prettier via pre-commit hooks
- **Line length**: 100 characters maximum
- **Indentation**: 2 spaces, no tabs

---

## Documentation

### For Users
- **README** - This file (installation and usage)
- **Security Policy** - [SECURITY.md](SECURITY.md)
- **Code of Conduct** - [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)

### For Developers
- **Contributing Guide** - [CONTRIBUTING.md](CONTRIBUTING.md)
- **Architecture Documentation** - [docs/architecture/](docs/architecture/)
- **Development Guides** - [docs/development/](docs/development/)
- **API Documentation** - [docs/api/](docs/api/) (generated via TypeDoc)

### For AI Agents
- **Project Context** - [GEMINI.md](GEMINI.md) (complete project overview and tasks)
- **Agent Operations** - [AGENT.md](AGENT.md) (operational rules and protocols)

### Additional Resources
- **User Guides** - [docs/guides/](docs/guides/)
- **Changelog** - Generated automatically via semantic-release

---

## Security

### Security Features

- **Context Isolation** - Renderer process isolated from Node.js APIs
- **Sandboxed Renderer** - OS-level process isolation
- **Node Integration Disabled** - Prevents direct Node.js access from UI
- **Content Security Policy** - Strict CSP headers prevent script injection
- **Secure Credential Storage** - OS-level encryption via safeStorage API
- **Client-side Encryption** - Files encrypted with AES-256-GCM before upload
- **Zero-knowledge Architecture** - Maintains ProtonDrive's privacy model
- **Input Validation** - Zod schema validation prevents injection attacks
- **Automated Vulnerability Scanning** - Dependabot + npm audit in CI/CD

### Reporting Vulnerabilities

**DO NOT** open public issues for security vulnerabilities.

Please report security issues via email or see [SECURITY.md](SECURITY.md) for our security policy and responsible disclosure process.

**Expected Response Time**: 48 hours

### Security Documentation

- [Security Policy](SECURITY.md) - Vulnerability reporting and security practices
- [Security Architecture](docs/architecture/) - Security design documentation

---

## Performance

### Performance Targets

Application performance adapts to available hardware:

**Low-End Hardware (2-4GB RAM):**
- Under 100MB RAM idle
- Under 3s cold start
- 30 FPS UI minimum
- 1-2 files/second sync

**Standard Hardware (4-8GB RAM):**
- Under 150MB RAM idle
- Under 2s cold start
- 60 FPS UI
- 5 files/second sync

**High-End Hardware (8GB+ RAM):**
- Under 200MB RAM idle
- Under 1.5s cold start
- 60 FPS UI
- 10+ files/second sync

### Performance Features

- **Adaptive Performance** - Detects system resources and adjusts behavior
- **Efficient Database** - Indexed SQLite queries with ACID transactions
- **Chunked Transfers** - 5MB chunks for large file handling
- **Smart Rate Limiting** - Configurable concurrent request management
- **Bundle Optimization** - Webpack tree-shaking and code splitting
- **Memory Profiling** - Automated leak detection

See [docs/architecture/](docs/architecture/) for performance details.

---

## Quality Assurance

### Testing Strategy

- **Unit Tests** - Jest with 80% minimum coverage (enforced in CI)
- **Integration Tests** - Service-to-service testing
- **E2E Tests** - Playwright for user workflow testing
- **Performance Tests** - Automated benchmark validation
- **Security Tests** - OWASP Top 10 compliance checks

### Code Quality

- **TypeScript Strict Mode** - Zero `any` types allowed
- **ESLint** - Code quality rules enforced
- **Prettier** - Consistent code formatting
- **Husky Git Hooks** - Pre-commit validation
- **CI/CD Pipeline** - Automated quality gates

### Test Coverage Requirements

All code must maintain 80% minimum test coverage:
- Unit tests for business logic
- Integration tests for service interactions
- E2E tests for critical user workflows
- Performance tests for budget validation

---

## Troubleshooting

### Application Won't Start

```bash
# Check logs
tail -f logs/command-*.json

# Verify dependencies
npm ci

# Rebuild native modules
npm run rebuild
```

### Development Issues

**Terminal locks up:**
- Always use `./scripts/run-command.sh` wrapper
- Never run `npm start` directly

**Tests failing:**
```bash
# Clear cache and reinstall
rm -rf node_modules package-lock.json
npm install
npm test
```

**Build errors:**
```bash
# Clean build artifacts
rm -rf dist out .webpack
npm run build
```

### Verbose Logging

Enable verbose logging for debugging:

```bash
# Add to .env file
echo "VERBOSE_LOGGING=true" >> .env

# Or use environment variable
VERBOSE_LOGGING=true ./scripts/run-command.sh "npm start"

# View browser console logs
tail -f browser_console_logs/electron-console-*.log
```

### Getting Help

- **Issues**: [GitHub Issues](https://github.com/donniedice/protondrive-linux/issues)
- **Discussions**: [GitHub Discussions](https://github.com/donniedice/protondrive-linux/discussions)
- **Documentation**: [docs/](docs/)

---

## License

MIT License - see [LICENSE](LICENSE) file for details.

Copyright (c) 2024 ProtonDrive Linux Contributors

---

## Disclaimer

**This is an unofficial client**, not affiliated with or endorsed by Proton AG.

**Important Notice:**
- This software is in **alpha development** stage
- **Not suitable for production use**
- **Always backup important files** before using
- Use at your own risk
- **Linux only** - No macOS or Windows support planned
- No warranty provided (see LICENSE)

---

## Acknowledgments

### Core Dependencies
- **Proton AG** - For ProtonDrive and the JavaScript SDK
- **Electron Community** - For the desktop application framework
- **TypeScript Team** - For the TypeScript language
- **React Team** - For the React framework

### Contributors
Thank you to all contributors who help improve this project.

### Community
Built with and for the Linux community.

---

**Project Status**: Active Development  
**Current Phase**: Phase 2 - Core Services Implementation  
**Last Updated**: 2024-11-30  
**Maintainers**: See [CONTRIBUTING.md](CONTRIBUTING.md)

For complete project context and development guidelines, see [GEMINI.md](GEMINI.md)  
For AI agent operational rules, see [AGENT.md](AGENT.md)