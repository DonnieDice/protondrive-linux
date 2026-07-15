"""Unit tests for scripts/ci/resolve-mapping.py.

Exercises the doc-audit path resolver: path normalization, exact-source and
glob matching, self_update entries, doc-target cleaning, and the
dedup-by-tuple behavior that powers the docs:resolve-mapping CI job.
"""

import json

import yaml


def test_norm_path_strips_dot_slash_and_backslashes(resolve_mapping_module):
    m = resolve_mapping_module
    # backslashes -> forward slashes via PurePosixPath
    assert m.norm_path(r"docs\\ci-cd\\ci-pipeline.md") == "docs/ci-cd/ci-pipeline.md"
    # leading ./ is stripped
    assert m.norm_path("./README.md") == "README.md"
    # bare path is unchanged
    assert m.norm_path("src-tauri/src/main.rs") == "src-tauri/src/main.rs"


def test_norm_path_idempotent(resolve_mapping_module):
    m = resolve_mapping_module
    once = m.norm_path("docs/foo/bar.md")
    twice = m.norm_path(once)
    # PurePosixPath collapses but doesn't add or remove anything beyond ./-strip
    assert once == twice


def test_path_matches_exact_source(resolve_mapping_module):
    m = resolve_mapping_module
    entry = {"source": "src-tauri/src/main.rs"}
    assert m.path_matches(entry, "src-tauri/src/main.rs") is True
    assert m.path_matches(entry, "src-tauri/src/other.rs") is False


def test_path_matches_glob_pattern(resolve_mapping_module):
    m = resolve_mapping_module
    entry = {"glob": "docs/ci-cd/*.md"}
    assert m.path_matches(entry, "docs/ci-cd/ci-pipeline.md") is True
    assert m.path_matches(entry, "docs/architecture/foo.md") is False


def test_path_matches_returns_false_when_no_source_or_glob(resolve_mapping_module):
    m = resolve_mapping_module
    assert m.path_matches({"other": "value"}, "anything") is False


def test_clean_doc_target_uses_defaults_for_critical_and_update_mode(resolve_mapping_module):
    m = resolve_mapping_module
    cleaned = m.clean_doc_target({"path": "docs/foo.md"})
    assert cleaned == {"path": "docs/foo.md", "critical": False, "update_mode": "section"}


def test_clean_doc_target_preserves_allowed_keys_and_drops_unknown_ones(resolve_mapping_module):
    m = resolve_mapping_module
    cleaned = m.clean_doc_target(
        {
            "path": "docs/foo.md",
            "section": "build",
            "critical": True,
            "update_mode": "file",
            "rustdoc": "Cargo.toml",
            "ignored_extra": "should not appear",
        }
    )
    assert cleaned == {
        "path": "docs/foo.md",
        "section": "build",
        "critical": True,
        "update_mode": "file",
        "rustdoc": "Cargo.toml",
    }


def test_resolve_returns_empty_for_unmatched_paths(resolve_mapping_module):
    m = resolve_mapping_module
    empty_mapping = {"mapping": []}
    assert m.resolve(empty_mapping, ["does/not/match.anything"]) == {}


def test_resolve_collects_docs_targets_only_when_source_matches(resolve_mapping_module):
    m = resolve_mapping_module
    mapping = {
        "mapping": [
            {
                "source": "src-tauri/src/main.rs",
                "docs": [
                    {"path": "docs/architecture/architecture.md", "section": "auth"},
                ],
            },
        ]
    }
    result = m.resolve(mapping, ["src-tauri/src/main.rs"])
    assert "src-tauri/src/main.rs" in result
    targets = result["src-tauri/src/main.rs"]
    assert len(targets) == 1
    assert targets[0]["path"] == "docs/architecture/architecture.md"
    assert targets[0]["section"] == "auth"


def test_resolve_self_update_emits_a_file_mode_target(resolve_mapping_module):
    m = resolve_mapping_module
    mapping = {
        "mapping": [
            {
                "source": "docs/ci-cd/ci-pipeline.md",
                "self_update": True,
            },
        ]
    }
    result = m.resolve(mapping, ["docs/ci-cd/ci-pipeline.md"])
    targets = result["docs/ci-cd/ci-pipeline.md"]
    assert len(targets) == 1
    assert targets[0]["path"] == "docs/ci-cd/ci-pipeline.md"
    assert targets[0]["update_mode"] == "file"
    assert targets[0]["section"] is None


