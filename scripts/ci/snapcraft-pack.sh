#!/usr/bin/env bash
# Pack a snap with the canonical snapcraft image via the host Docker socket.
#
# Why docker cp instead of `docker run -v`:
# This project's GitLab runner uses the "socket binding" pattern -- the host
# /var/run/docker.sock is bind-mounted into every job and the runner uses host
# networking. In that topology a `docker run -v <jobpath>:/project` bind mount
# resolves against the *host* filesystem, not the job container's, so a build
# context created in the job's own /tmp mounts as an empty directory
# (empirically confirmed on the runner). Running a `docker:dind` service
# instead also fails there, because the mounted host socket occupies
# /var/run/docker.sock and the dind daemon can't create its own.
#
# Streaming the context in and the packed snap out with `docker cp` copies
# through the CLI regardless of where the daemon runs, so it needs neither bind
# mounts nor a Docker-in-Docker service.
#
# Usage: snapcraft-pack.sh <build-context-dir> <output-snap-path>
#   SNAPCRAFT_IMAGE overrides the snapcraft image (default: core24 8.x).
#   SNAPCRAFT_BOOTSTRAP_VERSION builds and reuses a local Docker image with
#   that Snapcraft release. This is used for bases newer than the published
#   Canonical Snapcraft rock supports.
set -euo pipefail

BUILD_CONTEXT="${1:?build context dir required}"
OUTPUT_SNAP="${2:?output snap path required}"
SNAPCRAFT_IMAGE="${SNAPCRAFT_IMAGE:-ghcr.io/canonical/snapcraft:8_core24}"
SNAPCRAFT_BOOTSTRAP_VERSION="${SNAPCRAFT_BOOTSTRAP_VERSION:-}"
SNAPCRAFT_BOOTSTRAP_IMAGE_BASE="${SNAPCRAFT_BOOTSTRAP_IMAGE_BASE:-ubuntu:24.04}"

if [ -n "$SNAPCRAFT_BOOTSTRAP_VERSION" ]; then
  if ! docker image inspect "$SNAPCRAFT_IMAGE" >/dev/null 2>&1; then
    echo "Building reusable Snapcraft ${SNAPCRAFT_BOOTSTRAP_VERSION} image: $SNAPCRAFT_IMAGE"
    BOOTSTRAP_LOG="$(mktemp)"
    if ! docker build -q \
      --build-arg "SNAPCRAFT_BASE_IMAGE=$SNAPCRAFT_BOOTSTRAP_IMAGE_BASE" \
      --build-arg "SNAPCRAFT_VERSION=$SNAPCRAFT_BOOTSTRAP_VERSION" \
      --tag "$SNAPCRAFT_IMAGE" \
      - >"$BOOTSTRAP_LOG" 2>&1 <<'DOCKERFILE'
ARG SNAPCRAFT_BASE_IMAGE=ubuntu:24.04
FROM ${SNAPCRAFT_BASE_IMAGE}

ARG SNAPCRAFT_BASE_IMAGE
ARG SNAPCRAFT_VERSION
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/opt/snapcraft-venv/bin:$PATH

RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends \
        ca-certificates \
        git \
        python3 \
        python3-apt \
        python3-venv \
        squashfs-tools \
    && python3 -m venv --system-site-packages /opt/snapcraft-venv \
    && /opt/snapcraft-venv/bin/pip install --disable-pip-version-check --no-cache-dir --quiet \
        "git+https://github.com/canonical/snapcraft.git@${SNAPCRAFT_VERSION}" \
    && snapcraft --version \
    && rm -rf /var/lib/apt/lists/*
DOCKERFILE
    then
      cat "$BOOTSTRAP_LOG" >&2
      rm -f "$BOOTSTRAP_LOG"
      exit 1
    fi
    rm -f "$BOOTSTRAP_LOG"
  fi
fi

# Create (not run) the container so we can stream the context in before it
# starts. Output goes to a dedicated /out dir so we copy back only the snap,
# not the multi-hundred-MB destructive-mode build tree.
CID="$(docker create --entrypoint "" -w /project "$SNAPCRAFT_IMAGE" \
  sh -c 'mkdir -p /out && snapcraft pack --destructive-mode --output /out')"
trap 'docker rm -f "$CID" >/dev/null 2>&1 || true' EXIT

docker cp "$BUILD_CONTEXT/." "$CID:/project"
docker start -a "$CID"

OUT_DIR="$(mktemp -d)"
docker cp "$CID:/out/." "$OUT_DIR/"
SNAP_FILE="$(find "$OUT_DIR" -maxdepth 1 -name '*.snap' | head -1)"
[ -n "$SNAP_FILE" ] || { echo "No snap file produced by snapcraft" >&2; exit 1; }
mkdir -p "$(dirname "$OUTPUT_SNAP")"
mv "$SNAP_FILE" "$OUTPUT_SNAP"
rm -rf "$OUT_DIR"
echo "Packed snap -> $OUTPUT_SNAP"
