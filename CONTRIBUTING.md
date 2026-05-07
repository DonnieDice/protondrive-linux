# Contributing

Thanks for helping improve ProtonDrive Linux. The current `dev` branch is a Go-native client foundation, so contributions should keep implementation status, tests, and documentation aligned.

## Project Ground Rules

- Treat `go build ./...` and `go test ./...` as the source of truth for current status.
- Separate implemented behavior from planned behavior.
- Keep security claims precise and tied to code that exists.
- Do not commit local `WebClients/` checkouts.
- Use WebClients only as upstream reference material unless the architecture explicitly changes.
- Keep branch scopes narrow when multiple people or agents are working at once.

## Local Setup

```bash
git clone https://github.com/DonnieDice/protondrive-linux.git
cd protondrive-linux
git switch dev
go mod download
```

Run verification:

```bash
go build ./...
go test ./...
```

Current `dev` is expected to fail until active blockers are fixed. Include the relevant failure output or summary in your PR.

## Repository Areas

Entrypoints:

```text
main.go
cmd/protondrive/
```

Core implementation:

```text
internal/client/
internal/config/
internal/encryption/
internal/errors/
internal/profile/
internal/storage/
internal/testutil/
```

Tests:

```text
tests/security/
internal/**/*_test.go
```

Planning and documentation:

```text
README.md
TASKS.md
docs/
```

Scripts and automation:

```text
scripts/
.github/
```

## Development Workflow

1. Create a focused branch from `dev`.
2. Make the smallest change that moves the current branch toward build/test correctness.
3. Update docs when behavior, status, commands, or constraints change.
4. Run focused verification.
5. Include verification results in the PR.

Example:

```bash
git switch -c fix/module-imports origin/dev
go test ./...
```

## Common Workstreams

Build correctness:

- remove stale `github.com/yourusername/...` imports.
- implement or remove empty entrypoints.
- fix malformed imports.
- keep `go.mod` module path aligned with source imports.

Security/local state:

- review key derivation and session persistence.
- keep sensitive data out of logs and config.
- verify encryption tests with CGO where SQLite/SQLCipher is involved.

WebClients analysis:

- clone upstream locally when needed.
- document findings under `docs/webclients-analysis.md`.
- do not commit the upstream checkout.

## WebClients Reference Checkout

Optional local analysis checkout:

```bash
git clone --depth=1 --single-branch --branch main \
  https://github.com/ProtonMail/WebClients.git WebClients
```

Before committing, confirm `WebClients/` is not staged:

```bash
git status --short
```

## Pull Request Checklist

- The branch is based on `dev`.
- The changed files match the branch purpose.
- Build/test status is reported honestly.
- Documentation is updated for changed behavior.
- Security-sensitive changes describe residual risk.
- No local upstream checkout or generated dependency tree is committed.

## Useful References

- [Architecture](docs/architecture.md)
- [Development](docs/development.md)
- [Build and Release](docs/build-and-release.md)
- [Packaging](docs/packaging.md)
- [WebClients Analysis](docs/webclients-analysis.md)
- [Multi-Agent Coordination](docs/multi-agent-coordination.md)
- [Troubleshooting](docs/troubleshooting.md)
