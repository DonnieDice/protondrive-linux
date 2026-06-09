# Run the same checks CI runs, locally.  Requires: cargo, shellcheck, yamllint, jq.
# Usage: just preflight

default: preflight

preflight: fmt clippy test lint-shell lint-yaml versions

fmt:
    cargo fmt --manifest-path src-tauri/Cargo.toml -- --check

clippy:
    cargo clippy --manifest-path src-tauri/Cargo.toml --all-targets -- -D clippy::all

test:
    cargo test --manifest-path src-tauri/Cargo.toml --locked

lint-shell:
    shellcheck --severity=warning $(git ls-files '*.sh')

lint-yaml:
    yamllint -s .

versions:
    bash scripts/ci/check-versions.sh
