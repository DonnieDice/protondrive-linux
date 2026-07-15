"""Unit tests for scripts/ci/apply-doc-patch.py.

Exercises the AI-doc update applier: section-marker replacement, full-file
mode, atomic write (preserves original on error), and the path guard that
blocks writing outside docs/ or README.md.
"""

import os
import sys


def test_replace_section_swaps_content_between_markers(apply_doc_patch_module):
    m = apply_doc_patch_module
    original = (
        "intro\n"
        "\n"
        "<!-- BEGIN SECTION: build -->\n"
        "old body\n"
        "more old body\n"
        "<!-- END SECTION: build -->\n"
        "\n"
        "outro\n"
    )
    out = m.replace_section(original, "build", "new body\nsecond line")
    assert "BEGIN SECTION: build" in out
    assert "END SECTION: build" in out
    assert "new body\nsecond line" in out
    assert "old body" not in out
    assert "more old body" not in out
    # untouched prefix/suffix preserved
    assert out.startswith("intro\n")
    assert out.rstrip().endswith("outro")


def test_replace_section_raises_when_section_marker_missing(apply_doc_patch_module):
    m = apply_doc_patch_module
    original = "no markers here at all"
    try:
        m.replace_section(original, "build", "new body")
    except SystemExit as exc:
        assert "section markers not found" in str(exc)
        return
    raise AssertionError("expected SystemExit for missing section markers")


def test_replace_section_raises_when_end_marker_before_start(apply_doc_patch_module):
    m = apply_doc_patch_module
    # pathological: END before BEGIN
    original = (
        "<!-- END SECTION: build -->\n"
        "<!-- BEGIN SECTION: build -->\n"
    )
    try:
        m.replace_section(original, "build", "new body")
    except SystemExit as exc:
        assert "section markers not found" in str(exc)
        return
    raise AssertionError("expected SystemExit when END precedes BEGIN")


def test_atomic_write_writes_content_and_cleans_up_temp_file(apply_doc_patch_module, tmp_path):
    m = apply_doc_patch_module
    target = tmp_path / "doc.md"
    target.write_text("before", encoding="utf-8")
    m.atomic_write(str(target), "after\n")
    assert target.read_text(encoding="utf-8") == "after\n"
    # no leftover .doc-update.* temp files in the directory
    leftovers = [p for p in tmp_path.iterdir() if p.name.startswith(".doc-update.")]
    assert leftovers == []


def test_atomic_write_preserves_existing_file_on_oserror(apply_doc_patch_module, tmp_path, monkeypatch):
    m = apply_doc_patch_module
    target = tmp_path / "doc.md"
    target.write_text("keep me", encoding="utf-8")

    # sabotage os.replace so it raises — original content must remain intact
    def boom(_src, _dst):
        raise OSError("simulated replace failure")

    monkeypatch.setattr(m.os, "replace", boom)
    try:
        m.atomic_write(str(target), "would be written\n")
    except OSError:
        pass
    assert target.read_text(encoding="utf-8") == "keep me"
    # temp file should be cleaned up by the finally block even on error
    leftovers = [p for p in tmp_path.iterdir() if p.name.startswith(".doc-update.")]
    assert leftovers == []


def test_main_rejects_non_doc_paths(apply_doc_patch_module, tmp_path, monkeypatch, capsys):
    m = apply_doc_patch_module
    monkeypatch.setattr(
        m.sys,
        "argv",
        ["apply-doc-patch.py", "--path", "/etc/passwd", "--mode", "file"],
    )
    try:
        m.main()
    except SystemExit as exc:
        assert "refusing to edit non-doc path" in str(exc)
        return
    raise AssertionError("expected SystemExit for non-doc path")


def test_main_section_mode_requires_section_arg(apply_doc_patch_module, monkeypatch, tmp_path):
    m = apply_doc_patch_module
    # build a valid doc file under tmp_path/docs so the path starts with "docs/"
    doc = tmp_path / "docs" / "example.md"
    doc.parent.mkdir(parents=True)
    doc.write_text(
        "<!-- BEGIN SECTION: x -->\nold\n<!-- END SECTION: x -->\n",
        encoding="utf-8",
    )
    monkeypatch.chdir(tmp_path)
    # forward-slash path so the script's args.path.startswith("docs/") guard passes
    monkeypatch.setattr(
        m.sys, "argv", ["apply-doc-patch.py", "--path", "docs/example.md", "--mode", "section"]
    )
    # no --section; must exit with the explanatory message
    monkeypatch.setattr(m.sys, "stdin", _FakeStdin("new content"))
    try:
        m.main()
    except SystemExit as exc:
        assert "section update requires --section" in str(exc)
        return
    raise AssertionError("expected SystemExit when --mode=section without --section")


def test_main_section_mode_replaces_marked_section_on_disk(
    apply_doc_patch_module, monkeypatch, tmp_path
):
    m = apply_doc_patch_module
    doc = tmp_path / "docs" / "ci-pipeline.md"
    doc.parent.mkdir(parents=True)
    doc.write_text(
        "<!-- BEGIN SECTION: build-overview -->\nold content\n<!-- END SECTION: build-overview -->\n",
        encoding="utf-8",
    )
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(
        m.sys,
        "argv",
        [
            "apply-doc-patch.py",
            "--path",
            "docs/ci-pipeline.md",  # forward-slash, matches the path guard
            "--mode",
            "section",
            "--section",
            "build-overview",
        ],
    )
    monkeypatch.setattr(m.sys, "stdin", _FakeStdin("new content\nwith two lines"))
    rc = m.main()
    assert rc == 0
    new_text = doc.read_text(encoding="utf-8")
    assert "new content\nwith two lines" in new_text
    assert "old content" not in new_text
    # markers preserved
    assert "BEGIN SECTION: build-overview" in new_text
    assert "END SECTION: build-overview" in new_text


def test_main_file_mode_overwrites_entire_file(apply_doc_patch_module, monkeypatch, tmp_path):
    m = apply_doc_patch_module
    doc = tmp_path / "README.md"
    doc.write_text("old readme\n", encoding="utf-8")
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(
        m.sys, "argv", ["apply-doc-patch.py", "--path", "README.md", "--mode", "file"]
    )
    monkeypatch.setattr(m.sys, "stdin", _FakeStdin("entirely new readme\n"))
    rc = m.main()
    assert rc == 0
    assert doc.read_text(encoding="utf-8") == "entirely new readme\n"


def test_main_refuses_empty_stdin(apply_doc_patch_module, monkeypatch, tmp_path):
    m = apply_doc_patch_module
    doc = tmp_path / "README.md"
    doc.write_text("x", encoding="utf-8")
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(
        m.sys, "argv", ["apply-doc-patch.py", "--path", "README.md", "--mode", "file"]
    )
    monkeypatch.setattr(m.sys, "stdin", _FakeStdin("   \n   "))  # whitespace only
    try:
        m.main()
    except SystemExit as exc:
        assert "refusing to apply empty doc update" in str(exc)
        return
    raise AssertionError("expected SystemExit for empty stdin")


class _FakeStdin:
    """Minimal stdin replacement with .read() and .strip()."""

    def __init__(self, content: str):
        self._content = content

    def read(self) -> str:
        return self._content

    def strip(self) -> str:
        return self._content.strip()
