# Phase 5: Distribution & Release

**Duration**: 3-5 days  
**Status**: ❌ Blocked by Phase 4  
**Dependencies**: Phase 4 (Testing & Hardening) complete  
**Unlocks**: v1.0.0 Release

---

## OVERVIEW

Package, document, and release v1.0.0.

**Entry Criteria**: 
- Phase 4 complete
- All quality gates passed
- Security audit complete
- Performance targets met

**Exit Criteria**:
- All packages built and tested
- Documentation complete
- v1.0.0 released on GitHub
- Available for download

---

## 5.1 PACKAGING

**Dependencies**: Tested binary  
**Output**: Package files for all formats  
**Estimated Time**: 1.5 days

### Tasks

- [ ] 🏗️ **Create `scripts/build-all.sh`**
  - [ ] Set version from git tag or argument
  - [ ] Cross-compile for all targets:
    ```bash
    GOOS=linux GOARCH=amd64 go build -ldflags="-s -w -X main.Version=$VERSION" -o dist/protondrive-linux-amd64
    GOOS=linux GOARCH=arm64 go build -ldflags="-s -w -X main.Version=$VERSION" -o dist/protondrive-linux-arm64
    GOOS=linux GOARCH=arm GOARM=7 go build -ldflags="-s -w -X main.Version=$VERSION" -o dist/protondrive-linux-armv7
    ```
  - [ ] Strip binaries (`-ldflags="-s -w"`)
  - [ ] Generate SHA256 checksums
  - [ ] Create `checksums.txt`

- [ ] 🏗️ **Create `.deb` package**
  - [ ] Create `packaging/debian/` directory:
    ```
    packaging/debian/
    ├── control          # Package metadata
    ├── copyright        # License info
    ├── postinst         # Post-install script
    ├── prerm            # Pre-remove script
    ├── changelog        # Debian changelog
    └── rules            # Build rules
    ```
  - [ ] `control` file:
    ```
    Package: protondrive-linux
    Version: 1.0.0
    Section: net
    Priority: optional
    Architecture: amd64
    Depends: libgtk-3-0, libayatana-appindicator3-1
    Maintainer: Your Name <email>
    Description: ProtonDrive sync client for Linux
     Secure, privacy-focused file sync with ProtonDrive.
     End-to-end encrypted, open source.
    ```
  - [ ] Build with `dpkg-deb`
  - [ ] Test installation on Ubuntu/Debian
  - [ ] Test removal
  - [ ] Verify desktop entry created
  - [ ] Verify auto-start option works

- [ ] 🏗️ **Create `.rpm` package**
  - [ ] Create `packaging/rpm/protondrive-linux.spec`:
    ```spec
    Name:           protondrive-linux
    Version:        1.0.0
    Release:        1%{?dist}
    Summary:        ProtonDrive sync client for Linux
    License:        GPLv3
    URL:            https://github.com/yourusername/protondrive-linux
    
    %description
    Secure, privacy-focused file sync with ProtonDrive.
    
    %install
    mkdir -p %{buildroot}/usr/bin
    cp protondrive-linux %{buildroot}/usr/bin/
    
    %files
    /usr/bin/protondrive-linux
    ```
  - [ ] Build with `rpmbuild`
  - [ ] Test installation on Fedora
  - [ ] Test removal
  - [ ] Verify all files installed correctly

- [ ] 🏗️ **Create Flatpak**
  - [ ] Create `packaging/flatpak/com.proton.protondrive-linux.yml`:
    ```yaml
    app-id: com.proton.protondrive-linux
    runtime: org.gnome.Platform
    runtime-version: '44'
    sdk: org.gnome.Sdk
    command: protondrive-linux
    finish-args:
      - --share=network
      - --share=ipc
      - --socket=x11
      - --socket=wayland
      - --filesystem=home
      - --talk-name=org.freedesktop.secrets
    modules:
      - name: protondrive-linux
        buildsystem: simple
        build-commands:
          - install -D protondrive-linux /app/bin/protondrive-linux
        sources:
          - type: file
            path: protondrive-linux
    ```
  - [ ] Build with `flatpak-builder`
  - [ ] Test sandboxed installation
  - [ ] Verify permissions work
  - [ ] Test keyring access in sandbox

