"""Unit tests for scripts/create_stubs.py.

Exercises the stub-package layout helper (stub_dir_for), the per-package
writer (write_stub), and the end-to-end main() that stubs out
@proton/collect-metrics and @proton/proton-foundation-search.
"""
import json


def test_stub_dir_for_scoped_package(create_stubs_module, tmp_path):
    m = create_stubs_module
    out = m.stub_dir_for(tmp_path, "@proton/collect-metrics")
    assert out == tmp_path / "node_modules" / "@proton" / "collect-metrics"


def test_stub_dir_for_unscoped_package(create_stubs_module, tmp_path):
    m = create_stubs_module
    out = m.stub_dir_for(tmp_path, "lodash")
    assert out == tmp_path / "node_modules" / "lodash"


def test_write_stub_creates_package_json_and_index_js(create_stubs_module, tmp_path):
    m = create_stubs_module
    stub_dir = m.write_stub(tmp_path, "@proton/collect-metrics")

    assert stub_dir == tmp_path / "node_modules" / "@proton" / "collect-metrics"
    pkg_json = json.loads((stub_dir / "package.json").read_text(encoding="utf-8"))
    assert pkg_json["name"] == "@proton/collect-metrics"
    assert pkg_json["version"] == "0.0.0-stub"

    index_js = (stub_dir / "index.js").read_text(encoding="utf-8")
    assert "WebpackCollectMetricsPlugin" in index_js


def test_write_stub_creates_parent_directories(create_stubs_module, tmp_path):
    m = create_stubs_module
    webclients = tmp_path / "does" / "not" / "exist" / "yet"
    stub_dir = m.write_stub(webclients, "@proton/proton-foundation-search")
    assert stub_dir.is_dir()
    assert (stub_dir / "index.js").exists()


def test_main_creates_both_stub_packages(create_stubs_module, monkeypatch, tmp_path):
    m = create_stubs_module
    monkeypatch.chdir(tmp_path)

    m.main()

    metrics_dir = tmp_path / "WebClients/node_modules/@proton/collect-metrics"
    search_dir = tmp_path / "WebClients/node_modules/@proton/proton-foundation-search"
    assert (metrics_dir / "package.json").exists()
    assert (metrics_dir / "index.js").exists()
    assert (search_dir / "package.json").exists()
    assert (search_dir / "index.js").exists()

    search_index = (search_dir / "index.js").read_text(encoding="utf-8")
    assert "class Engine" in search_index
    assert "module.exports" in search_index
