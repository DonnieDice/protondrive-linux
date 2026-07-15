"""Unit tests for scripts/patch_drive_linux_drawer.py.

Exercises the four drawer-rail sub-patches (DriveWindow.tsx, App.tsx,
DrawerSidebar.tsx, DrawerVisibilityButton.tsx) individually and via main().
"""

ORIGINAL_DRIVE_WINDOW = (
    "import { useLocation } from 'react-router-dom-v5-compat';\n"
    "\n"
    "import {\n"
    " ContactDrawerAppButton,\n"
    " DrawerVisibilityButton,\n"
    "} from './somewhere';\n"
    "\n"
    "const DriveWindow = () => {\n"
    " const { appInView, showDrawerSidebar } = useDrawer();\n"
    " const drawerSidebarButtons = [\n"
    " existingButton,\n"
    " ];\n"
    "};\n"
)

ORIGINAL_APP_TSX = (
    "import { DRAWER_VISIBILITY } from '@proton/shared/lib/interfaces';\n"
    "const settings = {\n"
    " showDrawerSidebar: userSettings.HideSidePanel === DRAWER_VISIBILITY.SHOW,\n"
    "};\n"
)

ORIGINAL_SIDEBAR = "className={clsx('drawer-sidebar hidden md:inline no-print', other)}"

ORIGINAL_VISIBILITY_BUTTON = "'drawer-visibility-control hidden md:flex',"


def _patch_paths(m, monkeypatch, tmp_path, **overrides):
    drive_window = tmp_path / "DriveWindow.tsx"
    app_tsx = tmp_path / "App.tsx"
    sidebar = tmp_path / "DrawerSidebar.tsx"
    visibility = tmp_path / "DrawerVisibilityButton.tsx"

    monkeypatch.setattr(m, "DRIVE_WINDOW_CANDIDATES", overrides.get("drive_window_candidates", [drive_window]))
    monkeypatch.setattr(m, "DRIVE_APP", overrides.get("drive_app", app_tsx))
    monkeypatch.setattr(m, "DRAWER_SIDEBAR_CANDIDATES", overrides.get("sidebar_candidates", [sidebar]))
    monkeypatch.setattr(m, "DRAWER_VISIBILITY_CANDIDATES", overrides.get("visibility_candidates", [visibility]))
    monkeypatch.setattr(m, "WEBCLIENTS_DIR", tmp_path)
    return drive_window, app_tsx, sidebar, visibility


def test_patch_drive_window_fails_when_missing(patch_drive_linux_drawer_module, monkeypatch, tmp_path, capsys):
    m = patch_drive_linux_drawer_module
    _patch_paths(m, monkeypatch, tmp_path, drive_window_candidates=[tmp_path / "missing.tsx"])
    try:
        m.patch_drive_window()
    except SystemExit as exc:
        assert exc.code == 1
        assert "Unable to find DriveWindow.tsx" in capsys.readouterr().err
        return
    raise AssertionError("expected SystemExit")


def test_patch_drive_window_applies_linux_button(patch_drive_linux_drawer_module, monkeypatch, tmp_path):
    m = patch_drive_linux_drawer_module
    drive_window, *_ = _patch_paths(m, monkeypatch, tmp_path)
    drive_window.write_text(ORIGINAL_DRIVE_WINDOW, encoding="utf-8")

    m.patch_drive_window()

    patched = drive_window.read_text(encoding="utf-8")
    assert "protondrive-linux-drawer-app-button:linux-icon" in patched
    assert "import { c } from 'ttag';" in patched
    assert " DrawerAppButton,\n" in patched
    assert " Icon,\n" in patched
    assert "toggleDrawerApp" in patched
    # the pre-existing button stays after the newly-prepended Linux entry
    assert patched.index("protondrive-linux-drawer-app-button") < patched.index("existingButton")


def test_patch_drive_window_skips_when_already_present(
    patch_drive_linux_drawer_module, monkeypatch, tmp_path, capsys
):
    m = patch_drive_linux_drawer_module
    drive_window, *_ = _patch_paths(m, monkeypatch, tmp_path)
    already = ORIGINAL_DRIVE_WINDOW.replace(
        "existingButton", "protondrive-linux-drawer-app-button:linux-icon"
    )
    drive_window.write_text(already, encoding="utf-8")

    m.patch_drive_window()
    assert "already present" in capsys.readouterr().out
    assert drive_window.read_text(encoding="utf-8") == already


def test_patch_drive_app_fails_when_missing(patch_drive_linux_drawer_module, monkeypatch, tmp_path, capsys):
    m = patch_drive_linux_drawer_module
    _patch_paths(m, monkeypatch, tmp_path, drive_app=tmp_path / "missing-app.tsx")
    try:
        m.patch_drive_app()
    except SystemExit as exc:
        assert exc.code == 1
        assert "Unable to find Drive App.tsx" in capsys.readouterr().err
        return
    raise AssertionError("expected SystemExit")