- [ ] 🏗️ **Create AppImage**
  - [ ] Create `packaging/appimage/` structure:
    ```
    AppDir/
    ├── AppRun
    ├── protondrive-linux.desktop
    ├── protondrive-linux.png
    └── usr/
        └── bin/
            └── protondrive-linux
    ```
  - [ ] Create AppRun script
  - [ ] Include desktop entry
  - [ ] Include icon
  - [ ] Build with `appimagetool`
  - [ ] Test portable execution
  - [ ] Test on system without dependencies

- [ ] 📝 **Create `packaging/README.md`**
  - [ ] Document build process for each format
  - [ ] List dependencies
  - [ ] Troubleshooting tips

### Package Matrix

| Format | Architectures | Status | Tested |
|--------|---------------|--------|--------|
| Binary | amd64, arm64, armv7 | [ ] | [ ] |
| .deb | amd64, arm64 | [ ] | [ ] |
| .rpm | amd64, arm64 | [ ] | [ ] |
| Flatpak | amd64 | [ ] | [ ] |
| AppImage | amd64 | [ ] | [ ] |

### Acceptance Criteria
- [ ] All package formats build successfully
- [ ] All packages install correctly
- [ ] All packages uninstall cleanly
- [ ] Checksums generated for all files

---

## 5.2 CI/CD RELEASE PIPELINE

**Dependencies**: Packaging scripts  
**Output**: Automated release workflow  
**Estimated Time**: 0.5 days

### Tasks

- [ ] 🏗️ **Update `.github/workflows/ci.yml`**
  - [ ] Add release job:
    ```yaml
    release:
      runs-on: ubuntu-24.04
      if: startsWith(github.ref, 'refs/tags/v')
      needs: [test, lint, security, build]
      steps:
        - uses: actions/checkout@v4
        - uses: actions/setup-go@v5
          with:
            go-version: '1.21'
        
        - name: Build all architectures
          run: ./scripts/build-all.sh
        
        - name: Build packages
          run: |
            ./scripts/build-deb.sh
            ./scripts/build-rpm.sh
            ./scripts/build-appimage.sh
        
        - name: Create Release
          uses: softprops/action-gh-release@v1
          with:
            files: |
              dist/*
              checksums.txt
            generate_release_notes: true
    ```

- [ ] 🏗️ **Create package build scripts**
  - [ ] `scripts/build-deb.sh`
  - [ ] `scripts/build-rpm.sh`
  - [ ] `scripts/build-appimage.sh`

- [ ] 🏗️ **Configure release notes generation**
  - [ ] Use conventional commits for auto-generation
  - [ ] Or create `.github/release.yml` template

- [ ] 🧪 **Test release pipeline**
  - [ ] Create test tag `v0.0.0-test`
  - [ ] Verify pipeline triggers
  - [ ] Verify all artifacts uploaded
  - [ ] Delete test release

- [ ] 🔒 **Configure signing (optional but recommended)**
  - [ ] Set up GPG key for signing
  - [ ] Sign binaries
  - [ ] Sign checksums file
  - [ ] Document verification process

### Acceptance Criteria
- [ ] Release triggers on version tag
- [ ] All artifacts built automatically
- [ ] All artifacts uploaded to release
- [ ] Release notes generated
- [ ] Pipeline tested end-to-end

---

## 5.3 DOCUMENTATION

**Dependencies**: Feature-complete application  
**Output**: Complete documentation  
**Estimated Time**: 1 day

### Tasks

