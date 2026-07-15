"""Unit tests for scripts/patch_drive_linux_sync_bridge.py.

Exercises the DriveProvider discovery (find_drive_provider), the wiring of
ProtonDriveLinuxSyncBridge into it (patch_drive_provider), and the end-to-end
main() that also writes the bridge component file.
"""

DRIVE_PROVIDER_SOURCE = (
    "import { PublicSessionProvider } from './_api';\n"
    "\n"
    "export function DriveProvider({ children }) {\n"
    "    return (\n"
    "        <div>\n"
    "            <PublicSessionProvider>\n"
    "                                <UploadProvider>\n"
    "                                    <SearchProvider>\n"
    "                        {children}\n"
    "                    </SearchProvider>\n"
    "                </UploadProvider>\n"
    "            </PublicSessionProvider>\n"
    "        </div>\n"
    "    );\n"
    "}\n"
)


def test_fail_raises_systemexit_with_message(patch_drive_linux_sync_bridge_module):
    m = patch_drive_linux_sync_bridge_module
    try:
        m.fail("something broke")
    except SystemExit as exc:
        assert "something broke" in str(exc)
        return
    raise AssertionError("expected SystemExit")


def test_find_drive_provider_locates_matching_file(
    patch_drive_linux_sync_bridge_module, monkeypatch, tmp_path
):
    m = patch_drive_linux_sync_bridge_module
    app_dir = tmp_path / "applications/drive/src/app"
    app_dir.mkdir(parents=True)
    # a decoy file that doesn't have both markers
    (app_dir / "NotProvider.tsx").write_text("export function DriveProvider", encoding="utf-8")
    real = app_dir / "DriveProvider.tsx"
    real.write_text(DRIVE_PROVIDER_SOURCE, encoding="utf-8")

    monkeypatch.setattr(m, "DRIVE_APP_DIR", app_dir)
    found = m.find_drive_provider()
    assert found == real


def test_find_drive_provider_fails_when_absent(
    patch_drive_linux_sync_bridge_module, monkeypatch, tmp_path
):
    m = patch_drive_linux_sync_bridge_module
    app_dir = tmp_path / "applications/drive/src/app"
    app_dir.mkdir(parents=True)
    monkeypatch.setattr(m, "DRIVE_APP_DIR", app_dir)
    try:
        m.find_drive_provider()
    except SystemExit as exc:
        assert "Unable to find DriveProvider.tsx" in str(exc)
        return
    raise AssertionError("expected SystemExit")


def test_patch_drive_provider_inserts_import_and_bridge_component(
    patch_drive_linux_sync_bridge_module, tmp_path
):
    m = patch_drive_linux_sync_bridge_module
    provider = tmp_path / "DriveProvider.tsx"
    provider.write_text(DRIVE_PROVIDER_SOURCE, encoding="utf-8")

    m.patch_drive_provider(provider)

    patched = provider.read_text(encoding="utf-8")
    assert "import { ProtonDriveLinuxSyncBridge } from './ProtonDriveLinuxSyncBridge';" in patched
    assert "<ProtonDriveLinuxSyncBridge />" in patched
    # bridge must sit inside UploadProvider, before SearchProvider
    assert patched.index("<UploadProvider>") < patched.index("<ProtonDriveLinuxSyncBridge />")
    assert patched.index("<ProtonDriveLinuxSyncBridge />") < patched.index("<SearchProvider>")


def test_patch_drive_provider_is_idempotent(patch_drive_linux_sync_bridge_module, tmp_path):
    m = patch_drive_linux_sync_bridge_module
    provider = tmp_path / "DriveProvider.tsx"
    provider.write_text(DRIVE_PROVIDER_SOURCE, encoding="utf-8")

    m.patch_drive_provider(provider)
    once = provider.read_text(encoding="utf-8")
    m.patch_drive_provider(provider)
    twice = provider.read_text(encoding="utf-8")

    assert once == twice
    assert twice.count("<ProtonDriveLinuxSyncBridge />") == 1
    assert twice.count("import { ProtonDriveLinuxSyncBridge }") == 1


def test_main_fails_when_webclients_dir_missing(
    patch_drive_linux_sync_bridge_module, monkeypatch, tmp_path
):
    m = patch_drive_linux_sync_bridge_module
    monkeypatch.setattr(m, "WEBCLIENTS_DIR", tmp_path / "does-not-exist")
    try:
        m.main()
    except SystemExit as exc:
        assert "WebClients directory is missing" in str(exc)
        return
    raise AssertionError("expected SystemExit")


def test_main_writes_bridge_file_and_wires_provider(
    patch_drive_linux_sync_bridge_module, monkeypatch, tmp_path
):
    m = patch_drive_linux_sync_bridge_module
    webclients_dir = tmp_path / "WebClients"
    app_dir = webclients_dir / "applications/drive/src/app"
    app_dir.mkdir(parents=True)
    provider = app_dir / "DriveProvider.tsx"
    provider.write_text(DRIVE_PROVIDER_SOURCE, encoding="utf-8")

    monkeypatch.setattr(m, "WEBCLIENTS_DIR", webclients_dir)
    monkeypatch.setattr(m, "DRIVE_APP_DIR", app_dir)

    m.main()

    bridge_path = app_dir / m.BRIDGE_FILENAME
    assert bridge_path.exists()
    assert "ProtonDriveLinuxSyncBridge" in bridge_path.read_text(encoding="utf-8")
    assert "<ProtonDriveLinuxSyncBridge />" in provider.read_text(encoding="utf-8")
