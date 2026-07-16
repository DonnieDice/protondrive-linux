#!/bin/sh
# Content-addressed package artifact reuse for GitLab build jobs.
#
# Usage:
#   sh build-artifact-cache.sh restore
#   sh build-artifact-cache.sh publish
#
# `restore` returns 0 only when a verified artifact was restored. Build jobs use
# that result to exit before installing their distro toolchain. `publish` is
# best-effort and is intended for the shared build template's after_script.

set -eu

CACHE_PACKAGE_NAME="${BUILD_ARTIFACT_CACHE_PACKAGE:-proton-drive-build-cache}"
CACHE_ARCHIVE_NAME="artifact-cache.tar.gz"
CACHE_WORK_DIR="${BUILD_ARTIFACT_CACHE_WORK_DIR:-${CI_PROJECT_DIR:-.}/.build-artifact-cache}"
CACHE_KEY_FILE="${CACHE_WORK_DIR}/build-key"
CACHE_HIT_FILE="${CACHE_WORK_DIR}/hit"
ARTIFACT_DIR="${BUILD_ARTIFACT_DIR:-artifacts}"

log() {
  printf '%s\n' "[build-cache] $*"
}

is_true() {
  case "${1:-}" in
    1 | true | TRUE | yes | YES | on | ON) return 0 ;;
    *) return 1 ;;
  esac
}

ensure_tools() {
  missing=""
  for tool in bash curl git sha256sum tar; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
  done
  [ -z "$missing" ] && return 0

  log "installing lightweight cache client tools:$missing"
  if command -v apk >/dev/null 2>&1; then
    apk add --no-cache bash curl git coreutils tar gzip
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bash ca-certificates curl git coreutils tar gzip
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm --needed bash ca-certificates curl git coreutils tar gzip
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y bash ca-certificates curl git coreutils tar gzip
  elif command -v microdnf >/dev/null 2>&1; then
    microdnf install -y bash ca-certificates curl git coreutils tar gzip
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install bash ca-certificates curl git coreutils tar gzip
  else
    log "WARNING: cannot install required tools:$missing"
    return 1
  fi
}

resolve_build_identity() {
  BUILD_PACKAGE_TYPE="${BUILD_PACKAGE_TYPE:-}"
  BUILD_TARGET_LABEL="${BUILD_TARGET_LABEL:-}"

  if [ -z "$BUILD_PACKAGE_TYPE" ] || [ -z "$BUILD_TARGET_LABEL" ]; then
    case "${CI_JOB_NAME:-}" in
      build:apk:*)
        BUILD_PACKAGE_TYPE=apk
        BUILD_TARGET_LABEL="${DISTRO_PATCH:-}"
        ;;
      build:appimage)
        BUILD_PACKAGE_TYPE=appimage
        BUILD_TARGET_LABEL="${APPIMAGE_TARGET:-linux-baseline}"
        ;;
      build:aur)
        BUILD_PACKAGE_TYPE=aur
        BUILD_TARGET_LABEL="${DISTRO_PATCH:-arch-native}"
        ;;
      build:deb:*)
        BUILD_PACKAGE_TYPE=deb
        BUILD_TARGET_LABEL="${DISTRO_PATCH:-}"
        ;;
      build:flatpak:*)
        BUILD_PACKAGE_TYPE=flatpak
        BUILD_TARGET_LABEL="${DISTRO_PATCH:-${FLATPAK_TARGET:-}}"
        ;;
      build:rpm:*)
        BUILD_PACKAGE_TYPE=rpm
        BUILD_TARGET_LABEL="${DISTRO_PATCH:-}"
        ;;
      build:snap:*)
        BUILD_PACKAGE_TYPE=snap
        BUILD_TARGET_LABEL="${DISTRO_PATCH:-${SNAP_BASE:-}}"
        ;;
    esac
  fi

  if [ -z "$BUILD_PACKAGE_TYPE" ] || [ -z "$BUILD_TARGET_LABEL" ]; then
    log "WARNING: no artifact-cache identity for job '${CI_JOB_NAME:-unknown}'"
    return 1
  fi
  export BUILD_PACKAGE_TYPE BUILD_TARGET_LABEL
}

