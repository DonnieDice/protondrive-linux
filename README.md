# ProtonDrive Linux Client

A native Linux desktop client for ProtonDrive with zero-trust local encryption.

[![CI](https://github.com/yourusername/protondrive-linux/actions/workflows/ci.yml/badge.svg)](https://github.com/yourusername/protondrive-linux/actions/workflows/ci.yml)
[![Go Report Card](https://goreportcard.com/badge/github.com/yourusername/protondrive-linux)](https://goreportcard.com/report/github.com/yourusername/protondrive-linux)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

---

## Features

- **Two-way Sync** - Seamlessly sync files between local machine and ProtonDrive
- **End-to-End Encryption** - ProtonDrive's zero-knowledge encryption for cloud storage
- **Zero-Trust Local Storage** - All local data encrypted (metadata, cache, logs)
- **Native Performance** - Fast startup (<500ms), low memory (<50MB)
- **Universal Hardware** - Runs on Raspberry Pi to workstations
- **Single Binary** - No dependencies to install

---

## Zero-Trust Privacy

This client is built with a **zero-trust privacy philosophy**:

| What's Protected | How |
|------------------|-----|
| Cloud data | ProtonDrive E2E encryption (handled by Proton-API-Bridge) |
| Local metadata | GopenPGP encryption (Proton's official crypto library) |
| Cached files | GopenPGP encryption with filename obfuscation |
| Credentials | OS keyring (GNOME Keyring, KWallet, etc.) |
| Memory | Sensitive data wiped after use |

**Even if an attacker gains filesystem access, they find only encrypted data.**

### What We Don't Do

- ❌ No telemetry or analytics
- ❌ No crash reporting
- ❌ No plaintext logging
- ❌ No unencrypted local storage

---

## Installation

### Pre-built Binaries

Download from [Releases](https://github.com/yourusername/protondrive-linux/releases):

```bash
# x86_64 (most desktops/laptops)
wget https://github.com/yourusername/protondrive-linux/releases/latest/download/protondrive-linux-amd64
chmod +x protondrive-linux-amd64
./protondrive-linux-amd64

# ARM64 (Raspberry Pi 3+, modern ARM)
wget https://github.com/yourusername/protondrive-linux/releases/latest/download/protondrive-linux-arm64
chmod +x protondrive-linux-arm64
./protondrive-linux-arm64
```

### Package Managers

```bash
# Debian/Ubuntu
sudo dpkg -i protondrive-linux_*.deb

# Fedora/RHEL
sudo rpm -i protondrive-linux-*.rpm

# Arch Linux (AUR)
yay -S protondrive-linux
```

### From Source

**Requirements:** Go 1.21+, GCC (for CGO)

```bash
# Clone
git clone https://github.com/yourusername/protondrive-linux.git
cd protondrive-linux

# Build
go build -o protondrive-linux ./cmd/protondrive

# Run
./protondrive-linux
```

---

## Usage

### First Run

```bash
./protondrive-linux
```

1. Enter ProtonDrive credentials
2. Select sync directory (default: `~/ProtonDrive`)
3. Initial sync begins automatically

### Command Line Options

```bash
./protondrive-linux --help

Options:
  --config PATH    Config file path (default: ~/.config/protondrive-linux/config.json)
  --verbose        Enable verbose output (console only, no file logging)
  --profile NAME   Force performance profile (low, standard, high)
  --health         Show health check status and exit
  --version        Show version and exit
```

### System Tray

The app runs in your system tray with:
- Sync status indicator
- Pause/Resume sync
- Quick settings access
- Quit option

---

## Technology Stack

Built with Go and Proton's official libraries:

| Component | Library | Purpose |
|-----------|---------|---------|
| Crypto | [GopenPGP](https://github.com/ProtonMail/gopenpgp) | Proton's official OpenPGP library |
| API | [Proton-API-Bridge](https://github.com/henrybear327/Proton-API-Bridge) | ProtonDrive API integration |
| GUI | [Fyne](https://fyne.io/) | Cross-platform native UI |
| File Watching | [fsnotify](https://github.com/fsnotify/fsnotify) | Filesystem change detection |
| Credentials | [go-keyring](https://github.com/zalando/go-keyring) | OS keyring integration |

**Why these choices?**
- GopenPGP is security-audited and powers all Proton apps
- Proton-API-Bridge handles the complex ProtonDrive encryption scheme
- Fyne provides native look with pure Go (minimal CGO)
- Total: 5-6 dependencies (minimal attack surface)

---

## Development

### Setup

```bash
# Clone
git clone https://github.com/yourusername/protondrive-linux.git
cd protondrive-linux

# Install dependencies
go mod download

# Run tests
go test ./...

# Run with race detector
go test -race ./...

# Build
go build -o protondrive-linux ./cmd/protondrive
```

### Project Structure

```
protondrive-linux/
├── cmd/protondrive/     # CLI entry point
├── internal/
│   ├── encryption/      # GopenPGP wrapper, keyring, memory security
│   ├── sync/            # Sync engine, file watcher, conflict resolution
│   ├── gui/             # Fyne GUI components
│   ├── client/          # Proton-API-Bridge wrapper
│   ├── config/          # Configuration management
│   └── storage/         # Encrypted local storage
├── tests/               # Integration, security, performance tests
├── CLAUDE.md            # Project architecture reference
├── TASKS.md             # Development task tracking
└── CHANGELOG.md         # Release history
```

### Running Tests

```bash
# All tests
go test ./...

# With coverage
go test -cover ./...

# Security tests only
go test ./tests/security/...

# Benchmarks
go test -bench=. ./...
```

### Cross-Compilation

```bash
# Linux AMD64
GOOS=linux GOARCH=amd64 go build -o protondrive-linux-amd64 ./cmd/protondrive

# Linux ARM64
GOOS=linux GOARCH=arm64 go build -o protondrive-linux-arm64 ./cmd/protondrive

# Linux ARMv7 (Raspberry Pi 2)
GOOS=linux GOARCH=arm GOARM=7 go build -o protondrive-linux-armv7 ./cmd/protondrive
```

---

## Configuration

Config file: `~/.config/protondrive-linux/config.json`

```json
{
  "sync_directory": "/home/user/ProtonDrive",
  "performance_profile": "auto",
  "theme": "system",
  "language": "en"
}
```

**Note:** Only non-sensitive settings stored here. Credentials go in OS keyring.

---

## Performance Profiles

The app auto-detects hardware and selects appropriate profile:

| Profile | RAM | Concurrency | Cache | Target Hardware |
|---------|-----|-------------|-------|-----------------|
| Low | <4GB | 1 up, 2 down | 50MB | Raspberry Pi, old laptops |
| Standard | 4-8GB | 3 up, 5 down | 100MB | Most desktops/laptops |
| High | >8GB | 5 up, 10 down | 200MB | Workstations, servers |

Override with `--profile low|standard|high`.

---

## Security

See [SECURITY.md](SECURITY.md) for:
- Encryption details
- Threat model
- Vulnerability reporting

**Key security features:**
- All local data encrypted with GopenPGP (RFC 9580 profile)
- Argon2 key derivation (handled automatically by GopenPGP)
- AES-256 with AEAD for authenticated encryption
- Memory wiping of sensitive data
- No plaintext filenames in logs

---

## Contributing

See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines.

```bash
# Fork and clone
git clone https://github.com/yourusername/protondrive-linux.git

# Create branch
git checkout -b feature/your-feature

# Make changes, test
go test ./...

# Submit PR
```

---

## License

[GNU General Public License v3.0](LICENSE)

---

## Acknowledgments

- [Proton](https://proton.me/) for ProtonDrive and GopenPGP
- [henrybear327](https://github.com/henrybear327) for Proton-API-Bridge
- [Fyne](https://fyne.io/) team for the GUI toolkit

---

## Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/protondrive-linux/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/protondrive-linux/discussions)

**This is an unofficial client.** Not affiliated with or endorsed by Proton AG.