def test_patch_drive_app_forces_drawer_visible(patch_drive_linux_drawer_module, monkeypatch, tmp_path):
    m = patch_drive_linux_drawer_module
    _, app_tsx, _, _ = _patch_paths(m, monkeypatch, tmp_path)
    app_tsx.write_text(ORIGINAL_APP_TSX, encoding="utf-8")

    m.patch_drive_app()

    patched = app_tsx.read_text(encoding="utf-8")
    assert "showDrawerSidebar: true," in patched
    assert "DRAWER_VISIBILITY" not in patched  # unused import removed


def test_patch_drive_app_skips_when_already_patched(
    patch_drive_linux_drawer_module, monkeypatch, tmp_path, capsys
):
    m = patch_drive_linux_drawer_module
    _, app_tsx, _, _ = _patch_paths(m, monkeypatch, tmp_path)
    already = "Proton Drive Linux owns native sync/settings controls in this rail.\nshowDrawerSidebar: true,\n"
    app_tsx.write_text(already, encoding="utf-8")

    m.patch_drive_app()
    assert app_tsx.read_text(encoding="utf-8") == already


def test_patch_drawer_sidebar_skips_gracefully_when_missing(
    patch_drive_linux_drawer_module, monkeypatch, tmp_path, capsys
):
    m = patch_drive_linux_drawer_module
    _patch_paths(m, monkeypatch, tmp_path, sidebar_candidates=[tmp_path / "missing-sidebar.tsx"])
    m.patch_drawer_sidebar()
    assert "not found" in capsys.readouterr().out


def test_patch_drawer_sidebar_unhides_rail(patch_drive_linux_drawer_module, monkeypatch, tmp_path):
    m = patch_drive_linux_drawer_module
    _, _, sidebar, _ = _patch_paths(m, monkeypatch, tmp_path)
    sidebar.write_text(ORIGINAL_SIDEBAR, encoding="utf-8")

    m.patch_drawer_sidebar()

    patched = sidebar.read_text(encoding="utf-8")
    assert "'drawer-sidebar inline no-print'" in patched
    assert "hidden md:inline" not in patched


def test_patch_drawer_sidebar_skips_when_already_patched(
    patch_drive_linux_drawer_module, monkeypatch, tmp_path, capsys
):
    m = patch_drive_linux_drawer_module
    _, _, sidebar, _ = _patch_paths(m, monkeypatch, tmp_path)
    already = "className={clsx('drawer-sidebar inline no-print', other)}"
    sidebar.write_text(already, encoding="utf-8")

    m.patch_drawer_sidebar()
    assert "already patched" in capsys.readouterr().out
    assert sidebar.read_text(encoding="utf-8") == already


def test_patch_drawer_visibility_button_skips_gracefully_when_missing(
    patch_drive_linux_drawer_module, monkeypatch, tmp_path, capsys
):
    m = patch_drive_linux_drawer_module
    _patch_paths(m, monkeypatch, tmp_path, visibility_candidates=[tmp_path / "missing-visibility.tsx"])
    m.patch_drawer_visibility_button()
    assert "not found" in capsys.readouterr().out


def test_patch_drawer_visibility_button_unhides_chevron(patch_drive_linux_drawer_module, monkeypatch, tmp_path):
    m = patch_drive_linux_drawer_module
    _, _, _, visibility = _patch_paths(m, monkeypatch, tmp_path)
    visibility.write_text(ORIGINAL_VISIBILITY_BUTTON, encoding="utf-8")

    m.patch_drawer_visibility_button()

    patched = visibility.read_text(encoding="utf-8")
    assert "'drawer-visibility-control flex'" in patched
    assert "hidden md:flex" not in patched


def test_patch_drawer_visibility_button_skips_when_already_patched(
    patch_drive_linux_drawer_module, monkeypatch, tmp_path, capsys
):
    m = patch_drive_linux_drawer_module
    _, _, _, visibility = _patch_paths(m, monkeypatch, tmp_path)
    already = "'drawer-visibility-control flex',"
    visibility.write_text(already, encoding="utf-8")

    m.patch_drawer_visibility_button()
    assert "already patched" in capsys.readouterr().out
    assert visibility.read_text(encoding="utf-8") == already


def test_main_runs_all_four_patches_in_order(patch_drive_linux_drawer_module, monkeypatch, tmp_path):
    m = patch_drive_linux_drawer_module
    drive_window, app_tsx, sidebar, visibility = _patch_paths(m, monkeypatch, tmp_path)
    drive_window.write_text(ORIGINAL_DRIVE_WINDOW, encoding="utf-8")
    app_tsx.write_text(ORIGINAL_APP_TSX, encoding="utf-8")
    sidebar.write_text(ORIGINAL_SIDEBAR, encoding="utf-8")
    visibility.write_text(ORIGINAL_VISIBILITY_BUTTON, encoding="utf-8")

    m.main()

    assert "protondrive-linux-drawer-app-button:linux-icon" in drive_window.read_text(encoding="utf-8")
    assert "showDrawerSidebar: true," in app_tsx.read_text(encoding="utf-8")
    assert "'drawer-sidebar inline no-print'" in sidebar.read_text(encoding="utf-8")
    assert "'drawer-visibility-control flex'" in visibility.read_text(encoding="utf-8")