- [ ] 📝 **Complete `README.md`**
  - [ ] Project description
  - [ ] Features list
  - [ ] Screenshots/GIFs
  - [ ] Installation instructions (all methods):
    - Binary download
    - .deb package
    - .rpm package
    - Flatpak
    - AppImage
    - Build from source
  - [ ] Quick start guide
  - [ ] Configuration reference
  - [ ] Troubleshooting
  - [ ] Contributing
  - [ ] License

- [ ] 📝 **Create `docs/USER_MANUAL.md`**
  - [ ] Getting Started
    - System requirements
    - Installation
    - First run
    - Logging in
  - [ ] Using ProtonDrive Linux
    - Main interface overview
    - Browsing files
    - Uploading files
    - Downloading files
    - Sync status
  - [ ] Settings
    - General settings
    - Performance profiles
    - Appearance
    - Conflict resolution
  - [ ] System Tray
    - Tray icon
    - Menu options
    - Pause/resume sync
  - [ ] Troubleshooting
    - Common issues
    - Logs location
    - Reporting bugs
  - [ ] FAQ

- [ ] 📝 **Create `docs/INSTALL.md`**
  - [ ] System requirements:
    - Minimum: 1GB RAM, 100MB disk
    - Recommended: 4GB RAM, SSD
    - Supported: Linux kernel 4.x+
  - [ ] Binary installation
  - [ ] Package manager installation:
    - Debian/Ubuntu (apt)
    - Fedora (dnf)
    - Arch (AUR)
  - [ ] Flatpak installation
  - [ ] AppImage usage
  - [ ] Building from source:
    - Prerequisites
    - Clone and build
    - Install

- [ ] 📝 **Update `SECURITY.md`**
  - [ ] Security model overview
  - [ ] Threat model
  - [ ] Data protection:
    - At rest (encryption)
    - In transit (TLS)
    - In memory (wiping)
  - [ ] Authentication
  - [ ] Key management
  - [ ] Reporting vulnerabilities
  - [ ] Security contact

- [ ] 📝 **Create `PRIVACY.md`**
  - [ ] Data collected: None (beyond ProtonDrive sync)
  - [ ] Data stored locally:
    - Encrypted database
    - Encrypted cache
    - Non-sensitive config
  - [ ] Data NOT stored:
    - Passwords
    - Plaintext files
    - Filenames in logs
  - [ ] No telemetry
  - [ ] No analytics
  - [ ] Network connections (ProtonDrive only)

- [ ] 📝 **Create `docs/CONTRIBUTING.md`**
  - [ ] Code of conduct
  - [ ] How to contribute:
    - Bug reports
    - Feature requests
    - Pull requests
  - [ ] Development setup
  - [ ] Code style
  - [ ] Testing requirements
  - [ ] Pull request process

- [ ] 📝 **Create `docs/ARCHITECTURE.md`**
  - [ ] High-level architecture diagram
  - [ ] Component descriptions
  - [ ] Data flow
  - [ ] Security architecture

- [ ] 📝 **Update `CHANGELOG.md`**
  - [ ] Move [Unreleased] to [1.0.0]
  - [ ] Add release date
  - [ ] Ensure all changes documented
  - [ ] Follow Keep a Changelog format

### Documentation Checklist

| Document | Status | Reviewed |
|----------|--------|----------|
| README.md | [ ] | [ ] |
| USER_MANUAL.md | [ ] | [ ] |
| INSTALL.md | [ ] | [ ] |
| SECURITY.md | [ ] | [ ] |
| PRIVACY.md | [ ] | [ ] |
| CONTRIBUTING.md | [ ] | [ ] |
| ARCHITECTURE.md | [ ] | [ ] |
| CHANGELOG.md | [ ] | [ ] |

### Acceptance Criteria
- [ ] All documentation complete
- [ ] Documentation reviewed for accuracy
- [ ] No placeholder text
- [ ] Links all work
- [ ] Screenshots up to date

---

## 5.4 v1.0.0 RELEASE

