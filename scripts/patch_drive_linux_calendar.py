#!/usr/bin/env python3
"""
Patch the WebClients drawer to load the calendar app from the locally
bundled /calendar/ path in Tauri desktop builds instead of calendar.proton.me.

Changes applied:
  1. useToggleDrawerApp.tsx — when window.__TAURI__ is present, use
     getAppHrefBundle() (local asset path) instead of getAppHref() (remote URL),
     and bypass the isAppReachable check so the locally-served calendar loads
     even when the network connectivity state is unknown.
  2. Also imports getAppHrefBundle which is not currently imported.
"""
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
WEBCLIENTS_DIR = REPO_ROOT / "WebClients"

TOGGLE_DRAWER = (
    WEBCLIENTS_DIR
    / "packages/components/hooks/drawer/useToggleDrawerApp.tsx"
)


def fail(message: str) -> None:
    print(f"  ❌ {message}", file=sys.stderr)
    sys.exit(1)


def replace_once(content: str, old: str, new: str, label: str) -> str:
    if old not in content:
        fail(f"patch_drive_linux_calendar: missing anchor — {label}")
    return content.replace(old, new, 1)


def main() -> None:
    if not TOGGLE_DRAWER.exists():
        fail(f"useToggleDrawerApp.tsx not found at {TOGGLE_DRAWER}")

    content = TOGGLE_DRAWER.read_text()

    if "__TAURI__" in content:
        print("  ⚠ Calendar Tauri patch already present — skipping")
        return

    # 1. Add getAppHrefBundle to the existing helper import
    content = replace_once(
        content,
        "import { getAppHref } from '@proton/shared/lib/apps/helper';",
        "import { getAppHref, getAppHrefBundle } from '@proton/shared/lib/apps/helper';",
        "helper import line",
    )

    # 2. Replace the iframe URL construction block with Tauri-aware version
    old_block = (
        "                if (!iframeSrcMap[app] && isAppReachable) {\n"
        "                    const localID = getLocalIDFromPathname(window.location.pathname);\n"
        "                    const appHref = getAppHref(path, app, localID);\n"
        "\n"
        "                    setIframeSrcMap((map) => ({\n"
        "                        ...map,\n"
        "                        [app]: addParentAppToUrl(appHref, currentApp),\n"
        "                    }));\n"
        "                }"
    )
    new_block = (
        "                // In Tauri desktop builds, iframed apps (calendar) are bundled\n"
        "                // locally under /calendar/ rather than loaded from Proton CDN.\n"
        "                // Use the local bundle path and skip the network-reachability\n"
        "                // gate so the drawer works even before API connectivity is confirmed.\n"
        "                const isTauri = !!(window as unknown as { __TAURI__?: unknown }).__TAURI__;\n"
        "                if (!iframeSrcMap[app] && (isAppReachable || isTauri)) {\n"
        "                    const localID = getLocalIDFromPathname(window.location.pathname);\n"
        "                    const appHref = isTauri\n"
        "                        ? getAppHrefBundle(path, app as Parameters<typeof getAppHrefBundle>[1])\n"
        "                        : getAppHref(path, app, localID);\n"
        "\n"
        "                    setIframeSrcMap((map) => ({\n"
        "                        ...map,\n"
        "                        [app]: isTauri ? appHref : addParentAppToUrl(appHref, currentApp),\n"
        "                    }));\n"
        "                }"
    )
    content = replace_once(content, old_block, new_block, "iframeSrcMap set block")

    TOGGLE_DRAWER.write_text(content)
    print(
        f"  ✓ Calendar Tauri URL patch applied to "
        f"{TOGGLE_DRAWER.relative_to(WEBCLIENTS_DIR)}"
    )


if __name__ == "__main__":
    main()
