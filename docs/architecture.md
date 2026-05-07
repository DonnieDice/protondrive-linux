# Architecture

This document describes the current `dev` branch architecture.

## High-Level Shape

The `dev` branch is a Go-native Proton Drive client foundation. It is not currently a Tauri wrapper and does not embed Proton WebClients at runtime.

Current layers:

```text
main.go / cmd/protondrive
        |
        v
internal/config        system paths, config, capability detection, performance profiles
internal/client        Proton API bridge wrapper, session persistence, keyring helpers
internal/encryption    AES-GCM helpers, encrypted cache, SQLCipher helpers
internal/storage       encrypted metadata database and file models
internal/errors        safe errors and retry policy
internal/profile       profile detector wrapper
tests/security         security-focused tests
```

## Entrypoints

Current root entrypoint:

```text
main.go
```

`main.go` prints a short banner, detects hardware capabilities, chooses a performance profile, and prints RAM/CPU information. It currently imports `github.com/yourusername/protondrive-linux/internal/config`, which prevents builds under the actual module path.

Planned CLI entrypoint:

```text
cmd/protondrive/main.go
```

At the time of analysis, this file is empty, so `go build ./...` fails with `expected 'package', found 'EOF'`.

## Configuration

Package:

```text
internal/config
```

Responsibilities:

- Create default config.
- Load and save JSON config.
- Resolve config, data, and cache directories.
- Validate sync directory, performance profile, and disk type.
- Detect system capabilities from CPU, architecture, RAM, and storage heuristics.
- Select a performance profile.

Important files:

```text
internal/config/config.go
internal/config/paths.go
internal/config/capabilities.go
internal/config/profiles.go
```

Current caveats:

- `LoadConfig(baseDir)` creates the default config with `cfg.Save("")`, which ignores `baseDir`.
- Tests expect environment-controlled config paths that do not match `os.UserConfigDir()` behavior on Windows.
- `Validate()` creates a missing sync directory, so tests expecting an error for a nonexistent path fail.

## Performance Profiles

Profiles implement:

```go
type PerformanceProfile interface {
    MaxConcurrentUploads() int
    MaxConcurrentDownloads() int
    CacheSizeMB() int
    ChunkSizeMB() int
}
```

Current profiles:

| Profile | Uploads | Downloads | Cache | Chunk |
| --- | ---: | ---: | ---: | ---: |
| Low-End | 1 | 2 | 50 MB | 5 MB |
| Standard | 3 | 5 | 100 MB | 5 MB |
| High-End | 5 | 10 | 200 MB | 10 MB |

Selection is RAM-based:

- `< 4 GB`: Low-End
- `< 8 GB`: Standard
- otherwise: High-End

## Proton Client Layer

Package:

```text
internal/client
```

The intended abstraction is:

```go
type ProtonClient interface {
    Login(ctx context.Context, username string, password []byte, rememberMe bool) error
    Logout() error
    IsAuthenticated() bool
    Upload(filepath string) error
    Download(filepath string) error
}
```

`realProtonClient` wraps `Proton-API-Bridge` and stores:

- bridge client
- username
- Proton Drive credential/session

Current caveats:

- Imports point to nonexistent `internal/client/keyring` and `internal/client/session` subpackages, but the files are currently in `internal/client` itself.
- Upload/download/list/create/delete/move operations are TODO stubs.
- "Remember me" currently derives a session encryption key from a fixed passphrase plus username salt. That should not be treated as production-safe.

## Session And Keyring Storage

Current flow:

1. Load session encryption key from OS keyring.
2. Decrypt `session.json.enc` under the user config directory.
3. Initialize Proton API bridge with the loaded session when possible.
4. On login with remember-me enabled, save an encryption key to keyring and save encrypted session data.

Important files:

```text
internal/client/keyring.go
internal/client/session.go
```

Current caveats:

- Keyring fallback is TODO.
- Session key derivation strategy needs redesign.
- Session package paths need to be aligned with the current file layout.

## Encryption

Package:

```text
internal/encryption
```

Implemented helpers include:

- PBKDF2-SHA256 key derivation.
- AES-256-GCM byte encryption/decryption.
- byte-slice key wiping.
- encrypted cache file write/read/delete.
- SQLCipher database helper work.

Current caveats:

- Cache files currently use `os.TempDir()` as a placeholder.
- Windows deletion tests fail because wiped files remain open when deletion is attempted.
- SQLCipher tests require CGO and fail when `CGO_ENABLED=0`.

## Storage

Package:

```text
internal/storage
```

The storage layer manages a SQLite/SQLCipher state database with file metadata.

Current model:

```go
type FileMetadata struct {
    ID         string
    Name       string
    Size       int64
    ModTime    time.Time
    IsDir      bool
    Hash       string
    RemotePath string
    LocalPath  string
    SyncStatus SyncStatus
    CreatedAt  time.Time
    UpdatedAt  time.Time
}
```

Current caveats:

- SQLCipher connection string should be reviewed carefully.
- The driver import and driver name need verification.
- Tests depend on CGO-capable SQLite builds.

## WebClients Relationship

The Go application does not currently embed WebClients. WebClients is useful as an upstream reference for:

- Proton Drive web bootstrap.
- account/login flow.
- human verification flow.
- browser download mechanisms.
- crypto worker fallback strategy.

See [WebClients Analysis](webclients-analysis.md).
