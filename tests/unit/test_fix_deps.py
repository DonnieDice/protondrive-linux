"""Unit tests for scripts/fix_deps.py.

Exercises the four WebClients build fixups: stripping problematic
dependencies, patching the Drive build:web script, disabling SRI for
account/verify, and rewriting .yarnrc.yml — plus main()'s guard for a
missing WebClients checkout.
"""
import json


def _write_pkg(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data), encoding="utf-8")


def test_strip_problematic_deps_removes_bad_packages_from_all_sections(fix_deps_module, tmp_path):
    m = fix_deps_module
    webclients = tmp_path / "WebClients"
    pkg = webclients / "applications/drive/package.json"
    _write_pkg(
        pkg,
        {
            "dependencies": {"rowsncolumns-core": "1.0.0", "keep-me": "1.0.0"},
            "devDependencies": {"@proton/proton-meet": "1.0.0"},
            "peerDependencies": {"electron": "1.0.0"},
            "optionalDependencies": {"proton-foundation-search": "1.0.0"},
        },
    )

    count = m.strip_problematic_deps(webclients)

    assert count == 4
    data = json.loads(pkg.read_text(encoding="utf-8"))
    assert data["dependencies"] == {"keep-me": "1.0.0"}
    assert data["devDependencies"] == {}
    assert data["peerDependencies"] == {}
    assert data["optionalDependencies"] == {}


def test_strip_problematic_deps_skips_node_modules_and_yarn_dirs(fix_deps_module, tmp_path):
    m = fix_deps_module
    webclients = tmp_path / "WebClients"
    ignored = webclients / "node_modules/some-pkg/package.json"
    _write_pkg(ignored, {"dependencies": {"electron": "1.0.0"}})
    yarn_ignored = webclients / ".yarn/cache/package.json"
    _write_pkg(yarn_ignored, {"dependencies": {"electron": "1.0.0"}})

    count = m.strip_problematic_deps(webclients)

    assert count == 0
    assert json.loads(ignored.read_text(encoding="utf-8"))["dependencies"] == {"electron": "1.0.0"}


def test_strip_problematic_deps_leaves_clean_package_untouched(fix_deps_module, tmp_path):
    m = fix_deps_module
    webclients = tmp_path / "WebClients"
    pkg = webclients / "applications/account/package.json"
    _write_pkg(pkg, {"dependencies": {"react": "18.0.0"}})

    count = m.strip_problematic_deps(webclients)

    assert count == 0
    assert json.loads(pkg.read_text(encoding="utf-8")) == {"dependencies": {"react": "18.0.0"}}


def test_patch_drive_build_switches_sso_to_standalone_and_adds_no_sri(fix_deps_module, tmp_path):
    m = fix_deps_module
    webclients = tmp_path / "WebClients"
    pkg = webclients / "applications/drive/package.json"
    _write_pkg(pkg, {"scripts": {"build:web": "proton-pack build --appMode=sso --api=https://x"}})

    m.patch_drive_build(webclients)

    data = json.loads(pkg.read_text(encoding="utf-8"))
    script = data["scripts"]["build:web"]
    assert "--appMode=standalone" in script
    assert "--api=" not in script
    assert "--no-sri" in script


def test_patch_drive_build_is_idempotent(fix_deps_module, tmp_path, capsys):
    m = fix_deps_module
    webclients = tmp_path / "WebClients"
    pkg = webclients / "applications/drive/package.json"
    _write_pkg(pkg, {"scripts": {"build:web": "proton-pack build --appMode=standalone --no-sri"}})

    m.patch_drive_build(webclients)

    assert "already configured" in capsys.readouterr().out


def test_patch_drive_build_warns_when_package_missing(fix_deps_module, tmp_path, capsys):
    m = fix_deps_module
    m.patch_drive_build(tmp_path / "WebClients")
    assert "Could not find drive package.json" in capsys.readouterr().out


def test_disable_sri_for_apps_adds_flag_to_account_and_verify(fix_deps_module, tmp_path):
    m = fix_deps_module
    webclients = tmp_path / "WebClients"
    account_pkg = webclients / "applications/account/package.json"
    verify_pkg = webclients / "applications/verify/package.json"
    _write_pkg(account_pkg, {"scripts": {"build:web": "proton-pack build"}})
    _write_pkg(verify_pkg, {"scripts": {"build:web": "proton-pack build"}})

    m.disable_sri_for_apps(webclients)

    assert "--no-sri" in json.loads(account_pkg.read_text(encoding="utf-8"))["scripts"]["build:web"]
    assert "--no-sri" in json.loads(verify_pkg.read_text(encoding="utf-8"))["scripts"]["build:web"]


