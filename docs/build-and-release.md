# Build And Release

This branch is not ready for release packaging. The current goal is to make the Go application build-clean and testable first.

## Current Verification Status

Local verification from the docs branch:

```text
go build ./...   FAIL
go test ./...    FAIL
```

Do not cut releases from this branch until those commands pass in the target Linux environment.

## Build Command

Expected build command once blockers are fixed:

```bash
go build ./...
```

Expected application build target once `cmd/protondrive/main.go` is implemented:

```bash
go build -o protondrive-linux ./cmd/protondrive
```

## Test Command

```bash
go test ./...
```

SQLite/SQLCipher tests need CGO support:

```bash
CGO_ENABLED=1 go test ./...
```

On Windows PowerShell:

```powershell
$env:CGO_ENABLED = "1"
go test ./...
```

## Pre-Release Criteria

Before release packaging, require:

- `go build ./...` passes.
- `go test ./...` passes on Linux.
- stale `github.com/yourusername/...` imports are gone.
- `cmd/protondrive/main.go` is implemented.
- client package paths match the actual package layout.
- session/keyring security design is reviewed.
- upload/download/list/delete/move behavior is implemented or explicitly excluded from the release.
- sensitive data handling tests pass.
- packaging scripts are created and tested.

## Current GitHub Workflows

Inspect:

```text
.github/
```

The current branch should not assume release automation is complete until build/test status is green.

## Versioning

No final version source of truth is documented yet for the Go branch. Before packaging, choose and document whether version comes from:

- Git tags.
- a generated build variable.
- a package metadata file.
- release workflow input.

## Release Artifact Direction

Likely future artifacts:

- single Linux binary
- `.deb`
- `.rpm`
- AppImage or portable tarball
- AUR package

Those are intended directions, not current verified outputs.
