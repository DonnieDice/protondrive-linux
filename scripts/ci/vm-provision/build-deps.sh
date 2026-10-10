#!/usr/bin/env bash
# Provision build dependencies on persistent VM test hosts.
# Runs on the GitLab runner which has SSH access to the VM subnet.
# Targets: debian13 (192.168.1.120) — the routed execution dependency
# for issue #14 / parent #3 (debian12 is issue #2's scope, non-goal here).
# Transport: VM_SSH_KEY CI variable when set, else the runner-mounted
# /root/.ssh config (see scripts/ci/lib/_vm_common.sh).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../lib/_vm_common.sh"

# VM targets from SSH config
# Issue #14 scope: debian13 only. debian12 is issue #2's scope (non-goal here).
DEBIAN13_IP="192.168.1.120"

provision_build_deps() {
  local ip="$1" label="$2"
  echo "=== Provisioning build dependencies on $label ($ip) ==="

  # Pre-flight disk cleanup: VMs accumulate apt lists and prior build caches.
  # debian13 disk was observed full ("No space left on device", pipeline 3220
  # job 30232) which aborts provisioning before reaching debian12. The 47G
  # debian13 root disk (26G used) left only ~19G free at pre-flight, which is
  # not enough headroom for the WebClients git clone + node_modules + webpack
  # build that OOM-killed the index in pipeline 3466/32000. Reclaim aggressively
  # but safely: remove apt archives/lists, doc/man stubs, journal logs,
  # npm/yarn caches, and any stale pd-deploy tree — no distro package removals,
  # no config edits.
  run_on_vm "$ip" "
    df -h /;
    du -sh /var/cache/apt /var/log/journal /tmp/pd-deploy /root/.npm /root/.cache 2>/dev/null || true;
    sudo apt-get clean 2>/dev/null || true;
    sudo rm -rf /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/* 2>/dev/null || true;
    sudo rm -rf /var/lib/apt/lists/* 2>/dev/null || true;
    sudo rm -rf /var/log/*.gz /var/log/journal/*/system@*.journal 2>/dev/null || true;
    sudo rm -rf /usr/share/doc /usr/share/man /usr/share/locale 2>/dev/null || true;
    sudo rm -rf /tmp/pd-deploy /root/.cache/yarn /root/.cache/npm /root/.npm 2>/dev/null || true;
    df -h /;
  " || {
    echo "WARN: disk cleanup pre-flight reported errors on $label (continuing)"
  }
  run_on_vm "$ip" "
    DEBIAN_FRONTEND=noninteractive apt-get update -qq &&
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q \\
      cmake libssl-dev pkg-config build-essential \\
      git curl wget file patchelf python3 ca-certificates
  " || {
    echo "FAIL: apt install failed on $label"
    return 1
  }

  # Verify installed tools
  run_on_vm "$ip" "cmake --version" || {
    echo "FAIL: cmake not working on $label"
    return 1
  }
  run_on_vm "$ip" "pkg-config --version" || {
    echo "FAIL: pkg-config not working on $label"
    return 1
  }
  run_on_vm "$ip" "gcc --version | head -1" || {
    echo "FAIL: gcc not working on $label"
    return 1
  }

  # Install rustup if not present; default toolchain stable.
  # Deploy a script to the VM instead of embedding multi-line shell in a
  # double-quoted run_on_vm argument: the runner-side expansion of
  # $HOME/$PATH inside the escaped inline form corrupted the remote PATH
  # ("curl: sh: rustup: command not found", pipeline 3858 job 37378) even
  # though apt had just installed curl. The heredoc below is transmitted
  # verbatim (single-quoted delimiter) so every expansion happens on the
  # VM with the VM's own environment — the same pattern that already works
  # for the build script in verify_protondrive_build.
  local rust_script='
    set -euo pipefail
    export PATH="$HOME/.cargo/bin:$PATH"
    if ! command -v rustup >/dev/null 2>&1; then
      curl --proto =https --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --no-modify-path
    else
      rustup default stable 2>/dev/null || rustup default stable
    fi
    export PATH="$HOME/.cargo/bin:$PATH"
    rustup show
    rustc --version
    cargo --version
  '
  run_on_vm "$ip" "mkdir -p /tmp/pd-deploy && cat > /tmp/pd-deploy/rust-install.sh <<'RUST_SCRIPT_EOF'
$rust_script
RUST_SCRIPT_EOF
chmod +x /tmp/pd-deploy/rust-install.sh && /tmp/pd-deploy/rust-install.sh" || {
    echo "FAIL: rustup install failed on $label"
    return 1
  }

  echo "=== Build dependencies provisioned on $label ==="
  return 0
}