resolve_build_key() {
  mkdir -p "$CACHE_WORK_DIR"
  if [ -n "${BUILD_KEY:-}" ]; then
    printf '%s\n' "$BUILD_KEY" >"$CACHE_KEY_FILE"
    return 0
  fi
  if [ -s "$CACHE_KEY_FILE" ]; then
    BUILD_KEY="$(cat "$CACHE_KEY_FILE")"
    export BUILD_KEY
    return 0
  fi

  resolve_build_identity || return 1
  BUILD_KEY="$(bash scripts/ci/lib/compute-build-key.sh \
    "$BUILD_PACKAGE_TYPE" "$BUILD_TARGET_LABEL")"
  export BUILD_KEY
  printf '%s\n' "$BUILD_KEY" >"$CACHE_KEY_FILE"
}

cache_url() {
  printf '%s/projects/%s/packages/generic/%s/%s/%s' \
    "${CI_API_V4_URL:?CI_API_V4_URL not set}" \
    "${CI_PROJECT_ID:?CI_PROJECT_ID not set}" \
    "$CACHE_PACKAGE_NAME" "$BUILD_KEY" "$CACHE_ARCHIVE_NAME"
}

restore_cache() {
  if ! is_true "${REUSE_BUILD_ARTIFACTS:-true}"; then
    log "reuse disabled by REUSE_BUILD_ARTIFACTS"
    return 1
  fi
  if is_true "${FORCE_REBUILD:-false}"; then
    log "reuse bypassed by FORCE_REBUILD"
    return 1
  fi
  if [ -d "$ARTIFACT_DIR" ] && [ -n "$(ls -A "$ARTIFACT_DIR" 2>/dev/null)" ]; then
    log "artifacts already supplied by an upstream job"
    return 0
  fi

  ensure_tools || return 1
  resolve_build_key || return 1
  TOKEN="${CI_JOB_TOKEN:?CI_JOB_TOKEN not set}"
  URL="$(cache_url)"
  ARCHIVE="${CACHE_WORK_DIR}/${CACHE_ARCHIVE_NAME}"
  RESTORE_DIR="${CACHE_WORK_DIR}/restore"
  rm -rf "$RESTORE_DIR"
  mkdir -p "$RESTORE_DIR"

  HTTP_STATUS="$(curl --location --silent --show-error \
    --output "$ARCHIVE" --write-out '%{http_code}' \
    --header "JOB-TOKEN: $TOKEN" "$URL")" || {
    log "WARNING: cache lookup failed; continuing with a fresh build"
    return 1
  }

  case "$HTTP_STATUS" in
    200) ;;
    404)
      log "miss: $BUILD_KEY"
      rm -f "$ARCHIVE"
      return 1
      ;;
    *)
      log "WARNING: cache lookup returned HTTP $HTTP_STATUS; continuing with a fresh build"
      rm -f "$ARCHIVE"
      return 1
      ;;
  esac

  if ! tar -xzf "$ARCHIVE" -C "$RESTORE_DIR"; then
    log "WARNING: cached archive is unreadable; continuing with a fresh build"
    return 1
  fi
  if [ ! -s "$RESTORE_DIR/.artifact-cache/build-key" ] ||
    [ "$(cat "$RESTORE_DIR/.artifact-cache/build-key")" != "$BUILD_KEY" ]; then
    log "WARNING: cached artifact build key does not match $BUILD_KEY"
    return 1
  fi
  if [ ! -s "$RESTORE_DIR/.artifact-cache/SHA256SUMS" ] ||
    ! (cd "$RESTORE_DIR" && sha256sum -c .artifact-cache/SHA256SUMS >/dev/null); then
    log "WARNING: cached artifact checksum verification failed"
    return 1
  fi
  if [ ! -d "$RESTORE_DIR/artifacts" ] ||
    [ -z "$(ls -A "$RESTORE_DIR/artifacts" 2>/dev/null)" ]; then
    log "WARNING: cached archive contains no build artifacts"
    return 1
  fi

  rm -rf "$ARTIFACT_DIR"
  mv "$RESTORE_DIR/artifacts" "$ARTIFACT_DIR"
  : >"$CACHE_HIT_FILE"
  log "hit: restored verified artifacts for $BUILD_KEY"
  ls -lh "$ARTIFACT_DIR"/
  return 0
}

