"""Unit tests for scripts/patch_drive_linux_panel.py.

Exercises injection of DriveLinuxPanel.tsx into the drawer components
directory and wiring it into DriveWindow.tsx as the QUICK_SETTINGS
customAppSettings.
"""

ORIGINAL_DRIVE_WINDOW = (
    "import DriveQuickSettings from '../drawer/DriveQuickSettings';\n"
    "\n"
    "const DriveWindow = () => (\n"
    "    drawerApp={<DrawerApp customAppSettings={<DriveQuickSettings />} />}\n"
    ");\n"
)


def test_fail_prints_to_stderr_and_exits_1(patch_drive_linux_panel_module, capsys):
    m = patch_drive_linux_panel_module
    try:
        m.fail("boom")
    except SystemExit as exc:
        assert exc.code == 1
        assert "boom" in capsys.readouterr().err
        return
    raise AssertionError("expected SystemExit")


def test_replace_once_raises_when_anchor_missing(patch_drive_linux_panel_module, capsys):
    m = patch_drive_linux_panel_module
    try:
        m.replace_once("content", "missing-anchor", "new", "my label")
    except SystemExit as exc:
        assert exc.code == 1
        assert "my label" in capsys.readouterr().err
        return
    raise AssertionError("expected SystemExit when anchor is absent")


def test_main_fails_when_drawer_dir_missing(patch_drive_linux_panel_module, monkeypatch, tmp_path, capsys):
    m = patch_drive_linux_panel_module
    monkeypatch.setattr(m, "DRAWER_DIR", tmp_path / "does-not-exist")
    try:
        m.main()
    except SystemExit as exc:
        assert exc.code == 1
        assert "drawer directory not found" in capsys.readouterr().err
        return
    raise AssertionError("expected SystemExit when drawer dir is missing")


def test_main_fails_when_drive_window_missing(patch_drive_linux_panel_module, monkeypatch, tmp_path, capsys):
    m = patch_drive_linux_panel_module
    drawer_dir = tmp_path / "drawer"
    drawer_dir.mkdir()
    monkeypatch.setattr(m, "DRAWER_DIR", drawer_dir)
    monkeypatch.setattr(m, "PANEL_COMPONENT", drawer_dir / "DriveLinuxPanel.tsx")
    monkeypatch.setattr(m, "DRIVE_WINDOW_CANDIDATES", [tmp_path / "DriveWindow.tsx"])
    monkeypatch.setattr(m, "WEBCLIENTS_DIR", tmp_path)
    try:
        m.main()
    except SystemExit as exc:
        assert exc.code == 1
        assert "DriveWindow.tsx not found" in capsys.readouterr().err
        return
    raise AssertionError("expected SystemExit when DriveWindow.tsx is missing")


def test_main_creates_panel_and_wires_into_drive_window(
    patch_drive_linux_panel_module, monkeypatch, tmp_path
):
    m = patch_drive_linux_panel_module
    drawer_dir = tmp_path / "drawer"
    drawer_dir.mkdir()
    panel_component = drawer_dir / "DriveLinuxPanel.tsx"
    drive_window = tmp_path / "DriveWindow.tsx"
    drive_window.write_text(ORIGINAL_DRIVE_WINDOW, encoding="utf-8")

    monkeypatch.setattr(m, "DRAWER_DIR", drawer_dir)
    monkeypatch.setattr(m, "PANEL_COMPONENT", panel_component)
    monkeypatch.setattr(m, "DRIVE_WINDOW_CANDIDATES", [drive_window])
    monkeypatch.setattr(m, "WEBCLIENTS_DIR", tmp_path)

    m.main()

    assert panel_component.exists()
    assert "DriveLinuxPanel" in panel_component.read_text(encoding="utf-8")

    wired = drive_window.read_text(encoding="utf-8")
    assert "import DriveLinuxPanel from '../drawer/DriveLinuxPanel';" in wired
    assert "drawerApp={<DrawerApp customAppSettings={<DriveLinuxPanel />} />}" in wired
    assert "customAppSettings={<DriveQuickSettings />}" not in wired


def test_main_skips_panel_write_when_already_present(
    patch_drive_linux_panel_module, monkeypatch, tmp_path, capsys
):
    m = patch_drive_linux_panel_module
    drawer_dir = tmp_path / "drawer"
    drawer_dir.mkdir()
    panel_component = drawer_dir / "DriveLinuxPanel.tsx"
    panel_component.write_text("export const DriveLinuxPanel = () => null;", encoding="utf-8")
    drive_window = tmp_path / "DriveWindow.tsx"
    drive_window.write_text(ORIGINAL_DRIVE_WINDOW, encoding="utf-8")

    monkeypatch.setattr(m, "DRAWER_DIR", drawer_dir)
    monkeypatch.setattr(m, "PANEL_COMPONENT", panel_component)
    monkeypatch.setattr(m, "DRIVE_WINDOW_CANDIDATES", [drive_window])
    monkeypatch.setattr(m, "WEBCLIENTS_DIR", tmp_path)

    m.main()
    out = capsys.readouterr().out
    assert "already present" in out
    # existing (non-canonical) panel content left untouched
    assert panel_component.read_text(encoding="utf-8") == "export const DriveLinuxPanel = () => null;"


def test_main_skips_wiring_when_drive_window_already_wired(
    patch_drive_linux_panel_module, monkeypatch, tmp_path, capsys
):
    m = patch_drive_linux_panel_module
    drawer_dir = tmp_path / "drawer"
    drawer_dir.mkdir()
    panel_component = drawer_dir / "DriveLinuxPanel.tsx"
    drive_window = tmp_path / "DriveWindow.tsx"
    already_wired = "already uses DriveLinuxPanel somewhere"
    drive_window.write_text(already_wired, encoding="utf-8")

    monkeypatch.setattr(m, "DRAWER_DIR", drawer_dir)
    monkeypatch.setattr(m, "PANEL_COMPONENT", panel_component)
    monkeypatch.setattr(m, "DRIVE_WINDOW_CANDIDATES", [drive_window])
    monkeypatch.setattr(m, "WEBCLIENTS_DIR", tmp_path)

    m.main()
    out = capsys.readouterr().out
    assert "already uses DriveLinuxPanel" in out
    assert drive_window.read_text(encoding="utf-8") == already_wired