verify_protondrive_build() {
  local ip="$1" label="$2"
  echo "=== Verifying protondrive-linux build on $label ($ip) ==="

  # Deeper pre-build disk reclaim: the VMs are small (47-48G root) and
  # previous builds left apt caches, journal logs, npm caches, and stale
  # pd-deploy trees. On debian13 a release build of the full Tauri/GTK/
  # Webkit dependency tree exhausted the 47G disk ("No space left on device",
  # pipeline 4058 job 43516: 20G free → build died mid-compilation at gtk/
  # webkit2gtk). Maximize free space: vacuum journal, autoremove, clean apt,
  # remove stale cargo caches + old pd-deploy trees, strip doc/man/locale
  # stubs. No distro package removals; safe, idempotent.
  run_on_vm "$ip" "
    sudo apt-get clean 2>/dev/null || true;
    sudo apt-get autoremove -y 2>/dev/null || true;
    sudo journalctl --vacuum-size=50M 2>/dev/null || true;
    sudo rm -rf /var/cache/apt/archives/*.deb /var/lib/apt/lists/* 2>/dev/null || true;
    sudo rm -rf /var/log/journal/*/system@*.journal /var/log/*.gz 2>/dev/null || true;
    sudo rm -rf /usr/share/doc /usr/share/man /usr/share/locale 2>/dev/null || true;
    # Remove stale cargo caches from prior build attempts (no source rebuild).
    rm -rf /root/.cargo/registry /root/.rustup/tmp 2>/dev/null || true;
    rm -rf /tmp/pd-deploy 2>/dev/null || true;
    df -h /;
  " || {
    echo "WARN: deep disk cleanup reported errors on $label (continuing)"
  }

  # Transfer the runner's own checkout (excluding WebClients and .git) instead
  # of cloning from GitLab: the project is private (anonymous clone fails) and
  # VM-side DNS has been unreliable (pipeline 1916/2099-era outages).
  local workdir=/tmp/pd-deploy/protondrive-linux
  local srcdir="${CI_PROJECT_DIR:-$(pwd)}"
  tar -C "$srcdir" --exclude='./.git' --exclude='./WebClients' -cf - . |
    run_on_vm "$ip" "rm -rf '$workdir' && mkdir -p '$workdir' && tar -C '$workdir' -xf -"

  # Write a build script to the VM rather than embedding complex shell quoting
  # in run_on_vm. The build script runs a cargo release build in src-tauri/.
  # generate_context!() in src/main.rs loads tauri.conf.json (which declares
  # frontendDist) at compile time, so cargo build FAILS when the dist directory
  # is absent — the repo's own test:rust job stubs it identically
  # (.gitlab/workflows/tests.yml). The transfer step excludes WebClients
  # (disk headroom on the 47G VMs), so build.sh creates a placeholder dist
  # here: enough to satisfy the tauri build, not a real web bundle (that npm
  # build is out of scope for issue #14).
  local build_script='
    set -euo pipefail
    export PATH="$HOME/.cargo/bin:$PATH"
    # Reduce debuginfo to minimize disk usage on the 47G VM (pipeline 4058
    # job 43516 died mid-build at gtk/webkit with "No space left on device"
    # despite 20G free; full debuginfo on ~500 crates is too large).
    export RUSTFLAGS="-C debuginfo=0"
    cd "$1/src-tauri"
    mkdir -p ../WebClients/applications/drive/dist
    echo "<!doctype html><html><body>dist placeholder for release build</body></html>" \
      > ../WebClients/applications/drive/dist/index.html
    cargo build --release
    # Cargo run from src-tauri/ puts the binary in target/release/
    BINARY=target/release/proton-drive
    [ -f "$BINARY" ] && echo "BUILD SUCCESS: $BINARY" || {
        echo "BUILD FAILED: binary not found at $BINARY"; exit 1;
    }
    sha256sum "$BINARY"
    "$BINARY" --version 2>/dev/null || echo "binary present; no --version flag"
  '

  run_on_vm "$ip" "cat > /tmp/pd-deploy/build.sh <<'BUILD_SCRIPT_EOF'
$build_script
BUILD_SCRIPT_EOF
chmod +x /tmp/pd-deploy/build.sh && /tmp/pd-deploy/build.sh /tmp/pd-deploy/protondrive-linux" || {
    echo "FAIL: protondrive-linux build failed on $label"
    return 1
  }

  echo "=== protondrive-linux builds successfully on $label ==="
  return 0
}

# Main execution
_pd_ssh_init

echo "Starting VM build dependency provisioning..."

# Issue #14 scope: debian13 only. debian12 is a non-goal ("debian12
# verification is issue #2"); provisioning both caused the whole job to exit 1
# when debian12 was unreachable, masking debian13 success.
provision_build_deps "$DEBIAN13_IP" "debian13" || exit 1

echo "debian13 provisioned with build dependencies. Verifying build..."

# Verify the release build on debian13 (issue #14 acceptance criterion).
verify_protondrive_build "$DEBIAN13_IP" "debian13" || exit 1

echo "=== debian13 BUILD DEPENDENCIES PROVISIONED AND VERIFIED ==="
