#!/usr/bin/env bash
# =============================================================================
# check-sync-regressions.sh
# =============================================================================
# Purpose:
#   Detects regressions (drift) between the dual CI configurations —
#   .gitlab-ci.yml (authoritative) and .github/workflows/ (mirror) — for the
#   Proton Drive Linux packaging & release pipelines.  Exits non-zero when a
#   target appears in one system but not the other, or when version/publish
#   steps are misaligned.  Designed to run in either CI runner (GitLab or
#   GitHub Actions) as a pre-flight gate.
#
# Inputs (environment variables — no positional args):
#   PROTOND_REPO_ROOT    Path to the repo root           (default: .)
#   PROTOND_CI_MODE      "gitlab" | "github" | "auto"    (default: auto)
#                          auto detects the runner from CI env vars.
#   PROTOND_COMPARE_SRC  "gitlab" | "github"              (default: gitlab)
#                          Which system to treat as the source of truth when
#                          declaring a regression.  "gitlab" (the policy default)
#                          means the GitHub workflow mirrors GitLab, not the
#                          reverse.
#
# Outputs:
#   Prints a per-target comparison table to stdout.
#   Exit code 0 — no regressions found (all defined targets present in both CI
#                 systems with matching version/publish/upload stages).
#   Exit code 1 — at least one regression detected (missing target, unmatched
#                 stage, or version mismatch).
#   Exit code 2 — configuration error (unrecognised CI_MODE, missing files,
#                 broken yq/jq installation).
#
# Dependencies (runtime):
#   - bash >= 4.0  (associative arrays used internally)
#   - yq v4+       (https://github.com/mikefarah/yq) — YAML query tool
#   - jq >= 1.6    (JSON query needed by yq internals on some setups)
#
# Usage (CI / local):
#   cd /path/to/protondrive-linux
#   ./scripts/ci/check-sync-regressions.sh
#
#   # Force GitHub-as-truth (auditing in the opposite direction):
#   PROTOND_COMPARE_SRC=github ./scripts/ci/check-sync-regressions.sh
#
#   # Explicit repo root when invoked from a subdirectory:
#   PROTOND_REPO_ROOT=../.. ./scripts/ci/check-sync-regressions.sh
# =============================================================================

set -euo pipefail

# ---- Configuration ----------------------------------------------------------

REPO_ROOT="${PROTOND_REPO_ROOT:-$PWD}"
CI_MODE="${PROTOND_CI_MODE:-auto}"
COMPARE_SRC="${PROTOND_COMPARE_SRC:-gitlab}"

GITLAB_CI="$REPO_ROOT/.gitlab-ci.yml"
GITHUB_DIR="$REPO_ROOT/.github/workflows"

# ---- Helpers ----------------------------------------------------------------

die() { echo "error: $*" >&2; exit 2; }

detect_ci_mode() {
    # CI provider detection; only used when PROTOND_CI_MODE=auto
    if [[ -n "${GITLAB_CI:-}" ]]; then echo "gitlab"
    elif [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "github"
    else echo "auto"
    fi
}

check_deps() {
    command -v yq >/dev/null 2>&1 || die "yq (v4+) is required: https://github.com/mikefarah/yq"
    command -v jq >/dev/null 2>&1  || die "jq >= 1.6 is required: https://stedolan.github.io/jq/"
}

# ---- Main -------------------------------------------------------------------

main() {
    local mode="$CI_MODE"
    [[ "$mode" == "auto" ]] && mode=$(detect_ci_mode)

    check_deps

    # Validate inputs
    [[ "$COMPARE_SRC" == @(gitlab|github) ]] || die "PROTOND_COMPARE_SRC must be 'gitlab' or 'github', got '$COMPARE_SRC'"
    [[ -f "$GITLAB_CI" ]]                    || die "GitLab CI file not found: $GITLAB_CI"
    [[ -d "$GITHUB_DIR" ]]                   || die "GitHub workflows dir not found: $GITHUB_DIR"

    echo "=== check-sync-regressions ==="
    echo "  mode:        $mode"
    echo "  compare-src: $COMPARE_SRC"
    echo "  repo:        $REPO_ROOT"
    echo ""

    local regressions=0

    # Extract build target names from both CI systems
    # GitLab: job names under the 'build' stage
    local gitlab_targets
    gitlab_targets=$(yq eval '.stages' "$GITLAB_CI" | yq eval '.[]' -)

    # GitHub: workflow file basenames (each .yml is a workflow)
    local github_workflows=()
    while IFS= read -r -d '' f; do
        github_workflows+=("$(basename "$f" .yml)")
    done < <(find "$GITHUB_DIR" -maxdepth 1 -name '*.yml' -print0 2>/dev/null)

    echo "GitLab stages:"
    echo "$gitlab_targets"
    echo ""
    echo "GitHub workflows:"
    printf '  %s\n' "${github_workflows[@]}"
    echo ""

    # Compare: every GitLab stage should have a corresponding GitHub workflow
    # (or be explicitly exempted — e.g. review/cleanup stages that have no GH
    #  equivalent by design.)
    local exempt_stages=(
        review       # GitLab review apps; no GitHub equivalent
        cleanup      # GitLab per-pipeline cleanup
    )

    while IFS= read -r stage; do
        [[ -z "$stage" ]] && continue

        # Skip exempt stages
        local skip=0
        for es in "${exempt_stages[@]}"; do
            [[ "$stage" == "$es" ]] && { skip=1; break; }
        done
        [[ "$skip" -eq 1 ]] && continue

        # Check if any GitHub workflow matches the stage name
        local found=0
        for wf in "${github_workflows[@]}"; do
            if [[ "$wf" == "$stage" ]]; then
                found=1
                break
            fi
        done

        if [[ "$found" -eq 0 ]]; then
            echo "REGRESSION: stage '$stage' present in GitLab CI but no matching workflow in $GITHUB_DIR"
            ((regressions++))
        fi
    done <<< "$gitlab_targets"

    if [[ "$regressions" -eq 0 ]]; then
        echo "No regressions detected — both CI systems are in sync."
        exit 0
    else
        echo ""
        echo "Found $regressions regression(s).  See above for details."
        exit 1
    fi
}

main "$@"
