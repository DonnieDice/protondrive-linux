# Development

This guide is for the current Go-based `dev` branch.

## Requirements

- Go 1.24.x
- CGO-capable compiler toolchain for SQLite/SQLCipher work
- Git
- Linux for target runtime testing

On Windows, some tests currently fail because of path assumptions, file deletion behavior, and CGO-disabled SQLite.

## Setup

```bash
git clone https://github.com/DonnieDice/protondrive-linux.git
cd protondrive-linux
git switch dev
go mod download
```

## Verification Commands

Run:

```bash
go build ./...
go test ./...
```

Current expected result: both commands fail until active development blockers are resolved.

## Current Build Blockers

Observed from local verification:

```text
main.go imports github.com/yourusername/protondrive-linux/internal/config
cmd/protondrive/main.go is empty
internal/client imports nonexistent internal/client/keyring and internal/client/session subpackages
internal/testutil/testutil.go has a malformed import path
```

Search for stale imports:

```bash
rg "github.com/yourusername"
```

## Current Test Blockers

Observed from local verification:

- `internal/config` tests fail because expected test config paths differ from `os.UserConfigDir()` on Windows.
- `TestValidate_InvalidSyncDirectory` expects an error, but validation creates missing directories.
- cache deletion tests fail on Windows because files remain open during deletion.
- SQLCipher tests fail when `CGO_ENABLED=0`.

## Code Areas

Entrypoints:

```text
main.go
cmd/protondrive/main.go
```

Configuration and profiles:

```text
internal/config/
internal/profile/
```

Proton API integration:

```text
internal/client/
```

Encryption and local state:

```text
internal/encryption/
internal/storage/
```

Errors and retry:

```text
internal/errors/
```

Tests:

```text
internal/**/*_test.go
tests/security/
```

Planning:

```text
docs/phases/
TASKS.md
```

## WebClients Reference Checkout

The Go branch does not require WebClients for building. Clone it only when analyzing upstream Proton behavior:

```bash
git clone --depth=1 --single-branch --branch main \
  https://github.com/ProtonMail/WebClients.git WebClients
```

Do not commit `WebClients/`.

## Documentation Discipline

When documenting behavior:

- Document implemented behavior separately from intended behavior.
- Use current `go build ./...` and `go test ./...` output as the source of truth for status.
- Keep WebClients analysis separate from Go runtime architecture.
- Do not describe WebClients behavior as part of the Go app unless code actually integrates it.
