#!/bin/bash
# Download build artifacts from the latest successful pipeline on this branch.
#
# Called by transfer jobs when the upstream build was skipped (no source changes
# since last build). Lets transfer/install/vmtest still run against the last
# known-good artifact so CI-only changes get fully tested without a rebuild.
#
# Requires CI_JOB_TOKEN, CI_API_V4_URL, CI_PROJECT_ID, CI_COMMIT_REF_NAME.
# Usage: fetch-latest-artifact.sh <job-name> [out-dir]

set -e

JOB_NAME="${1:?Usage: fetch-latest-artifact.sh <job-name>}"
OUT_DIR="${2:-artifacts}"

if [ -d "$OUT_DIR" ] && [ -n "$(ls -A "$OUT_DIR" 2>/dev/null)" ]; then
    echo "[fetch-artifact] artifacts/ already present -- fresh build, skipping fetch"
    exit 0
fi

API="${CI_API_V4_URL:?CI_API_V4_URL not set}"
PROJECT="${CI_PROJECT_ID:?CI_PROJECT_ID not set}"
REF="${CI_COMMIT_REF_NAME:?CI_COMMIT_REF_NAME not set}"
TOKEN="${CI_JOB_TOKEN:?CI_JOB_TOKEN not set}"

echo "[fetch-artifact] Build was skipped (no source change). Fetching '$JOB_NAME' artifact from last successful pipeline on '$REF'..."

HTTP_STATUS=$(curl -sS -o /tmp/artifact.zip -w "%{http_code}" \
    -H "JOB-TOKEN: $TOKEN" \
    "$API/projects/$PROJECT/jobs/artifacts/$REF/download" \
    -G --data-urlencode "job=$JOB_NAME")

if [ "$HTTP_STATUS" = "404" ]; then
    echo "[fetch-artifact] ERROR: No artifact found for '$JOB_NAME' on ref '$REF'."
    echo "  This usually means the source has never been built on this branch."
    echo "  Touch a source file or trigger the build manually to create an initial artifact."
    exit 1
elif [ "$HTTP_STATUS" != "200" ]; then
    echo "[fetch-artifact] ERROR: API returned HTTP $HTTP_STATUS for '$JOB_NAME'."
    exit 1
fi

unzip -o /tmp/artifact.zip -d . >/dev/null
rm -f /tmp/artifact.zip

if [ -z "$(ls -A "$OUT_DIR" 2>/dev/null)" ]; then
    echo "[fetch-artifact] ERROR: zip extracted but '$OUT_DIR/' is still empty."
    exit 1
fi

echo "[fetch-artifact] Restored $(ls "$OUT_DIR"/ | wc -l) file(s) from last successful build:"
ls -lh "$OUT_DIR"/
