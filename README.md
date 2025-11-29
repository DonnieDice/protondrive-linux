# ProtonDrive Linux

Unofficial open-source desktop client for ProtonDrive on Linux.

[![CI](https://github.com/donniedice/protondrive-linux/workflows/CI/badge.svg)](https://github.com/donniedice/protondrive-linux/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> **Status**: Alpha - Under active development  
> **Platform**: Linux only (Ubuntu, Fedora, Debian, Arch)

## Features

- 🔐 **Zero-knowledge encryption** - Files encrypted client-side before upload
- 🔄 **Real-time sync** - Automatic background synchronization
- 💾 **Offline mode** - Access files without internet connection
- 🚀 **Lightweight** - <150MB RAM usage, <80MB installer
- 🌍 **Multi-language** - English, Spanish, French, German
- 📦 **Standalone** - AppImage, deb, rpm packages with no dependencies

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

1. **Launch the application** from your application menu or command line
2. **Sign in** with your ProtonDrive credentials
3. **Choose sync folder** - Select which local folder to sync
4. **Start syncing** - Files automatically sync in the background

## Development Setup

### Prerequisites

- Node.js 18 or 20 (LTS)
- npm 9+
- Linux operating system

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

```
protondrive-linux/
├── src/
│   ├── main/          # Electron main process
│   ├── renderer/      # React UI
│   ├── services/      # Business logic
│   └── shared/        # Shared utilities
├── scripts/           # Build and utility scripts
├── tests/             # Test files
├── docs/              # Documentation
└── .gemini/           # Project context (for AI agents)
```

## Tech Stack

- **Electron** - Desktop framework
- **TypeScript** - Type safety
- **React** - UI framework
- **Zustand** - State management
- **SQLite** - Local database
- **ProtonDrive SDK** - API integration

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Quick Contribution Steps

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for your changes (80% coverage required)
4. Commit using conventional format (`git commit -m "feat: add amazing feature"`)
5. Push to your branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

### Code Standards

- TypeScript strict mode
- 80% test coverage minimum
- ESLint + Prettier enforced
- Conventional commits

## Documentation

- **User Guide**: [docs/guides/user-guide.md](docs/guides/user-guide.md)
- **API Documentation**: [docs/api/](docs/api/) (generated with TypeDoc)
- **Architecture**: [docs/architecture/](docs/architecture/)
- **For AI Agents**: [.gemini/GEMINI.md](.gemini/GEMINI.md) - Complete project context

## Roadmap

- [x] Infrastructure and security setup
- [x] Loop prevention system for AI agents
- [ ] Core services (auth, sync, storage) - **In Progress**
- [ ] UI components (login, file browser)
- [ ] Sync engine with conflict resolution
- [ ] System tray integration
- [ ] Beta release

See [.gemini/task-log.md](.gemini/task-log.md) for detailed progress.

## Performance

Our performance targets:

- Installer: <80MB
- RAM (idle): <150MB  
- RAM (active): <300MB
- Cold start: <1.5s
- UI: 60 FPS

See [docs/architecture/performance-budget.md](docs/architecture/performance-budget.md) for details.

## Security

- Context isolation enabled
- Sandboxed renderer process
- Content Security Policy enforced
- Client-side encryption (AES-256-GCM)
- No localStorage - uses Electron safeStorage

See [docs/architecture/security-checklist.md](docs/architecture/security-checklist.md) for complete security model.

## Troubleshooting

### App won't start

```bash
# Check logs
tail -f logs/command-*.json

# Verify dependencies
npm ci

# Rebuild native modules
npm run rebuild
```

### Sync issues

1. Check internet connection
2. Verify ProtonDrive credentials
3. Check logs in `~/.config/protondrive-linux/logs/`
4. Report issue with logs attached

### Performance problems

```bash
# Run memory profiler
./scripts/memory-test.js

# Check performance logs
grep "SLOW" logs/*.json
```

## Support

- **Issues**: [GitHub Issues](https://github.com/donniedice/protondrive-linux/issues)
- **Discussions**: [GitHub Discussions](https://github.com/donniedice/protondrive-linux/discussions)
- **Security**: See [SECURITY.md](SECURITY.md) for vulnerability reporting

## License

MIT License - see [LICENSE](LICENSE) for details.

## Disclaimer

**This is an unofficial client**, not affiliated with or endorsed by Proton AG.

- Alpha software - use at your own risk
- Always backup important files
- Linux only - no macOS or Windows support

## Acknowledgments

- **Proton AG** - For ProtonDrive and the JavaScript SDK
- **Electron Community** - For the desktop framework
- **Contributors** - Everyone who helps improve this project

---

**Built with ❤️ for the Linux community**