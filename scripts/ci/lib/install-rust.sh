#!/usr/bin/env bash
export PATH="$CARGO_HOME/bin:$PATH"
if [ ! -f "$CARGO_HOME/bin/rustup" ]; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --default-toolchain "${RUST_VERSION:-stable}" --no-modify-path
else
  rustup default "${RUST_VERSION:-stable}" 2>/dev/null || rustup default stable
fi
export PATH="$CARGO_HOME/bin:$PATH"
# A cached rustup install can exist without any installed toolchain
# (pipeline 2261: "rustup could not choose a version of rustc to run").
# Ensure one is active before rustc/cargo are used.
if ! rustup show active-toolchain >/dev/null 2>&1; then
  rustup default "${RUST_VERSION:-stable}" || rustup default stable
fi
rustc --version && cargo --version
