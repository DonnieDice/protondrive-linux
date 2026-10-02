#!/usr/bin/env bash
# Install/verify the Rust toolchain for CI jobs (test:fmt, test:clippy,
# test:rust, coverage:rust, build:*).
#
# Robust against a partially-archived cache: a job killed mid-rustup-install
# can archive a .cargo-* cache containing the rustup binary but no usable
# default toolchain (observed 2026-09-27: "rustup could not choose a version
# of rustc to run, because one wasn't specified explicitly, and no default is
# configured"). Guard every entry point so a poisoned cache self-heals
# instead of failing the release-policy jobs.
export PATH="$CARGO_HOME/bin:$PATH"

RUSTUP="$CARGO_HOME/bin/rustup"

need_install=1
if [ -x "$RUSTUP" ]; then
  if rustup show active-toolchain >/dev/null 2>&1 \
     && rustc --version >/dev/null 2>&1 && cargo --version >/dev/null 2>&1; then
    need_install=0
  else
    echo "[install-rust] cached $CARGO_HOME is missing a default toolchain; reinstalling rustup" >&2
    rm -rf "$CARGO_HOME"
  fi
fi

if [ "$need_install" = 1 ]; then
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
