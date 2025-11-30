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
- [Roadmap](#roadmap)
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
- **Lightweight performance** - Less than 150MB RAM idle, under 2s cold start, 60 FPS UI
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
- **Performance Budgets** - Enforced limits optimized for low-end hardware
- **Smart Rate Limiting** - p-queue prevents API throttling (10 req/s configurable)
- **Exponential Backoff** - Automatic retry with intelligent failure handling
- **Chunked Uploads** - 5MB chunks enable resume capability and progress tracking
- **Database Optimization** - Indexed queries, ACID transactions, automated backups
- **Bundle Analysis** - Webpack bundle analyzer prevents bloat
- **Memory Profiling** - Automated leak detection and monitoring
- **Low-resource mode** - Optimized for systems with 2GB RAM and older CPUs

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

This project is in active alpha development (Phase 2: Core Services). There are no stable releases yet. 

**Current Status:**
- Project infrastructure complete (Phase 1)
- Core services implementation in progress (Phase 2)
- UI and sync engine pending (Phase 3-4)
- Beta release targeted for Phase 6

Check back later or star the repository to get notified of releases.

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
- **CPU:** Any x86_64 or ARM64 Linux-capable processor (Intel, AMD, ARM)
- **RAM:** Runs on 2GB+ (4GB recommended, 8GB+ for development)
- **Storage:** Works on HDD or SSD (SSD recommended for optimal performance)
- **Architecture:** x86_64, ARM64, ARMv7 (Raspberry Pi compatible)

**Development Requirements:**
- Node.js 18 LTS or 20 LTS (required)
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
│   └── preload/           # Secure IPC bridge (contextBridge)
│       └── index.ts       # Preload script
├── tests/                 # Test files
│   ├── unit/              # Jest unit tests
│   ├── integration/       # Integration tests
│   └── e2e/               # Playwright E2E tests
├── scripts/               # Build and utility scripts
│   ├── run-command.sh     # Command wrapper (prevents lockup)
│   └── memory-test.js     # Memory profiling
├── docs/                  # Documentation
│   ├── architecture/      # Architecture Decision Records (ADRs)
│   ├── development/       # Developer guides
│   └── guides/            # User guides
├── logs/                  # Command execution logs (gitignored)
├── browser_console_logs/  # Electron console logs (gitignored)
├── .agent_logs/           # AI agent logs (gitignored)
├── .gemini/               # AI agent configuration
│   ├── GEMINI.md          # Project context (for AI)
│   ├── agent-docs.md      # Agent operational rules
│   └── task-log.md        # Task tracking
└── sdk-main/              # ProtonDrive SDK (local patched copy)
    └── js/sdk/            # SDK source (excluded from context)
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