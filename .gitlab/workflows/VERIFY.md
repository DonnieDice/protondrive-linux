# `verify` stage — install + smoke-test on real VMs

After the `build` stage produces a native package per distro, the `verify`
stage installs each package on a matching virtual machine and confirms the
`proton-drive` binary actually runs. This catches packaging/runtime breakage
(missing deps, bad paths, ABI mismatches) that a build-only pipeline misses.

## Pipeline flow

```
test → build → verify → spec → release → publish
                  │
                  ├── verify:alpine-3.20   → alpine320  (192.168.1.157)  apk tarball
                  ├── verify:alpine-3.22   → alpine322  (192.168.1.126)  apk tarball
                  ├── verify:debian-12     → debian12   (192.168.1.162)  .deb
                  ├── verify:debian-13     → debian13   (192.168.1.120)  .deb
                  ├── verify:ubuntu-24.04  → ubuntu2404 (192.168.1.219)  .deb
                  ├── verify:ubuntu-26.04  → ubuntu2604 (192.168.1.168)  .deb
                  ├── verify:rpm-el10      → el10       (192.168.1.123)  .rpm (dnf)
                  ├── verify:rpm-fedora-43 → fedora43   (192.168.1.183)  .rpm (dnf)
                  ├── verify:rpm-opensuse… → opensuse-tw (192.168.1.245) .rpm (zypper)
                  └── verify:aur           → arch       (192.168.1.128)  pacman -U
```

Each job `needs:` only its own build job, so they fan out in parallel as soon
as their package is ready. Failures are surfaced per-distro.

The build matrix has two packages with no dedicated VM yet (alpine-3.23,
fedora-44) and the universal bundles (appimage/flatpak/snap) are not VM-verified
here — add a file under `.gitlab/workflows/verify/` if/when target VMs exist.

## How a job works

`scripts/ci/deploy-and-test-vm.sh <DISTRO_KEY>`:
1. Resolves `DISTRO_KEY` → `IP | package-glob | package-family`.
2. Finds the package in `artifacts/` (the build job's output).
3. `scp`s it to the VM and installs with the native tool
   (apk tarball-extract / `apt-get install` / `dnf` / `zypper` / `pacman -U`).
4. Smoke test: locates the installed `proton-drive`, runs `--version`/`--help`
   under `xvfb-run` if present (it's a GUI/Tauri app), prints `SMOKE_TEST_PASS`.

## One-time setup

**CI/CD variable** (GitLab → project → Settings → CI/CD → Variables):

| Variable | Type | Value |
|---|---|---|
| `VM_SSH_KEY` | **File** | private key whose public half is in each VM's `/root/.ssh/authorized_keys` |
| `VM_SSH_USER` | Variable | optional; defaults to `root` |

The deploy keypair already exists on the Unraid host (tower) at
`/root/pd-ci-deploy` (private) / `/root/pd-ci-deploy.pub` (public). The public
key has been added to all 10 VMs. Paste the **contents of
`/root/pd-ci-deploy`** into the `VM_SSH_KEY` file variable.

> Treat `VM_SSH_KEY` as protected/masked. Rotate by regenerating the keypair on
> tower and re-running the inject step (see git history of this stage).

## Runner requirements

- The job container must reach the `192.168.1.0/24` VM subnet. The shared
  `gitlab-runner` on tower (docker executor) does, via the host's routing.
- Jobs are **untagged** and run on the default runner. If your runner only
  accepts tagged jobs, add a matching `tags:` entry to `.verify:base` in
  `deploy.yml`.

## Local manual run

```bash
export VM_SSH_KEY=/path/to/pd-ci-deploy   # or inline contents
# build first so artifacts/ is populated, then:
bash scripts/ci/deploy-and-test-vm.sh debian12
```