def test_disable_sri_for_apps_is_idempotent(fix_deps_module, tmp_path, capsys):
    m = fix_deps_module
    webclients = tmp_path / "WebClients"
    account_pkg = webclients / "applications/account/package.json"
    _write_pkg(account_pkg, {"scripts": {"build:web": "proton-pack build --no-sri"}})

    m.disable_sri_for_apps(webclients)

    assert "already disabled" in capsys.readouterr().out


def test_rewrite_yarnrc_strips_npm_scopes_and_registries_block(fix_deps_module):
    m = fix_deps_module
    original = (
        "npmScopes:\n"
        "  proton:\n"
        "    npmAuthToken: secret\n"
        "npmRegistries:\n"
        "  //registry.internal:\n"
        "    npmAuthToken: secret\n"
        "yarnPath: .yarn/releases/yarn.cjs\n"
    )
    out = m.rewrite_yarnrc(original)
    assert "npmScopes" not in out
    assert "npmRegistries" not in out
    assert "secret" not in out
    assert "yarnPath: .yarn/releases/yarn.cjs" in out
    assert 'npmRegistryServer: "https://registry.npmjs.org"' in out
    assert "enableImmutableInstalls: false" in out


def test_rewrite_yarnrc_overrides_existing_registry_server(fix_deps_module):
    m = fix_deps_module
    original = 'npmRegistryServer: "https://npm.proton.internal"\n'
    out = m.rewrite_yarnrc(original)
    assert out.count("npmRegistryServer") == 1
    assert 'npmRegistryServer: "https://registry.npmjs.org"' in out


def test_rewrite_yarnrc_handles_empty_input(fix_deps_module):
    m = fix_deps_module
    out = m.rewrite_yarnrc("")
    assert 'npmRegistryServer: "https://registry.npmjs.org"' in out
    assert "enableImmutableInstalls: false" in out


def test_configure_yarn_writes_yarnrc_when_absent(fix_deps_module, tmp_path):
    m = fix_deps_module
    webclients = tmp_path / "WebClients"
    webclients.mkdir()
    m.configure_yarn(webclients)
    content = (webclients / ".yarnrc.yml").read_text(encoding="utf-8")
    assert 'npmRegistryServer: "https://registry.npmjs.org"' in content


def test_main_exits_when_webclients_missing(fix_deps_module, monkeypatch, tmp_path, capsys):
    m = fix_deps_module
    monkeypatch.chdir(tmp_path)
    try:
        m.main()
    except SystemExit as exc:
        assert exc.code == 1
        assert "WebClients directory not found" in capsys.readouterr().out
        return
    raise AssertionError("expected SystemExit when WebClients/ is missing")


def test_main_runs_all_fixups_end_to_end(fix_deps_module, monkeypatch, tmp_path):
    m = fix_deps_module
    monkeypatch.chdir(tmp_path)
    webclients = tmp_path / "WebClients"
    _write_pkg(webclients / "package.json", {"dependencies": {"electron": "1.0.0"}})
    _write_pkg(
        webclients / "applications/drive/package.json",
        {"scripts": {"build:web": "proton-pack build --appMode=sso"}},
    )
    _write_pkg(webclients / "applications/account/package.json", {"scripts": {"build:web": "proton-pack build"}})
    _write_pkg(webclients / "applications/verify/package.json", {"scripts": {"build:web": "proton-pack build"}})

    m.main()

    assert json.loads((webclients / "package.json").read_text(encoding="utf-8"))["dependencies"] == {}
    drive_script = json.loads(
        (webclients / "applications/drive/package.json").read_text(encoding="utf-8")
    )["scripts"]["build:web"]
    assert "--appMode=standalone" in drive_script and "--no-sri" in drive_script
    assert "--no-sri" in json.loads(
        (webclients / "applications/account/package.json").read_text(encoding="utf-8")
    )["scripts"]["build:web"]
    assert (webclients / ".yarnrc.yml").exists()
