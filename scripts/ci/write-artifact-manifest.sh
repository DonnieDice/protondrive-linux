#!/usr/bin/env bash
set -euo pipefail

# write-artifact-manifest.sh — generate an artifact manifest JSON file
# 
# Usage:
#   ARTIFACT_MANIFEST_DIR=<dir> bash scripts/ci/write-artifact-manifest.sh \
#     <name> <type> <os> <arch> [file ...]
#
# Example:
#   ARTIFACT_MANIFEST_DIR=. bash scripts/ci/write-artifact-manifest.sh \
#     aur-pkgbuild aur-metadata arch x86_64 "PKGBUILD" "AUR_SUBMISSION_GUIDE.md"

if [ $# -lt 4 ]; then
  echo "Usage: $0 <name> <type> <os> <arch> [file ...]" >&2
  exit 1
fi

NAME="$1"
TYPE="$2"
OS="$3"
ARCH="$4"
shift 4

FILES=()
for f in "$@"; do
  FILES+=("$f")
done

MANIFEST_DIR="${ARTIFACT_MANIFEST_DIR:-.}"
MANIFEST_FILE="${MANIFEST_DIR}/${NAME}.manifest.json"

cat > "${MANIFEST_FILE}" << ENDMANIFEST
{
  "name": "${NAME}",
  "type": "${TYPE}",
  "os": "${OS}",
  "arch": "${ARCH}",
  "files": $(printf '%s\n' "${FILES[@]}" | jq -R . | jq -s .),
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "commit": "${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo 'unknown')}"
}
ENDMANIFEST

echo "Artifact manifest written to ${MANIFEST_FILE}" >&2