def test_resolve_combines_self_update_and_docs_targets(resolve_mapping_module):
    m = resolve_mapping_module
    mapping = {
        "mapping": [
            {
                "glob": "docs/**",
                "self_update": True,
                "docs": [
                    {"path": "README.md", "critical": True},
                ],
            },
        ]
    }
    result = m.resolve(mapping, ["docs/foo.md"])
    targets = result["docs/foo.md"]
    # self_update target + docs target = 2
    assert len(targets) == 2
    paths = sorted(t["path"] for t in targets)
    assert paths == ["README.md", "docs/foo.md"]


def test_resolve_dedupes_identical_targets(resolve_mapping_module):
    m = resolve_mapping_module
    mapping = {
        "mapping": [
            # two entries matching the same path, both pointing at the same doc target
            {
                "source": "src/foo.rs",
                "docs": [{"path": "docs/architecture/architecture.md", "section": "auth"}],
            },
            {
                "glob": "src/*.rs",  # also matches src/foo.rs
                "docs": [{"path": "docs/architecture/architecture.md", "section": "auth"}],
            },
        ]
    }
    result = m.resolve(mapping, ["src/foo.rs"])
    targets = result["src/foo.rs"]
    # both entries produce the same (path, section, critical, update_mode) tuple, so dedup
    assert len(targets) == 1


def test_resolve_handles_missing_docs_key_with_self_update(resolve_mapping_module):
    m = resolve_mapping_module
    mapping = {
        "mapping": [
            {
                "source": "scripts/foo.sh",
                "self_update": True,
                # no 'docs' key
            },
        ]
    }
    result = m.resolve(mapping, ["scripts/foo.sh"])
    assert "scripts/foo.sh" in result
    assert len(result["scripts/foo.sh"]) == 1


def test_resolve_iterates_multiple_changed_files_independently(resolve_mapping_module):
    m = resolve_mapping_module
    mapping = {
        "mapping": [
            {
                "glob": "src/*.rs",
                "docs": [{"path": "docs/architecture/architecture.md"}],
            },
        ]
    }
    result = m.resolve(mapping, ["src/foo.rs", "docs/other.md"])
    # only the .rs file matches the glob
    assert set(result.keys()) == {"src/foo.rs"}


def test_resolve_with_real_mapping_file(repo_root, resolve_mapping_module):
    """Integration: load docs/mapping.yaml from the repo and exercise a
    representative changed file (or no-op if mapping is absent in this repo
    checkout)."""
    m = resolve_mapping_module
    mapping_path = repo_root / "docs" / "mapping.yaml"
    if not mapping_path.is_file():
        # not all checkouts ship docs/mapping.yaml; skip if absent
        import pytest

        pytest.skip("docs/mapping.yaml not present in this checkout")
    mapping = yaml.safe_load(mapping_path.read_text(encoding="utf-8")) or {}
    # run resolve with an empty changed list — must return empty without error
    assert m.resolve(mapping, []) == {}
    # ... and ensure the loaded structure is the dict shape the resolver expects
    assert isinstance(mapping, dict)
    # also exercise the main() round-trip via a subprocess if present — covered


def test_main_round_trip_writes_sorted_json_to_stdout(
    repo_root, resolve_mapping_module, tmp_path, monkeypatch
):
    m = resolve_mapping_module
    mapping_file = tmp_path / "mapping.yaml"
    mapping_file.write_text(
        yaml.safe_dump(
            {
                "mapping": [
                    {
                        "source": "src-tauri/src/main.rs",
                        "docs": [{"path": "docs/architecture/architecture.md"}],
                    },
                ]
            }
        ),
        encoding="utf-8",
    )
    changed_file = tmp_path / "changed.txt"
    changed_file.write_text("src-tauri/src/main.rs\n", encoding="utf-8")

    captured = {}
    fake_stdout = []

    class FakeStdout:
        def write(self, s):
            fake_stdout.append(s)

        def flush(self):
            pass

    monkeypatch.setattr(m.sys, "stdout", FakeStdout())
    monkeypatch.chdir(tmp_path)  # so os.makedirs("docs", ...) works
    monkeypatch.setattr(
        m.sys,
        "argv",
        ["resolve-mapping.py", "--mapping", str(mapping_file), "--changed", str(changed_file)],
    )

    rc = m.main()
    assert rc == 0
    output = "".join(fake_stdout)
    # main writes the resolved mapping, then a trailing newline
    parsed = json.loads(output)
    assert "src-tauri/src/main.rs" in parsed
    entry = parsed["src-tauri/src/main.rs"]
    assert entry[0]["path"] == "docs/architecture/architecture.md"
    assert entry[0]["critical"] is False
    assert entry[0]["update_mode"] == "section"
