# ProtonDrive Linux Client

Unofficial open-source desktop client for ProtonDrive on Linux.

[![CI](https://github.com/donniedice/protondrive-linux/workflows/CI/badge.svg)](https://github.com/donniedice/protondrive-linux/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Table of Contents

*   [Project Overview](#project-overview)
*   [Features](#features)
*   [Installation](#installation)
*   [Quick Start](#quick-start)
*   [Development Setup](#development-setup)
*   [Project Structure](#project-structure)
*   [Tech Stack](#tech-stack)
*   [Contributing](#contributing)
*   [Code Standards](#code-standards)
*   [Documentation](#documentation)
*   [Roadmap](#roadmap)
*   [Performance](#performance)
*   [Security](#security)
*   [Troubleshooting](#troubleshooting)
*   [Support](#support)
*   [License](#license)
*   [Disclaimer](#disclaimer)
*   [Acknowledgments](#acknowledgments)

## Project Overview

This project provides an unofficial, open-source desktop client for ProtonDrive, specifically targeting Linux distributions. It is currently under active development.

*   **Status**: Alpha - Under active development
*   **Platform**: Linux only (Ubuntu, Fedora, Debian, Arch, etc.)

## Features

*   Zero-knowledge encryption: Files are encrypted client-side before upload.
*   Real-time synchronization: Automatic background synchronization of files.
*   Offline mode: Access and work with files even without an internet connection.
*   Lightweight resource usage: Designed for efficiency with minimal RAM usage (<150MB) and a small installer size (<80MB).
*   Multi-language support: Available in English, Spanish, French, and German.
*   Standalone distribution: Provided as AppImage, .deb, and .rpm packages with no additional dependencies.

## Installation

### AppImage (Recommended - Universal)

```bash
# Download latest release
wget https://github.com/donniedice/protondrive-linux/releases/latest/download/ProtonDrive-Linux-x86_64.AppImage

# Make executable
chmod +x ProtonDrive-Linux-x86_64.AppImage

# Run
./ProtonDrive-Linux-x86_64.AppImage
```

### Debian/Ubuntu

```bash
wget https://github.com/donniedice/protondrive-linux/releases/latest/download/protondrive-linux_amd64.deb
sudo dpkg -i protondrive-linux_amd64.deb
```

### Fedora/RHEL

```bash
wget https://github.com/donniedice/protondrive-linux/releases/latest/download/protondrive-linux.x86_64.rpm
sudo rpm -i protondrive-linux.x86_64.rpm
```

## Quick Start

1.  Launch the application from your application menu or command line.
2.  Sign in with your ProtonDrive credentials.
3.  Choose your sync folder: Select which local folder to synchronize.
4.  Start syncing: Files will automatically synchronize in the background.

## Development Setup

### Prerequisites

*   Node.js 18 or 20 (LTS)
*   npm 9+
*   Linux operating system

### Install Dependencies

```bash
git clone https://github.com/donniedice/protondrive-linux.git
cd protondrive-linux
npm ci
```

### Run Development Mode

```bash
# Start the app in development mode
./scripts/run-command.sh "npm start"

# View logs
tail -f logs/command-*.json
```

### Run Tests

```bash
# Unit tests
./scripts/run-command.sh "npm test"

# E2E tests
./scripts/run-command.sh "npm run test:e2e"

# Coverage report
./scripts/run-command.sh "npm test -- --coverage"
```

### Build Packages

```bash
# Build all packages (AppImage, deb, rpm)
./scripts/run-command.sh "npm run make"

# Packages will be in out/make/
```

## Project Structure

The project follows a standard Electron-Forge structure, separating main, renderer, and shared processes, with dedicated directories for services, utilities, and configuration.

```
protondrive-linux/
├── src/
│   ├── main/          # Electron Main Process (backend logic)
│   ├── renderer/      # React UI (frontend)
│   ├── services/      # Business logic and SDK integration
│   ├── shared/        # Shared types, constants, config, and utilities
│   ├── preload/       # Secure IPC bridge
│   └── __tests__/     # Unit test files
├── sdk-main/          # ProtonDrive SDK (patched local copy)
├── tests/             # E2E test files
├── docs/              # Project documentation
├── scripts/           # Build and utility scripts
└── config/            # Webpack and Electron Forge configuration
```

## Tech Stack

*   **Electron**: Desktop application framework (Linux-only target)
*   **TypeScript**: Ensures type safety and improves code quality
*   **React**: UI framework for building interactive user interfaces
*   **Zustand**: Lightweight state management solution
*   **better-sqlite3**: Local database with migrations for persistent data storage
*   **Winston**: Structured logging for application events
*   **Axios**: HTTP client for API interactions with retry logic
*   **p-queue**: Manages API request concurrency and rate limiting
*   **electron-updater**: Provides automatic application updates

## Contributing

We welcome contributions from the community! Please refer to our [CONTRIBUTING.md](CONTRIBUTING.md) guide for detailed instructions on how to set up your development environment, submit changes, and adhere to our code standards.

## Code Standards

*   TypeScript strict mode is enforced.
*   Minimum 80% test coverage is required for new code.
*   Code quality is maintained using ESLint and Prettier.
*   Conventional Commits are used for clear and consistent commit history.

## Documentation

*   **User Guide**: [docs/guides/user-guide.md](docs/guides/user-guide.md)
*   **API Documentation**: [docs/api/](docs/api/index.md) (generated with TypeDoc)
*   **Architecture**: [docs/architecture/](docs/architecture/index.md)
*   **Security Policy**: [SECURITY.md](SECURITY.md)
*   **Code of Conduct**: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
*   **Detailed Project Context for AI Agents**: [.gemini/GEMINI.md](.gemini/GEMINI.md)

## Roadmap

The project development is structured into several phases to systematically build and deliver the ProtonDrive Linux Client.

*   **Phase 0: Infrastructure (COMPLETE)**: Foundation, tooling, and CI/CD are established.
*   **Phase 1: Configuration (COMPLETE)**: Project configuration and legal documents are finalized.
*   **Phase 2: Core Services (CURRENT)**: Backend logic for authentication, data storage, sync, and more.
*   **Phase 3: UI Foundation**: Development of the user interface components and pages.
*   **Phase 4: Sync Engine**: Implementation of file synchronization and conflict resolution.
*   **Phase 5: Advanced Features**: Integration of features like system tray, selective sync, and offline mode.
*   **Phase 6: Distribution**: Packaging for Linux, auto-update testing, and beta program.
*   **Final Steps: Go Live**: Public release and ongoing monitoring.

For a detailed breakdown of tasks within each phase, please consult the [.gemini/GEMINI.md](.gemini/GEMINI.md) file.

## Performance

The application is developed with specific performance targets to ensure a responsive and efficient user experience:

*   **Installer Size**: <80 MB
*   **RAM Usage (Idle)**: <150 MB
*   **RAM Usage (Active)**: <300 MB
*   **Cold Start Time**: <1.5 seconds
*   **UI Frame Rate**: 60 FPS

Detailed performance budgets and metrics are available in [docs/architecture/performance-budget.md](docs/architecture/performance-budget.md).

## Security

Security is a paramount concern for ProtonDrive Linux. Key security measures include:

*   Context isolation and sandboxed renderer processes.
*   Strict Content Security Policy (CSP).
*   Client-side encryption using AES-256-GCM.
*   Secure storage of sensitive data using Electron's `safeStorage` (no `localStorage`).

A complete overview of the security model and checklist can be found in [docs/architecture/security-checklist.md](docs/architecture/security-checklist.md).

## Troubleshooting

### App won't start

```bash
# Check logs for errors
tail -f logs/command-*.json

# Verify installed dependencies
npm ci

# Rebuild native modules if necessary
npm run rebuild
```

### Sync issues

1.  Check your internet connection.
2.  Verify your ProtonDrive credentials.
3.  Examine application logs located in `~/.config/protondrive-linux/logs/`.
4.  If the issue persists, report it on [GitHub Issues](https://github.com/donniedice/protondrive-linux/issues) with logs attached.

### Performance problems

```bash
# Run the memory profiler
./scripts/memory-test.js

# Check performance-related log entries
grep "SLOW" logs/*.json
```

## Support

For questions, bug reports, or feature requests, please use the following resources:

*   **Issues**: [GitHub Issues](https://github.com/donniedice/protondrive-linux/issues)
*   **Discussions**: [GitHub Discussions](https://github.com/donniedice/protondrive-linux/discussions)
*   **Security**: See [SECURITY.md](SECURITY.md) for instructions on how to report vulnerabilities responsibly.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for full details.

## Disclaimer

This is an **unofficial client**, not affiliated with or endorsed by Proton AG.

*   This is alpha software; use at your own risk.
*   Always back up important files.
*   Linux only; no macOS or Windows support is planned.

## Acknowledgments

We extend our gratitude to:

*   **Proton AG**: For developing ProtonDrive and the underlying JavaScript SDK.
*   **The Electron Community**: For providing the robust framework that powers this desktop client.
*   **Our Contributors**: Every individual who helps improve and maintain this project.

---

**Built with dedication for the Linux community.**