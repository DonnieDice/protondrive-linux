#!/usr/bin/env bash
set -euo pipefail
export PATH="$CARGO_HOME/bin:$PATH"
if [ ! -f "$CARGO_HOME/bin/rustup" ]; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --default-toolchain "${RUST_VERSION:-stable}" --no-modify-path
fi
export PATH="$CARGO_HOME/bin:$PATH"
rustc --version && cargo --version
