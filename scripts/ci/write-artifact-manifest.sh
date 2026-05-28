#!/usr/bin/env bash
# ==============================================================================
# write-artifact-manifest.sh — generate a build artifact manifest for CI
# ==============================================================================
#
# Purpose
# -------
# Scans the given output directory for built packages and writes a JSON
# manifest listing every artifact (filename, size, SHA256, MIME type).
# The manifest is consumed by release / publish steps in GitLab CI and
# GitHub Actions to verify all expected artifacts are present before
# signing or uploading.
#
# Inputs
# ------
#   $1     — ARTIFACT_DIR    Path to the directory containing built packages
#                            (e.g. target/release/, dist/packages/)
#
#   $2     — OUTPUT_FILE     Path where the JSON manifest will be written
#                            (default: "${ARTIFACT_DIR}/artifact-manifest.json")
#
# Environment
#   CI_JOB_ID    — used as the manifest's build_id (GitLab); optional
#   GITHUB_RUN_ID — used as the manifest's build_id (GitHub); optional
#
# Outputs
# -------
#   Produces a JSON file at OUTPUT_FILE with the following structure:
#
#   {
#     "build_id": "12345",
#     "created_at": "2026-05-28T08:00:00Z",
#     "artifacts": [
#       {
#         "name": "protondrive-1.2.3-x86_64.AppImage",
#         "path": "dist/protondrive-1.2.3-x86_64.AppImage",
#         "size_bytes": 12345678,
#         "sha256": "abcdef...",
#         "mime_type": "application/x-iso9660-appimage"
#       }
#     ]
#   }
#
# Usage
# -----
#   ./scripts/ci/write-artifact-manifest.sh target/release/ manifest.json
#
# Exit codes
#   0 — manifest written successfully
#   1 — ARTIFACT_DIR does not exist or is not a directory
#   2 — no artifacts found in ARTIFACT_DIR
#   3 — OUTPUT_FILE is not writable
#
# ==============================================================================

set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") ARTIFACT_DIR [OUTPUT_FILE]

Generate a JSON artifact manifest for CI publishing.

Arguments:
  ARTIFACT_DIR   Path to directory with built packages (required)
  OUTPUT_FILE    Output JSON path (default: ARTIFACT_DIR/artifact-manifest.json)
EOF
    exit 0
}

main() {
    local artifact_dir="${1:-}"
    local output_file="${2:-}"

    # --- validate arguments ---------------------------------------------------
    if [[ -z "$artifact_dir" || "$artifact_dir" == "-h" || "$artifact_dir" == "--help" ]]; then
        usage
    fi

    if [[ ! -d "$artifact_dir" ]]; then
        echo "ERROR: ARTIFACT_DIR '${artifact_dir}' does not exist or is not a directory." >&2
        exit 1
    fi

    if [[ -z "$output_file" ]]; then
        output_file="${artifact_dir}/artifact-manifest.json"
    fi

    # --- determine build_id ---------------------------------------------------
    local build_id=""
    if [[ -n "${CI_JOB_ID:-}" ]]; then
        build_id="${CI_JOB_ID}"
    elif [[ -n "${GITHUB_RUN_ID:-}" ]]; then
        build_id="${GITHUB_RUN_ID}"
    else
        build_id="local-$(date +%s)"
    fi

    # --- discover artifacts ---------------------------------------------------
    local artifacts=()
    while IFS= read -r -d '' f; do
        artifacts+=("$f")
    done < <(find "$artifact_dir" -maxdepth 2 -type f -not -name 'artifact-manifest.json' -not -name '.*' -print0)

    if [[ ${#artifacts[@]} -eq 0 ]]; then
        echo "ERROR: no artifacts found in '${artifact_dir}'." >&2
        exit 2
    fi

    # --- build JSON -----------------------------------------------------------
    local tmpfile
    tmpfile="$(mktemp)"

    echo '{' > "$tmpfile"
    echo "  \"build_id\": \"${build_id}\"," >> "$tmpfile"
    echo "  \"created_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"," >> "$tmpfile"
    echo '  "artifacts": [' >> "$tmpfile"

    local first=true
    for artifact in "${artifacts[@]}"; do
        local name size sha256 mime
        name="$(basename "$artifact")"
        size="$(stat --format='%s' "$artifact")"
        sha256="$(sha256sum "$artifact" | cut -d' ' -f1)"
        mime="$(file --brief --mime-type "$artifact")"

        if [[ "$first" == true ]]; then
            first=false
        else
            echo ',' >> "$tmpfile"
        fi

        cat >> "$tmpfile" <<<"    {"
        cat >> "$tmpfile" <<<"      \"name\": \"${name}\","
        cat >> "$tmpfile" <<<"      \"path\": \"${artifact}\","
        cat >> "$tmpfile" <<<"      \"size_bytes\": ${size},"
        cat >> "$tmpfile" <<<"      \"sha256\": \"${sha256}\","
        cat >> "$tmpfile" <<<"      \"mime_type\": \"${mime}\""
        printf '    }' >> "$tmpfile"
    done

    echo '' >> "$tmpfile"
    echo '  ]' >> "$tmpfile"
    echo '}' >> "$tmpfile"

    # --- validate & write -----------------------------------------------------
    if ! python3 -c "import json,sys; json.load(open('${tmpfile}'))" 2>/dev/null; then
        echo "ERROR: generated invalid JSON — aborting." >&2
        rm -f "$tmpfile"
        exit 3
    fi

    if ! touch "$output_file" 2>/dev/null; then
        echo "ERROR: OUTPUT_FILE '${output_file}' is not writable." >&2
        rm -f "$tmpfile"
        exit 3
    fi

    mv "$tmpfile" "$output_file"
    echo "OK: manifest written to ${output_file} (${#artifacts[@]} artifacts)" >&2
}

main "$@"
