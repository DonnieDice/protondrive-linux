#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: compute-build-key.sh PACKAGE_TYPE TARGET_LABEL [PATHSPEC ...]

Computes a deterministic content-addressed key for a package build. The key is
based on tracked Git blob IDs/modes plus build-affecting environment values.

Examples:
  compute-build-key.sh deb debian.12
  compute-build-key.sh rpm fedora.43 src src-tauri Cargo.lock

Environment values included when present:
  WEBCLIENTS_COMMIT WEBCLIENTS_REF RUST_VERSION RUSTFLAGS CARGO_BUILD_JOBS
  NODE_OPTIONS TARGET_TRIPLE DISTRO_TYPE DISTRO_PATCH APPIMAGE_TARGET
  FLATPAK_TARGET SNAP_BASE CI_RUNNER_EXECUTABLE_ARCH
EOF
}

if [ "$#" -lt 2 ]; then
  usage
  exit 2
fi

PACKAGE_TYPE="$1"
TARGET_LABEL="$2"
shift 2

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is required to compute build keys" >&2
  exit 1
fi

if ! command -v sha256sum >/dev/null 2>&1; then
  echo "ERROR: sha256sum is required to compute build keys" >&2
  exit 1
fi

# Common build inputs. Git pathspec ordering is deterministic because we sort the
# resulting index entries by path before hashing. This avoids filesystem traversal
# order differences between runners.
DEFAULT_PATHS=(
  src
  src-tauri
  package.json
  package-lock.json
  Cargo.toml
  Cargo.lock
  scripts/build-webclients.sh
  scripts/ci/lib/install-rust.sh
  scripts/ci/lib/fetch-webclients.sh
  scripts/ci/lib/compute-build-key.sh
  .gitlab/workflows/_shared.yml
  .gitlab/workflows/builds.yml
)

# Include the target-specific patch if it exists. Some package types use labels
# that are already patch names (deb/rpm/snap/flatpak/apk). AppImage uses a named
# target in patches/appimage/.
case "$PACKAGE_TYPE" in
  apk|appimage|deb|flatpak|rpm|snap)
    PATCH_PATH="patches/${PACKAGE_TYPE}/${TARGET_LABEL}.patch"
    ;;
  aur)
    PATCH_PATH="patches/aur/${TARGET_LABEL}.patch"
    ;;
  *)
    PATCH_PATH=""
    ;;
esac

PATHS=("${DEFAULT_PATHS[@]}")
if [ -n "$PATCH_PATH" ] && [ -e "$PATCH_PATH" ]; then
  PATHS+=("$PATCH_PATH")
fi

if [ "$#" -gt 0 ]; then
  PATHS+=("$@")
fi

# Keep env input list explicit. These are values known to change output or build
# behavior. Missing values are recorded as empty strings so the input stream has a
# stable shape across runners.
ENV_KEYS=(
  PACKAGE_TYPE
  TARGET_LABEL
  WEBCLIENTS_COMMIT
  WEBCLIENTS_REF
  RUST_VERSION
  RUSTFLAGS
  CARGO_BUILD_JOBS
  NODE_OPTIONS
  TARGET_TRIPLE
  DISTRO_TYPE
  DISTRO_PATCH
  APPIMAGE_TARGET
  FLATPAK_TARGET
  SNAP_BASE
  CI_RUNNER_EXECUTABLE_ARCH
)

{
  printf 'schema=proton-drive-build-key-v1\n'
  printf 'package_type=%s\n' "$PACKAGE_TYPE"
  printf 'target_label=%s\n' "$TARGET_LABEL"
  for key in "${ENV_KEYS[@]}"; do
    case "$key" in
      PACKAGE_TYPE) value="$PACKAGE_TYPE" ;;
      TARGET_LABEL) value="$TARGET_LABEL" ;;
      *) value="${!key-}" ;;
    esac
    printf 'env:%s=%s\n' "$key" "$value"
  done

  # `git ls-files -s` prints: mode object stage<TAB>path. Sorting by path keeps
  # the stream deterministic and hashes blob IDs/permissions instead of current
  # worktree file bytes.
  git ls-files -s -- "${PATHS[@]}" \
    | LC_ALL=C sort -t $'\t' -k2,2
} | sha256sum | awk -v type="$PACKAGE_TYPE" -v target="$TARGET_LABEL" '{
  safe = type "-" target
  gsub(/[^A-Za-z0-9_.-]/, "-", safe)
  print safe "-" $1
}'
