#!/usr/bin/env bash
# Provision build dependencies on persistent VM test hosts.
# Runs on the GitLab runner which has SSH access to the VM subnet.
# Targets: debian13 (192.168.1.120) first — the routed execution dependency
# for issue #14 / parent #3 — then debian12 (192.168.1.162).
# Transport: VM_SSH_KEY CI variable when set, else the runner-mounted
# /root/.ssh config (see scripts/ci/lib/_vm_common.sh).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../lib/_vm_common.sh"

# VM targets from SSH config
DEBIAN12_IP="192.168.1.162"
DEBIAN13_IP="192.168.1.120"

provision_build_deps() {
  local ip="$1" label="$2"
  echo "=== Provisioning build dependencies on $label ($ip) ==="

  # Update apt and install build dependencies
  run_on_vm "$ip" "
    DEBIAN_FRONTEND=noninteractive apt-get update -qq &&
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
      cmake libssl-dev pkg-config build-essential \
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

  # Install rustup if not present; default toolchain stable
  run_on_vm "$ip" "
    export PATH=\"\$HOME/.cargo/bin:\$PATH\"
    if ! command -v rustup >/dev/null 2>&1; then
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --no-modify-path
    else
      rustup default stable 2>/dev/null || rustup default stable
    fi
    export PATH=\"\$HOME/.cargo/bin:\$PATH\"
    rustup show
    rustc --version && cargo --version
  " || {
    echo "FAIL: rustup install failed on $label"
    return 1
  }

  echo "=== Build dependencies provisioned on $label ==="
  return 0
}

verify_protondrive_build() {
  local ip="$1" label="$2"
  echo "=== Verifying protondrive-linux build on $label ($ip) ==="

  # Transfer the runner's own checkout instead of cloning from GitLab on the
  # VM: the project is private (anonymous clone fails) and VM-side DNS has
  # been unreliable (pipeline 1916/2099-era outages). The runner job already
  # has the exact MR sources at CI_PROJECT_DIR.
  local workdir=/tmp/pd-deploy/protondrive-linux
  local srcdir="${CI_PROJECT_DIR:-$(pwd)}"
  tar -C "$srcdir" --exclude='./.git' --exclude='./WebClients' -cf - . |
    run_on_vm "$ip" "rm -rf '$workdir' && mkdir -p '$workdir' && tar -C '$workdir' -xf -"

  # WebClients is fetched from GitHub (public) by the repo's own pinned
  # fetch-webclients helper when not already present.
  run_on_vm "$ip" '
    set -euo pipefail
    export PATH="$HOME/.cargo/bin:$PATH"
    cd "'"$workdir"'"

    # WebClients checkout + Node.js (needed to build the web assets)
    if ! command -v node >/dev/null 2>&1; then
      curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
      DEBIAN_FRONTEND=noninteractive apt-get install -y -q nodejs
    fi
    bash scripts/build-webclients.sh

    # Install npm deps and build Rust binary
    npm ci
    cd src-tauri && cargo build --release && cd ..

    # Verify binary exists
    BINARY=src-tauri/target/release/proton-drive
    [ -f "$BINARY" ] && echo "BUILD SUCCESS: $BINARY" || { echo "BUILD FAILED: binary not found"; exit 1; }
    sha256sum "$BINARY"
    "$BINARY" --version 2>/dev/null || echo "binary present; no --version flag"
  ' || {
    echo "FAIL: protondrive-linux build failed on $label"
    return 1
  }

  echo "=== protondrive-linux builds successfully on $label ==="
  return 0
}

# Main execution
_pd_ssh_init

echo "Starting VM build dependency provisioning..."

# Provision debian13 first (issue #14 target), then debian12
provision_build_deps "$DEBIAN13_IP" "debian13" || exit 1
provision_build_deps "$DEBIAN12_IP" "debian12" || exit 1

echo "All VMs provisioned with build dependencies. Verifying builds..."

# Verify builds, debian13 first
verify_protondrive_build "$DEBIAN13_IP" "debian13" || exit 1
verify_protondrive_build "$DEBIAN12_IP" "debian12" || exit 1

echo "=== ALL VMs PROVISIONED AND VERIFIED ==="
