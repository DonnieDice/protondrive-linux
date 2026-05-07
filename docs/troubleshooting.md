# Troubleshooting

This page records current known issues on the Go-based `dev` branch.

## `go build ./...` Fails

Observed failures:

```text
main.go: no required module provides package github.com/yourusername/protondrive-linux/internal/config
cmd/protondrive/main.go: expected 'package', found 'EOF'
internal/client/client.go: no required module provides package github.com/yourusername/protondrive-linux/internal/client/keyring
internal/client/client.go: no required module provides package github.com/yourusername/protondrive-linux/internal/client/session
internal/testutil/testutil.go: missing import path
```

Likely fixes:

- Replace stale `github.com/yourusername/protondrive-linux` imports with `github.com/donniedice/protondrive-linux`.
- Add a valid package declaration and implementation to `cmd/protondrive/main.go`.
- Either move `keyring.go` and `session.go` into subpackages or update imports to match the current `internal/client` package.
- Fix malformed imports in `internal/testutil/testutil.go`.

## Find Stale Imports

```bash
rg "github.com/yourusername"
```

## Config Tests Fail On Windows

Observed failures include path mismatches such as:

```text
expected temp test path
actual C:\Users\...\AppData\Roaming\protondrive-linux\config.json
```

Cause:

- tests expect overridden config roots, but implementation uses `os.UserConfigDir()` for default paths.
- `LoadConfig(baseDir)` saves default config with `cfg.Save("")`, which ignores the provided base directory.

## Invalid Sync Directory Test Fails

Observed:

```text
TestValidate_InvalidSyncDirectory expected error but got nil
```

Cause:

- `Validate()` creates a missing sync directory instead of failing.

Resolution options:

- update the test to expect directory creation.
- or change validation to fail on missing directories.

Pick the behavior deliberately and document it.

## Cache Delete Tests Fail On Windows

Observed:

```text
The process cannot access the file because it is being used by another process.
```

Cause:

- cache deletion wipes file contents and then deletes the file while Windows still considers the file handle active.

Likely fix:

- close the file before `os.Remove`.

## SQLCipher Tests Fail With CGO Disabled

Observed:

```text
Binary was compiled with 'CGO_ENABLED=0', go-sqlite3 requires cgo to work.
```

Fix:

```bash
CGO_ENABLED=1 go test ./internal/encryption ./internal/storage
```

PowerShell:

```powershell
$env:CGO_ENABLED = "1"
go test ./internal/encryption ./internal/storage
```

You also need a working C compiler toolchain.

## WebClients Confusion

The current Go branch does not build or run WebClients.

Use WebClients only for upstream reference analysis:

```bash
git clone --depth=1 --single-branch --branch main \
  https://github.com/ProtonMail/WebClients.git WebClients
```

Do not treat WebClients build failures as Go app build failures.

## Current Verification Snapshot

Last local docs-branch verification:

```text
go build ./...   failed
go test ./...    failed
```

The failures above are expected until the build-fix workstream lands.
