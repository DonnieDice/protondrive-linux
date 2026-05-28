#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 5 ]; then
  echo "usage: $0 ARTIFACT_NAME PACKAGE_TYPE DISTRO ARCH FILE_GLOB [FILE_GLOB ...]" >&2
  exit 2
fi

ARTIFACT_NAME="$1"
PACKAGE_TYPE="$2"
DISTRO="$3"
ARCH="$4"
shift 4

if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: node is required to write artifact manifests" >&2
  exit 1
fi

FILES=()
for pattern in "$@"; do
  if [ -f "$pattern" ]; then
    FILES+=("$pattern")
    continue
  fi

  while IFS= read -r file; do
    [ -f "$file" ] && FILES+=("$file")
  done < <(compgen -G "$pattern" || true)
done

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "ERROR: no files matched manifest inputs: $*" >&2
  exit 1
fi

node - "$ARTIFACT_NAME" "$PACKAGE_TYPE" "$DISTRO" "$ARCH" "${ARTIFACT_MANIFEST_DIR:-artifact-metadata}" "${FILES[@]}" <<'JS'
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const [artifactName, packageType, distro, arch, outputDir, ...files] = process.argv.slice(2);

function sha256File(filePath) {
  const digest = crypto.createHash("sha256");
  const buffer = Buffer.alloc(1024 * 1024);
  const fd = fs.openSync(filePath, "r");
  try {
    let bytesRead = 0;
    while ((bytesRead = fs.readSync(fd, buffer, 0, buffer.length, null)) > 0) {
      digest.update(buffer.subarray(0, bytesRead));
    }
    return digest.digest("hex");
  } finally {
    fs.closeSync(fd);
  }
}

function readJson(filePath) {
  if (!filePath || !fs.existsSync(filePath)) {
    return {};
  }
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function readVersion() {
  if (process.env.VERSION) {
    return process.env.VERSION;
  }
  return readJson("package.json").version || "";
}

const event = readJson(process.env.GITHUB_EVENT_PATH);
const pullRequest = event.pull_request || {};
const prNumber = pullRequest.number ?? (process.env.GITHUB_EVENT_NAME === "pull_request" ? event.number ?? null : null);
const repository = process.env.GITHUB_REPOSITORY || "";
const runId = process.env.GITHUB_RUN_ID || "";
const serverUrl = process.env.GITHUB_SERVER_URL || "https://github.com";

const fileEntries = files
  .sort()
  .map((filePath) => ({
    name: path.basename(filePath),
    size_bytes: fs.statSync(filePath).size,
    sha256: sha256File(filePath),
  }));

const manifest = {
  arch,
  artifact_name: artifactName,
  distro,
  files: fileEntries,
  generated_at: new Date().toISOString(),
  github: {
    event_name: process.env.GITHUB_EVENT_NAME || "",
    job: process.env.GITHUB_JOB || "",
    run_attempt: process.env.GITHUB_RUN_ATTEMPT || "",
    run_id: runId,
    run_url: repository && runId ? `${serverUrl}/${repository}/actions/runs/${runId}` : "",
    workflow: process.env.GITHUB_WORKFLOW || "",
  },
  package_type: packageType,
  schema_version: 1,
  signing_status: process.env.SIGNING_STATUS || "unsigned",
  source: {
    branch: process.env.GITHUB_HEAD_REF || process.env.GITHUB_REF_NAME || "",
    commit_sha: process.env.GITHUB_SHA || "",
    pr_number: prNumber,
    ref: process.env.GITHUB_REF || "",
    ref_name: process.env.GITHUB_REF_NAME || "",
    repository,
  },
  test_status: process.env.TEST_STATUS || "built_not_runtime_tested",
  version: readVersion(),
};

fs.mkdirSync(outputDir, { recursive: true });

const manifestPath = path.join(outputDir, `${artifactName}.manifest.json`);
fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

const checksumPath = path.join(outputDir, `${artifactName}.sha256`);
fs.writeFileSync(
  checksumPath,
  `${fileEntries.map((entry) => `${entry.sha256}  ${entry.name}`).join("\n")}\n`,
);

console.log(`Wrote ${manifestPath}`);
console.log(`Wrote ${checksumPath}`);
JS
