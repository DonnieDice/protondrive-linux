#!/usr/bin/env python3
"""Apply all drawer-rail patches for Proton Drive Linux.

This script is the Python fallback when `git apply` fails on the common
patches (add-drive-linux-drawer-rail.patch and
show-drive-drawer-rail-in-desktop-shell.patch).  It handles three files:

1. DriveWindow.tsx – add the Linux drawer app button
2. App.tsx          – force drawer sidebar visible, drop DRAWER_VISIBILITY
3. DrawerSidebar.tsx – unhide the rail on small screens
4. DrawerVisibilityButton.tsx – unhide the chevron on small screens
"""
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
WEBCLIENTS_DIR = REPO_ROOT / "WebClients"
DRIVE_WINDOW_CANDIDATES = [
    WEBCLIENTS_DIR / "applications/drive/src/app/components/layout/DriveWindow.tsx",
    WEBCLIENTS_DIR / "applications/drive/src/app/legacy/components/layout/DriveWindow.tsx",
]
DRIVE_APP = WEBCLIENTS_DIR / "applications/drive/src/app/App.tsx"
DRAWER_SIDEBAR_CANDIDATES = [
    WEBCLIENTS_DIR / "packages/components/components/drawer/DrawerSidebar.tsx",
]
DRAWER_VISIBILITY_CANDIDATES = [
    WEBCLIENTS_DIR / "packages/components/components/drawer/DrawerVisibilityButton.tsx",
]


def fail(message: str) -> None:
    print(f" ❌ {message}", file=sys.stderr)
    sys.exit(1)


def replace_once(content: str, old: str, new: str, label: str) -> str:
    if old not in content:
        fail(f"Unable to patch Drive drawer: missing {label}")
    return content.replace(old, new, 1)


def patch_drive_window() -> None:
    drive_window = next((path for path in DRIVE_WINDOW_CANDIDATES if path.exists()), None)
    if drive_window is None:
        fail("Unable to find DriveWindow.tsx in current WebClients layout")

    content = drive_window.read_text()
    if "protondrive-linux-drawer-app-button:linux-icon" in content:
        print(" ⚠ Linux drawer entry already present - skipping")
    else:
        if "import { c } from 'ttag';" not in content:
            content = replace_once(
                content,
                "import { useLocation } from 'react-router-dom-v5-compat';\n\n",
                "import { useLocation } from 'react-router-dom-v5-compat';\n\nimport { c } from 'ttag';\n\n",
                "ttag import anchor",
            )

        if " DrawerAppButton,\n" not in content:
            content = replace_once(
                content,
                " ContactDrawerAppButton,\n",
                " ContactDrawerAppButton,\n DrawerAppButton,\n",
                "DrawerAppButton import anchor",
            )

        if " Icon,\n" not in content:
            content = replace_once(
                content,
                " DrawerVisibilityButton,\n",
                " DrawerVisibilityButton,\n Icon,\n",
                "Icon import anchor",
            )

        content = replace_once(
            content,
            " const { appInView, showDrawerSidebar } = useDrawer();",
            " const { appInView, showDrawerSidebar, toggleDrawerApp } = useDrawer();",
            "useDrawer destructuring",
        )

        linux_button = """ <DrawerAppButton
 key="toggle-protondrive-linux-drawer-app-button"
 tooltipText={c('Title').t`Proton Drive Linux`}
 data-testid="protondrive-linux-drawer-app-button:linux-icon"
 buttonContent={<Icon name="brand-linux" size={5} />}
 onClick={() => toggleDrawerApp({ app: DRAWER_NATIVE_APPS.QUICK_SETTINGS })()}
 alt={c('Action').t`Toggle Proton Drive Linux options`}
 aria-controls="drawer-app-protondrive-linux"
 aria-expanded={isAppInView(DRAWER_NATIVE_APPS.QUICK_SETTINGS, appInView)}
 />,
"""
        content = replace_once(
            content,
            " const drawerSidebarButtons = [\n",
            " const drawerSidebarButtons = [\n" + linux_button,
            "drawerSidebarButtons anchor",
        )

        drive_window.write_text(content)
        print(f" ✓ Applied Linux drawer entry to {drive_window.relative_to(WEBCLIENTS_DIR)}")


def patch_drive_app() -> None:
    if not DRIVE_APP.exists():
        fail("Unable to find Drive App.tsx in current WebClients layout")

    app_content = DRIVE_APP.read_text()
    if "Proton Drive Linux owns native sync/settings controls in this rail." not in app_content:
        app_content = app_content.replace(
            "import { DRAWER_VISIBILITY } from '@proton/shared/lib/interfaces';\n", "", 1
        )
        app_content = replace_once(
            app_content,
            " showDrawerSidebar: userSettings.HideSidePanel === DRAWER_VISIBILITY.SHOW,\n",
            " // Proton Drive Linux owns native sync/settings controls in this rail.\n"
            " // Keep it visible by default so the Linux controls, Contacts,\n"
            " // Calendar, and Referral entries are reachable in packaged\n"
            " // desktop builds. The chevron can still collapse it.\n"
            " showDrawerSidebar: true,\n",
            "Drive drawer default visibility",
        )
        DRIVE_APP.write_text(app_content)
        print(f" ✓ Forced Drive drawer rail visible by default in {DRIVE_APP.relative_to(WEBCLIENTS_DIR)}")


def patch_drawer_sidebar() -> None:
    """Unhide the drawer sidebar on small/desktop screens.

    Original:  className={clsx('drawer-sidebar hidden md:inline no-print', ...)}
    Patched:   className={clsx('drawer-sidebar inline no-print', ...)}
    """
    sidebar = next((p for p in DRAWER_SIDEBAR_CANDIDATES if p.exists()), None)
    if sidebar is None:
        print(" ⚠ DrawerSidebar.tsx not found – skipping sidebar visibility patch")
        return

    content = sidebar.read_text()
    if "drawer-sidebar inline no-print" in content:
        print(" ⚠ DrawerSidebar already patched – skipping")
        return

    content = replace_once(
        content,
        "'drawer-sidebar hidden md:inline no-print'",
        "'drawer-sidebar inline no-print'",
        "DrawerSidebar hidden class",
    )
    sidebar.write_text(content)
    print(f" ✓ Unhid drawer sidebar in {sidebar.relative_to(WEBCLIENTS_DIR)}")


def patch_drawer_visibility_button() -> None:
    """Unhide the drawer visibility chevron on small screens.

    Original:  'drawer-visibility-control hidden md:flex',
    Patched:   'drawer-visibility-control flex',
    """
    button = next((p for p in DRAWER_VISIBILITY_CANDIDATES if p.exists()), None)
    if button is None:
        print(" ⚠ DrawerVisibilityButton.tsx not found – skipping visibility button patch")
        return

    content = button.read_text()
    if "'drawer-visibility-control flex'" in content:
        print(" ⚠ DrawerVisibilityButton already patched – skipping")
        return

    content = replace_once(
        content,
        "'drawer-visibility-control hidden md:flex'",
        "'drawer-visibility-control flex'",
        "DrawerVisibilityButton hidden class",
    )
    button.write_text(content)
    print(f" ✓ Unhid drawer visibility button in {button.relative_to(WEBCLIENTS_DIR)}")


def main() -> None:
    patch_drive_window()
    patch_drive_app()
    patch_drawer_sidebar()
    patch_drawer_visibility_button()


if __name__ == "__main__":
    main()