**Dependencies**: Everything else in Phase 5  
**Output**: Published release  
**Estimated Time**: 0.5 days

### Tasks

- [ ] 🚀 **Pre-release checklist**
  - [ ] All Phase 4 quality gates passed
  - [ ] All packages built and tested
  - [ ] All documentation complete
  - [ ] CHANGELOG.md updated
  - [ ] Version number updated in code
  - [ ] No critical/high bugs open

- [ ] 🚀 **Final QA pass**
  - [ ] Install on clean system (VM)
  - [ ] Complete first-run flow
  - [ ] Test all major features
  - [ ] Verify documentation accuracy
  - [ ] Check all links work

- [ ] 🚀 **Create release tag**
  ```bash
  git checkout main
  git pull
  git tag -a v1.0.0 -m "Release v1.0.0"
  git push origin v1.0.0
  ```

- [ ] 🚀 **Verify CI/CD release**
  - [ ] Pipeline triggered
  - [ ] All jobs passed
  - [ ] All artifacts uploaded
  - [ ] Release created on GitHub

- [ ] 🚀 **Edit release notes**
  - [ ] Add highlights at top
  - [ ] Add installation instructions
  - [ ] Add known issues (if any)
  - [ ] Add upgrade notes (for future releases)
  - [ ] Add contributors acknowledgment

- [ ] 🚀 **Verify release assets**
  - [ ] All binaries present
  - [ ] All packages present
  - [ ] Checksums file present
  - [ ] All files downloadable

- [ ] 🚀 **Post-release announcement**
  - [ ] GitHub release announcement
  - [ ] Reddit: r/linux, r/privacy, r/ProtonMail
  - [ ] Hacker News (if appropriate)
  - [ ] Proton community forums
  - [ ] Project website (if any)
  - [ ] Social media (if any)

- [ ] 🚀 **Post-release tasks**
  - [ ] Monitor for critical bug reports
  - [ ] Respond to user feedback
  - [ ] Start planning v1.1.0

### Release Checklist

| Item | Status |
|------|--------|
| Quality gates passed | [ ] |
| Packages built | [ ] |
| Documentation complete | [ ] |
| Final QA passed | [ ] |
| Tag created | [ ] |
| CI/CD completed | [ ] |
| Release published | [ ] |
| Announcement posted | [ ] |

### Acceptance Criteria
- [ ] v1.0.0 tag created
- [ ] Release visible on GitHub
- [ ] All assets downloadable
- [ ] Release notes complete
- [ ] Announcement posted

---

## PHASE 5 EXIT CHECKLIST (PROJECT COMPLETE)

- [ ] **All packages available**
  - [ ] Binary releases for all architectures
  - [ ] .deb package
  - [ ] .rpm package
  - [ ] Flatpak
  - [ ] AppImage

- [ ] **CI/CD fully operational**
  - [ ] Automated releases work
  - [ ] All artifacts published

- [ ] **Documentation complete**
  - [ ] User documentation
  - [ ] Developer documentation
  - [ ] Security documentation

- [ ] **Release published**
  - [ ] v1.0.0 on GitHub
  - [ ] Announcement posted
  - [ ] Users can download and use

---

## POST-RELEASE: MAINTENANCE PLAN

### Regular Tasks

- [ ] Monitor GitHub issues
- [ ] Review and triage bug reports
- [ ] Review pull requests
- [ ] Update dependencies monthly
- [ ] Run security scans weekly
- [ ] Address critical bugs within 48h

### Version Planning

| Version | Focus | Timeline |
|---------|-------|----------|
| v1.0.x | Bug fixes | As needed |
| v1.1.0 | Selective sync, bandwidth limits | Q1 |
| v1.2.0 | File versioning, share links | Q2 |
| v2.0.0 | Major features TBD | Q3-Q4 |

---

**Phase 5 Estimated Completion**: 3-5 days  
**Project Status After Phase 5**: v1.0.0 RELEASED 🎉