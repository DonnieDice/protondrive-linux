# CI/CD Roadmap

This roadmap separates checks by what they can prove, how much infrastructure
they require, and whether they should block releases.

## Stage 0: Artifact Traceability

Status: started in PR #102.

Goal: make every build artifact self-describing before adding new test
infrastructure.

What this proves:

- Which commit produced an artifact
- Which PR/run/job produced an artifact
- Which package type, distro, arch, and version the artifact targets
- Which checksum belongs to each file

What this does not prove:

- The package installs
- The GUI opens
- Login or 2FA works

Gate recommendation: required once stable.

## Stage 1: Unit Tests

Goal: test isolated logic that does not need a desktop session, WebKit, a
network login, or system package installation.

Good candidates:

- URL routing helpers
- cookie/session persistence helpers
- auth state parsing
- storage path selection
- package metadata helper scripts
- small JS/Rust utility functions

What this proves:

- Deterministic helper logic behaves as expected
- Regressions are caught before package builds start

What this does not prove:

- WebView rendering
- desktop integration
- login/2FA behavior against Proton

Gate recommendation: required for touched helper code.

## Stage 2: Debug Markers

Goal: add structured logs around startup, WebView creation, navigation,
auth handoff, cookie persistence, and 2FA transitions.

What this proves:

- The app reached specific internal checkpoints
- session/auth hooks ran
- a tester can identify where login stopped

What this does not prove:

- a real window was visible
- WebKit rendered content
- user input worked
- 2FA was actually usable

Gate recommendation: required for login/session changes once enough markers
exist.

## Stage 3: Mini-Compositor GUI Smoke Test

Goal: run the app under a lightweight CI display stack such as `xvfb`,
`weston`, or `xvfb + openbox` and verify that the process creates a window
without crashing.

What this proves:

- the app can start in a CI desktop-like environment
- Tauri/WebKit can create a GUI surface
- obvious blank-start or crash-on-open failures are caught

What this does not prove:

- distro-specific package install behavior
- login success
- 2FA success
- keyring and desktop-session behavior in a real user VM

Gate recommendation: start non-blocking, then make required after flake rate is
known.

## Stage 4: Package Install Smoke Tests

Goal: install built artifacts into matching distro environments and run basic
post-install checks.

Likely targets:

- DEB on Ubuntu/Debian
- RPM on Fedora/EL/openSUSE
- APK on Alpine
- AUR package on Arch
- AppImage launch check
- Flatpak install check
- Snap install check, excluding known store publish issues

What this proves:

- package dependencies are installable
- desktop files/icons are present
- package managers accept the artifact
- basic app launch still works after packaging

What this does not prove:

- real login/2FA success
- complete desktop integration
- long-running sync behavior

Gate recommendation: non-blocking at first, then required per package family
after the scripts stabilize.

## Stage 5: VM Login And 2FA Acceptance Tests

Goal: test the real user workflow in persistent or provisioned virtual
machines with a real desktop session.

Required infrastructure:

- VM per priority distro or distro family
- desktop session and compositor
- WebKitGTK runtime
- keyring/secret-service
- network access
- test Proton account
- controlled 2FA flow, likely TOTP via CI secret
- screenshot, video, and app log capture

What this proves:

- the app can open in a real desktop environment
- login page is usable
- 2FA can be completed
- authenticated state persists after the handoff

What this does not prove:

- every user account state
- every distro variant
- every store-specific publish path

Gate recommendation: manual or scheduled at first. Make it a release candidate
gate only after the VM jobs are reliable and the account/2FA process is
controlled.

## Priority Order

1. Artifact traceability
2. Unit tests for isolated helpers
3. Debug markers for login/session routing
4. mini-compositor GUI smoke test
5. package install smoke tests
6. VM login and 2FA acceptance tests

## Release Policy Direction

Until VM login/2FA testing exists, release confidence should come from:

- successful package builds
- artifact manifests and checksums
- helper-level unit tests
- targeted manual testing of priority artifacts
- clear debug logs when login/session behavior fails

Do not treat container-only tests as proof that login and 2FA work. Login and
2FA are end-to-end acceptance tests and need a real desktop-like environment.
