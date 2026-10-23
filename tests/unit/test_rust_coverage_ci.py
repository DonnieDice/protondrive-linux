"""Keep cold Rust coverage budget and fail-closed reporting in the CI contract."""

import re

import yaml


def _seconds(duration):
    match = re.fullmatch(r"(\d+)([mh])", duration)
    assert match is not None, f"Unexpected CI timeout: {duration}"
    return int(match[1]) * {"m": 60, "h": 3600}[match[2]]


def test_coverage_has_native_rust_cold_start_budget(repo_root):
    root = yaml.safe_load((repo_root / ".gitlab-ci.yml").read_text(encoding="utf-8"))
    tests = yaml.safe_load(
        (repo_root / ".gitlab/workflows/tests.yml").read_text(encoding="utf-8")
    )
    # Coverage shares the cold Tauri prerequisite/build path. A shorter budget
    # kills coverage before the security stage even when native tests pass.
    # Upper bound 150m: the shared tower runner exhausted the 90m budget twice
    # on 2026-10-23 (pipelines 5499/5562) while passing its tests; 150m is the
    # documented envelope for the loaded runner (see issues #32/#34).
    coverage_budget = _seconds(root["coverage:rust"]["timeout"])
    native_budget = max(
        _seconds(tests[name]["timeout"]) for name in ("test:rust", "test:clippy")
    )
    assert native_budget <= coverage_budget <= 150 * 60


def test_coverage_remains_required_and_reports_cobertura(repo_root):
    root = yaml.safe_load((repo_root / ".gitlab-ci.yml").read_text(encoding="utf-8"))
    job = root["coverage:rust"]
    assert job["extends"] == ".rules:gate"
    assert job["stage"] == "test"
    assert job.get("allow_failure", False) is False
    gate_rules = root[".rules:gate"]["rules"]
    assert all(rule.get("allow_failure", False) is False for rule in gate_rules)
    commands = [
        command for command in job["script"] if command.startswith("cargo llvm-cov ")
    ]
    assert commands == [
        "cargo llvm-cov --manifest-path src-tauri/Cargo.toml --cobertura "
        "--output-path coverage.xml --summary-only"
    ]
    assert job["artifacts"]["when"] == "always"
    assert "coverage.xml" in job["artifacts"]["paths"]
    assert job["artifacts"]["reports"]["coverage_report"] == {
        "coverage_format": "cobertura", "path": "coverage.xml"
    }
    assert any(
        "dropping stale src-tauri/target/llvm-cov-target" in command
        for command in job["before_script"]
    )
    # Do not turn the skipped secret scan into an optional job to mask the block.
    security = root["security:secrets"]
    assert security["extends"] == ".rules:gate"
    assert security["stage"] == "security"
    assert security.get("allow_failure", False) is False
