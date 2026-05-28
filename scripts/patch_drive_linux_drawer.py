#!/usr/bin/env python3
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
WEBCLIENTS_DIR = REPO_ROOT / "WebClients"
DRIVE_WINDOW_CANDIDATES = [
    WEBCLIENTS_DIR / "applications/drive/src/app/components/layout/DriveWindow.tsx",
    WEBCLIENTS_DIR / "applications/drive/src/app/legacy/components/layout/DriveWindow.tsx",
]
DRIVE_APP = WEBCLIENTS_DIR / "applications/drive/src/app/App.tsx"


def fail(message: str) -> None:
    print(f"  ❌ {message}", file=sys.stderr)
    sys.exit(1)


def replace_once(content: str, old: str, new: str, label: str) -> str:
    if old not in content:
        fail(f"Unable to patch Drive drawer: missing {label}")
    return content.replace(old, new, 1)


def main() -> None:
    drive_window = next((path for path in DRIVE_WINDOW_CANDIDATES if path.exists()), None)
    if drive_window is None:
        fail("Unable to find DriveWindow.tsx in current WebClients layout")

    content = drive_window.read_text()
    if "protondrive-linux-drawer-app-button:linux-icon" in content:
        print("  ⚠ Linux drawer entry already present - skipping")
    else:
        if "import { c } from 'ttag';" not in content:
            content = replace_once(
                content,
                "import { useLocation } from 'react-router-dom-v5-compat';\n\n",
                "import { useLocation } from 'react-router-dom-v5-compat';\n\nimport { c } from 'ttag';\n\n",
                "ttag import anchor",
            )

        if "    DrawerAppButton,\n" not in content:
            content = replace_once(
                content,
                "    ContactDrawerAppButton,\n",
                "    ContactDrawerAppButton,\n    DrawerAppButton,\n",
                "DrawerAppButton import anchor",
            )

        if "    Icon,\n" not in content:
            content = replace_once(
                content,
                "    DrawerVisibilityButton,\n",
                "    DrawerVisibilityButton,\n    Icon,\n",
                "Icon import anchor",
            )

        content = replace_once(
            content,
            "    const { appInView, showDrawerSidebar } = useDrawer();",
            "    const { appInView, showDrawerSidebar, toggleDrawerApp } = useDrawer();",
            "useDrawer destructuring",
        )

        linux_button = """        <DrawerAppButton
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
            "    const drawerSidebarButtons = [\n",
            "    const drawerSidebarButtons = [\n" + linux_button,
            "drawerSidebarButtons anchor",
        )

        drive_window.write_text(content)
        print(f"  ✓ Applied Linux drawer entry to {drive_window.relative_to(WEBCLIENTS_DIR)}")

    if not DRIVE_APP.exists():
        fail("Unable to find Drive App.tsx in current WebClients layout")

    app_content = DRIVE_APP.read_text()
    if "Proton Drive Linux owns native sync/settings controls in this rail." not in app_content:
        app_content = app_content.replace("import { DRAWER_VISIBILITY } from '@proton/shared/lib/interfaces';\n", "", 1)
        app_content = replace_once(
            app_content,
            "                    showDrawerSidebar: userSettings.HideSidePanel === DRAWER_VISIBILITY.SHOW,\n",
            "                    // Proton Drive Linux owns native sync/settings controls in this rail.\n"
            "                    // Keep it visible by default so the Linux controls, Contacts,\n"
            "                    // Calendar, and Referral entries are reachable in packaged\n"
            "                    // desktop builds. The chevron can still collapse it.\n"
            "                    showDrawerSidebar: true,\n",
            "Drive drawer default visibility",
        )
        DRIVE_APP.write_text(app_content)
        print(f"  ✓ Forced Drive drawer rail visible by default in {DRIVE_APP.relative_to(WEBCLIENTS_DIR)}")


if __name__ == "__main__":
    main()
