# Packaging

Packaging for the Go-based `dev` branch is not implemented yet.

## Current State

There are no verified package outputs from the current branch. Build/test correctness should land before package automation.

Current blockers:

- application entrypoint is incomplete.
- module imports are inconsistent.
- tests are not green.
- CGO requirements for SQLite/SQLCipher need a documented Linux build environment.

## Likely Runtime Dependencies

The Go binary may need:

- system keyring backend such as GNOME Keyring, KWallet, or Secret Service-compatible provider.
- SQLite/SQLCipher native dependencies if dynamically linked.
- CA certificates for HTTPS.
- desktop integration dependencies if a GUI is added.

Exact dependencies must be verified when packaging starts.

## Likely Package Targets

Potential targets:

- `.deb`
- `.rpm`
- AppImage or tarball
- AUR

Do not document public availability until artifacts are built and published.

## Packaging Inputs To Decide

Before package work starts, decide:

- binary name
- desktop entry name
- icon source
- config/data/cache paths
- systemd user service or autostart behavior, if any
- required keyring backend behavior
- whether the app is CLI-only, GUI-only, or both
- whether CGO is required in release builds

## Suggested Build Flags

For a simple binary, a future build may look like:

```bash
go build -trimpath -ldflags="-s -w" -o protondrive-linux ./cmd/protondrive
```

If version metadata is added:

```bash
go build -trimpath \
  -ldflags="-s -w -X main.version=${VERSION}" \
  -o protondrive-linux ./cmd/protondrive
```

These are suggestions until the entrypoint and version package are implemented.

## Packaging Documentation Rule

Keep packaging docs honest:

- "Implemented" means a command exists and has been tested.
- "Supported" means a release artifact exists and is installable.
- "Planned" means design intent only.
