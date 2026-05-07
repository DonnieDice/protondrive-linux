# ProtonDrive Linux

Native Linux client work-in-progress for Proton Drive, written in Go.

The current `dev` branch is a Go application foundation for a zero-trust local Proton Drive client. It is not the Tauri/WebClients wrapper that exists on other branches. The codebase currently focuses on configuration, hardware profile detection, safe error handling, encrypted local state, encrypted cache/session storage, and early Proton API bridge integration.

## Current Status

This branch is under active development and is not currently build-clean.

Verified locally on Windows from `docs/comprehensive-docs`:

```text
go build ./...   fails
go test ./...    fails
```

Primary blockers observed:

- Several imports still use `github.com/yourusername/protondrive-linux` instead of `github.com/donniedice/protondrive-linux`.
- `cmd/protondrive/main.go` is empty.
- `internal/testutil/testutil.go` has a malformed import block.
- `main.go` is a capability/profile demo, not a full client entrypoint.
- `internal/client` file operations are mostly TODO stubs.
- SQLite/SQLCipher tests require CGO; they fail when built with `CGO_ENABLED=0`.
- Some Windows test failures are caused by path expectations and open-file deletion behavior.

See [Troubleshooting](docs/troubleshooting.md) for the latest verification notes.

## Documentation

- [Architecture](docs/architecture.md)
- [Development](docs/development.md)
- [Build and Release](docs/build-and-release.md)
- [Packaging](docs/packaging.md)
- [WebClients Analysis](docs/webclients-analysis.md)
- [Multi-Agent Coordination](docs/multi-agent-coordination.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Contributing](CONTRIBUTING.md)

## Repository Layout

```text
.
|-- cmd/protondrive/           planned CLI/application entrypoint
|-- internal/client/           Proton API bridge, session, keyring, file operation layer
|-- internal/config/           config loading, XDG paths, capability/profile detection
|-- internal/encryption/       AES-GCM helpers, cache encryption, SQLCipher helpers
|-- internal/errors/           safe error types, user messages, retry policy
|-- internal/profile/          profile detection wrapper
|-- internal/storage/          SQLite/SQLCipher state database and file metadata models
|-- internal/testutil/         test helpers and mocks
|-- tests/security/            security-focused tests
|-- docs/phases/               development phase plans and status notes
|-- scripts/                   helper scripts
|-- go.mod                     Go module definition
`-- main.go                    temporary capability/profile demo entrypoint
```

`WebClients/` is not part of this Go application. It may be cloned locally for analysis of Proton's upstream Drive, Account, and Verify web apps, but it should not be committed to this repository.

## Intended Direction

The Go branch appears to target:

- Proton Drive API access through `github.com/henrybear327/Proton-API-Bridge`.
- Local configuration under XDG-compatible paths.
- OS keyring-backed session key storage.
- Encrypted session persistence.
- Encrypted file cache.
- SQLCipher-backed sync metadata storage.
- Hardware-aware performance profiles.
- Eventually, a Linux GUI and sync engine.

The phase documents under `docs/phases/` describe a broader roadmap. Some phase content still references older assumptions and should be treated as planning material, not verified implementation truth.

## Quick Start For Development

Install Go 1.24.x with CGO support.

Clone:

```bash
git clone https://github.com/DonnieDice/protondrive-linux.git
cd protondrive-linux
git switch dev
```

Run verification:

```bash
go build ./...
go test ./...
```

Expect failures until the current blockers are fixed.

## WebClients Analysis

Proton's upstream WebClients repository is useful as a reference for how Proton Drive handles browser-side authentication, Drive bootstrap, download mechanisms, human verification, and crypto worker fallback.

Clone it locally when needed:

```bash
git clone --depth=1 --single-branch --branch main \
  https://github.com/ProtonMail/WebClients.git WebClients
```

Then read [docs/webclients-analysis.md](docs/webclients-analysis.md).

## License

This repository is licensed under GPL-3.0. See [LICENSE](LICENSE).
