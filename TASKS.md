# Proton Drive Linux - Workflow Fix Tasks

## Current Status
- **Local build**: ✅ WORKING (login, drive access, downloads all functional)
- **Workflow builds**: ❌ BROKEN (apps compile but show white screen/loading loop)

## Root Cause
The workflow builds the account/verify apps with wrong asset paths:
- Built with: `/assets/static/...`
- Should be: `/account/assets/static/...` and `/verify/assets/static/...`

We added sed fixes to rewrite paths after copying, but need to verify they work.

---

## Task List

### Phase 1: Set Up ACT for Local Workflow Testing
- [ ] Create proper Dockerfile for act-debian12 with all build dependencies
- [ ] Configure act to use custom image
- [ ] Verify act can start the workflow container

### Phase 2: Run Full Build in ACT
- [ ] Execute build-linux-packages.yml workflow steps in act
- [ ] Verify WebClients clones and builds successfully
- [ ] Verify account/verify apps are built
- [ ] **CRITICAL**: Verify sed path fixes are applied correctly
- [ ] Verify Tauri builds the binary with embedded assets

### Phase 3: Test ACT-Built Package
- [ ] Extract the built binary/AppImage from act container
- [ ] Run on host system (outside Docker)
- [ ] Verify login screen loads (no white screen)
- [ ] Verify can log in successfully
- [ ] Verify Drive UI loads after login
- [ ] Verify downloads work

### Phase 4: Push to GitHub
- [ ] Commit any final fixes
- [ ] Delete old v1.1.1 tag/release
- [ ] Push and create new v1.1.1 tag
- [ ] Monitor workflow completion
- [ ] Download and test workflow-built packages

---

## Key Files to Check

### Workflow Path Fixes (all 3 workflows)
```yaml
# After copying account app:
find applications/drive/dist/account -name "*.html" -exec sed -i \
  -e 's|<base href="/">|<base href="/account/">|g' \
  -e 's|href="/assets/|href="/account/assets/|g' \
  -e 's|src="/assets/|src="/account/assets/|g' \
  -e 's|content="/assets/|content="/account/assets/|g' {} \;
```

### Expected Result in account/index.html
```html
<base href="/account/">
<script src="/account/assets/static/runtime.xxx.js">
```

---

## Quick Verification Commands

```bash
# Test local build
./src-tauri/target/release/proton-drive

# Check account app paths in local dist
grep -o 'src="[^"]*"' WebClients/applications/drive/dist/account/index.html | head -5

# Run act workflow
sg docker -c "act -W .github/workflows/build-linux-packages.yml -j build-deb-rpm-appimage"
```

---

## Notes
- The issue is NOT in the Rust code or Tauri config
- The issue is that Proton's build outputs `/assets/` paths but we deploy under `/account/`
- The sed fix should work, we just need to verify it's being applied correctly in the workflow