write_metadata() {
  stage_dir="$1"
  metadata_dir="$stage_dir/.artifact-cache"
  mkdir -p "$metadata_dir"
  printf '%s\n' "$BUILD_KEY" >"$metadata_dir/build-key"
  printf '%s\n' "${CI_COMMIT_SHA:-unknown}" >"$metadata_dir/source-commit"
  printf '%s\n' "${CI_PIPELINE_ID:-unknown}" >"$metadata_dir/source-pipeline"

  (cd "$stage_dir" &&
    find artifacts -type f -exec sha256sum '{}' \; | LC_ALL=C sort \
      >.artifact-cache/SHA256SUMS)

  if command -v node >/dev/null 2>&1; then
    artifact_name="${CI_JOB_NAME_SLUG:-$BUILD_PACKAGE_TYPE-$BUILD_TARGET_LABEL}"
    ARTIFACT_MANIFEST_DIR="$metadata_dir" \
      BUILD_KEY="$BUILD_KEY" \
      bash scripts/ci/lib/write-artifact-manifest.sh \
      "$artifact_name" "$BUILD_PACKAGE_TYPE" "$BUILD_TARGET_LABEL" \
      "${BUILD_ARCH:-amd64}" "$stage_dir/artifacts/*"
  fi
}

publish_cache() {
  if [ "${CI_JOB_STATUS:-success}" != success ]; then
    log "job status is ${CI_JOB_STATUS:-unknown}; refusing to publish partial artifacts"
    return 0
  fi
  if [ -f "$CACHE_HIT_FILE" ]; then
    log "verified cache hit; no upload needed"
    return 0
  fi
  if ! is_true "${REUSE_BUILD_ARTIFACTS:-true}"; then
    return 0
  fi
  if [ ! -d "$ARTIFACT_DIR" ] || [ -z "$(ls -A "$ARTIFACT_DIR" 2>/dev/null)" ]; then
    log "no completed artifacts to publish"
    return 0
  fi

  ensure_tools || return 0
  resolve_build_identity || return 0
  resolve_build_key || return 0
  TOKEN="${CI_JOB_TOKEN:-}"
  if [ -z "$TOKEN" ]; then
    log "WARNING: CI_JOB_TOKEN is unavailable; skipping cache upload"
    return 0
  fi

  STAGE_DIR="${CACHE_WORK_DIR}/publish"
  ARCHIVE="${CACHE_WORK_DIR}/${CACHE_ARCHIVE_NAME}"
  RESPONSE="${CACHE_WORK_DIR}/upload-response"
  rm -rf "$STAGE_DIR"
  mkdir -p "$STAGE_DIR/artifacts"
  cp -a "$ARTIFACT_DIR"/. "$STAGE_DIR/artifacts/"
  write_metadata "$STAGE_DIR"
  tar -czf "$ARCHIVE" -C "$STAGE_DIR" .

  HTTP_STATUS="$(curl --silent --show-error --output "$RESPONSE" \
    --write-out '%{http_code}' --header "JOB-TOKEN: $TOKEN" \
    --upload-file "$ARCHIVE" "$(cache_url)")" || {
    log "WARNING: cache upload failed"
    return 0
  }
  case "$HTTP_STATUS" in
    200 | 201)
      log "published $BUILD_KEY ($(du -h "$ARCHIVE" | awk '{print $1}'))"
      ;;
    409)
      log "cache entry already exists for $BUILD_KEY"
      ;;
    *)
      log "WARNING: cache upload returned HTTP $HTTP_STATUS"
      ;;
  esac
}

case "${1:-}" in
  restore) restore_cache ;;
  publish) publish_cache ;;
  *)
    echo "usage: $0 {restore|publish}" >&2
    exit 2
    ;;
esac
