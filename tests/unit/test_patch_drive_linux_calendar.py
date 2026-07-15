"""Unit tests for scripts/patch_drive_linux_calendar.py.

Exercises the Tauri-aware calendar drawer patch: the replace_once anchor
guard, the already-patched skip, and the end-to-end main() rewrite of
useToggleDrawerApp.tsx.
"""

ORIGINAL_TOGGLE_DRAWER = (
    "import { getAppHref } from '@proton/shared/lib/apps/helper';\n"
    "\n"
    "const useToggleDrawerApp = () => {\n"
    "    const toggle = () => {\n"
    "        if (something) {\n"
    "                if (!iframeSrcMap[app] && isAppReachable) {\n"
    "                    const localID = getLocalIDFromPathname(window.location.pathname);\n"
    "                    const appHref = getAppHref(path, app, localID);\n"
    "\n"
    "                    setIframeSrcMap((map) => ({\n"
    "                        ...map,\n"
    "                        [app]: addParentAppToUrl(appHref, currentApp),\n"
    "                    }));\n"
    "                }\n"
    "        }\n"
    "    };\n"
    "};\n"
)


def test_replace_once_raises_systemexit_when_anchor_missing(patch_drive_linux_calendar_module, capsys):
    m = patch_drive_linux_calendar_module
    try:
        m.replace_once("no anchor here", "missing", "replacement", "test anchor")
    except SystemExit as exc:
        assert exc.code == 1
        err = capsys.readouterr().err
        assert "missing anchor" in err
        assert "test anchor" in err
        return
    raise AssertionError("expected SystemExit when anchor is absent")


def test_replace_once_replaces_first_occurrence_only(patch_drive_linux_calendar_module):
    m = patch_drive_linux_calendar_module
    content = "foo foo foo"
    out = m.replace_once(content, "foo", "bar", "label")
    assert out == "bar foo foo"


def test_main_skips_when_toggle_drawer_missing(
    patch_drive_linux_calendar_module, monkeypatch, tmp_path, capsys
):
    m = patch_drive_linux_calendar_module
    monkeypatch.setattr(m, "TOGGLE_DRAWER", tmp_path / "does-not-exist.tsx")
    try:
        m.main()
    except SystemExit as exc:
        assert exc.code == 1
        assert "not found" in capsys.readouterr().err
        return
    raise AssertionError("expected SystemExit when useToggleDrawerApp.tsx is missing")


def test_main_skips_when_already_patched(patch_drive_linux_calendar_module, monkeypatch, tmp_path, capsys):
    m = patch_drive_linux_calendar_module
    toggle = tmp_path / "useToggleDrawerApp.tsx"
    toggle.write_text("already has __TAURI__ in it", encoding="utf-8")
    monkeypatch.setattr(m, "TOGGLE_DRAWER", toggle)
    m.main()
    out = capsys.readouterr().out
    assert "already present" in out
    # file must be untouched
    assert toggle.read_text(encoding="utf-8") == "already has __TAURI__ in it"


def test_main_applies_patch_end_to_end(patch_drive_linux_calendar_module, monkeypatch, tmp_path):
    m = patch_drive_linux_calendar_module
    toggle = tmp_path / "useToggleDrawerApp.tsx"
    toggle.write_text(ORIGINAL_TOGGLE_DRAWER, encoding="utf-8")
    monkeypatch.setattr(m, "TOGGLE_DRAWER", toggle)
    monkeypatch.setattr(m, "WEBCLIENTS_DIR", tmp_path)

    m.main()

    patched = toggle.read_text(encoding="utf-8")
    assert "getAppHrefBundle" in patched
    assert "import { getAppHref, getAppHrefBundle }" in patched
    assert "isTauri" in patched
    assert "__TAURI__" in patched


def test_main_raises_when_iframe_block_anchor_missing(
    patch_drive_linux_calendar_module, monkeypatch, tmp_path, capsys
):
    m = patch_drive_linux_calendar_module
    # helper import present, but the iframeSrcMap block is missing entirely
    toggle = tmp_path / "useToggleDrawerApp.tsx"
    toggle.write_text(
        "import { getAppHref } from '@proton/shared/lib/apps/helper';\nno iframe block here\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(m, "TOGGLE_DRAWER", toggle)
    monkeypatch.setattr(m, "WEBCLIENTS_DIR", tmp_path)
    try:
        m.main()
    except SystemExit as exc:
        assert exc.code == 1
        assert "iframeSrcMap set block" in capsys.readouterr().err
        return
    raise AssertionError("expected SystemExit when iframeSrcMap block anchor is missing")
